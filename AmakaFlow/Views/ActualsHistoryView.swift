//
//  ActualsHistoryView.swift
//  AmakaFlow
//
//  AMA-2396: Profile → History — Sync v2. Day-grouped Strava history with the
//  wrong-day bug fixed (bucketed by `start_date_local`, not UTC).
//

// swiftlint:disable file_length

import Combine
import OSLog
import SwiftUI

@MainActor
final class ActualsHistoryViewModel: ObservableObject {
    @Published private(set) var dayGroups: [(day: Date, cards: [ActualsTodayDemoCard])] = []
    @Published private(set) var isLoading = false
    @Published private(set) var daysBack = 30
    @Published var bannerExpanded = true

    private let client: BFFStravaClient
    private let calendar: Calendar
    private let now: () -> Date
    private let repository: ActualsRepository

    init(
        client: BFFStravaClient? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        repository: ActualsRepository? = nil
    ) {
        self.client = client ?? BFFStravaClient.live()
        self.calendar = calendar
        self.now = now
        self.repository = repository ?? ActualsRepository()
    }

    nonisolated deinit {}

    var totalSessions: Int {
        dayGroups.reduce(0) { $0 + $1.cards.count }
    }

    var needFillInCount: Int {
        dayGroups.reduce(0) { partial, group in
            partial + group.cards.filter { $0.kind == .unmapped || $0.kind == .fillInDebt || $0.kind == .merged }.count
        }
    }

    func loadIfNeeded() async {
        guard dayGroups.isEmpty, !isLoading else { return }
        await load(replacingExisting: true)
    }

    func loadMore() async {
        let previousDaysBack = daysBack
        let previousGroups = dayGroups
        daysBack += 30
        let loadSucceeded = await load(replacingExisting: true)
        if !loadSucceeded {
            // Failed pagination must not erase the window the athlete already has.
            daysBack = previousDaysBack
            dayGroups = previousGroups
        }
    }

    /// AMA-2407: Verify as-is — mark Verified in AmakaFlow, never touch Strava.
    func applyKeepAsIs(cardID: String) async {
        guard let card = card(withID: cardID) else { return }
        let session = ActualsTodayDemoFeed.makeVerifiedAsIsSession(
            cardID: card.id,
            title: card.title,
            activity: card.activity
        )
        do {
            try repository.upsertVerifiedAsIs(session)
        } catch {
            Logger(
                subsystem: "com.myamaka.AmakaFlowCompanion",
                category: "ActualsHistory"
            ).error(
                "Failed to persist verify-as-is for \(card.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
        let decoration = ActualsTodayDemoFeed.verifyAsIsDecoration(
            sourceProvider: card.sourceProvider ?? card.activity?.provider
        )
        try? repository.storeDecoration(decoration, forSessionID: session.id)
        mutateCard(id: cardID) { $0.markingVerifiedAsIs(with: session, decoration: decoration) }
        NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)

        guard let activityId = session.stravaActivityId else { return }
        do {
            _ = try await client.verifySession(activityId: activityId, amakaflowSessionId: session.id)
        } catch {
            Logger(
                subsystem: "com.myamaka.AmakaFlowCompanion",
                category: "ActualsHistory"
            ).error(
                "Strava verify call failed for activity \(activityId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// AMA-2405: cache Strava description after counted-detail lazy fetch.
    func applyActivityDescription(cardID: String, description: String) {
        mutateCard(id: cardID) { $0.withActivityDescription(description) }
        let activityId = card(withID: cardID)?.fillInSession?.stravaActivityId
            ?? ActualsTodayDemoFeed.stravaActivityId(fromCardID: cardID)
        guard let activityId, !activityId.isEmpty else { return }
        do {
            try repository.upsertStravaActivityDescription(
                activityId: activityId,
                description: description
            )
        } catch {
            // In-memory card already updated; keep UI and log for diagnosis.
            Logger(
                subsystem: "com.myamaka.AmakaFlowCompanion",
                category: "ActualsHistory"
            ).error(
                "Failed to persist Strava description for activity \(activityId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Map → library pick: attach plan + fill-in session (same as Today).
    @discardableResult
    func applyLibraryMatch(
        planTitle: String,
        cardID: String,
        workout: Workout? = nil
    ) -> ActualsTodayDemoCard? {
        guard let prior = card(withID: cardID) else { return nil }
        let summaries: [String] = {
            if let workout {
                let names = workout.blocks.flatMap(\.exercises).map(\.name)
                if !names.isEmpty { return names }
            }
            return [planTitle]
        }()
        let matched = ActualsTodayDemoFeed.makeMatchedCard(
            request: ActualsTodayDemoFeed.MatchedCardRequest(
                cardID: cardID,
                timeLabel: prior.timeLabel,
                title: planTitle,
                activity: prior.activity,
                blockSummaries: summaries,
                sourceLabel: "Matched · \(ActualsCopy.sourceDisplayName(prior.activity?.provider ?? .strava))",
                workout: workout
            )
        )
        if let session = matched.fillInSession {
            try? repository.upsertMatchedDraft(session)
            NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)
        }
        mutateCard(id: cardID) { _ in matched }
        return matched
    }

    @discardableResult
    func applyCaptureMatched(draft: ActualsCaptureDraft, cardID: String) -> ActualsTodayDemoCard? {
        guard let prior = card(withID: cardID) else { return nil }
        let matched = ActualsTodayDemoFeed.makeMatchedCard(
            request: ActualsTodayDemoFeed.MatchedCardRequest(
                cardID: cardID,
                timeLabel: prior.timeLabel,
                title: draft.title,
                activity: prior.activity,
                blockSummaries: draft.blockSummaries.isEmpty ? [draft.title] : draft.blockSummaries,
                sourceLabel: "Matched · \(ActualsCopy.sourceDisplayName(prior.activity?.provider ?? .strava))",
                workout: draft.toWorkoutForMatch()
            )
        )
        if let session = matched.fillInSession {
            try? repository.upsertMatchedDraft(session)
            NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)
        }
        mutateCard(id: cardID) { _ in matched }
        return matched
    }

    func markVerified(saved: ActualsFillInSession, cardID: String) {
        mutateCard(id: cardID) { $0.markingVerified(with: saved) }
        NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)
    }

    /// AMA-2407: un-verify clears local + server verified state (DELETE verify).
    func applyUnverify(cardID: String, session: ActualsFillInSession) async {
        try? repository.unverifySession(id: session.id)
        var draft = session
        draft.verified = false
        draft.rpe = nil
        mutateCard(id: cardID) { card in
            ActualsTodayDemoCard(
                id: card.id,
                kind: .fillInDebt,
                timeLabel: card.timeLabel,
                title: draft.title,
                stats: card.stats,
                sourceLabel: "Fill in · draft",
                sourceProvider: card.sourceProvider,
                session: card.session,
                activity: card.activity,
                fillInSession: draft,
                stravaDecoration: card.stravaDecoration
            )
        }
        NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)

        guard let activityId = session.stravaActivityId else { return }
        do {
            _ = try await client.unverifySession(activityId: activityId)
        } catch {
            Logger(
                subsystem: "com.myamaka.AmakaFlowCompanion",
                category: "ActualsHistory"
            ).error(
                "Strava un-verify call failed for activity \(activityId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Mid-edit Back — keep confirms / RPE on the History card + GRDB draft.
    func applyFillInDraft(session: ActualsFillInSession, cardID: String) {
        mutateCard(id: cardID) { $0.withFillInSession(session) }
        NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)
    }

    func card(withID id: String) -> ActualsTodayDemoCard? {
        for group in dayGroups {
            if let found = group.cards.first(where: { $0.id == id }) {
                return found
            }
        }
        return nil
    }

    private func mutateCard(id: String, transform: (ActualsTodayDemoCard) -> ActualsTodayDemoCard) {
        for groupIndex in dayGroups.indices {
            if let cardIndex = dayGroups[groupIndex].cards.firstIndex(where: { $0.id == id }) {
                var group = dayGroups[groupIndex]
                group.cards[cardIndex] = transform(group.cards[cardIndex])
                dayGroups[groupIndex] = group
                return
            }
        }
    }

    /// Returns `true` when groups were successfully replaced from the network.
    @discardableResult
    private func load(replacingExisting: Bool) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await client.syncCompleted(daysBack: daysBack)
            guard result.success else {
                if replacingExisting, dayGroups.isEmpty {
                    dayGroups = []
                }
                return false
            }
            let groups = ActualsTodayDemoFeed.historyCards(
                from: result.activities,
                calendar: calendar,
                now: now()
            )
            dayGroups = groups.map { group in
                (
                    day: group.day,
                    cards: ActualsTodayDemoFeed.applyLocalOverlays(
                        to: group.cards,
                        repository: repository
                    )
                )
            }
            return true
        } catch {
            // Never crash History on a missing/expired token — keep what we have.
            if dayGroups.isEmpty {
                dayGroups = []
            }
            return false
        }
    }
}

extension Notification.Name {
    /// Posted when a Strava card is matched or verified locally — Today re-applies overlays.
    static let actualsLocalSessionsDidChange = Notification.Name("ama2396.actualsLocalSessionsDidChange")
}

/// Navigation payload for History → Map (keeps card identity through match).
private struct HistoryMapRoute: Identifiable, Hashable {
    let cardID: String
    let activity: ActualsUnmappedActivity

    var id: String { "map-\(cardID)" }
}

private struct HistoryFillInRoute: Identifiable, Hashable {
    let cardID: String

    var id: String { "fill-\(cardID)" }
}

private struct HistoryVerifiedRoute: Identifiable, Hashable {
    let cardID: String

    var id: String { "verified-\(cardID)" }
}

// swiftlint:disable:next type_body_length
struct ActualsHistoryView: View {
    @StateObject private var viewModel: ActualsHistoryViewModel
    @State private var mapRoute: HistoryMapRoute?
    @State private var fillInRoute: HistoryFillInRoute?
    @State private var verifiedRoute: HistoryVerifiedRoute?
    @State private var libraryCandidates: [ActualsPlanCandidate] = ActualsTodayDemoFeed.samplePlanCandidates
    @State private var libraryWorkoutsByID: [String: Workout] = [:]
    @State private var showLibraryMatchPicker = false
    @State private var libraryPickerCardID: String?

    @MainActor
    init(viewModel: ActualsHistoryViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ActualsHistoryViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)

                banner
                    .padding(.top, 14)

                if viewModel.bannerExpanded {
                    dayList
                        .padding(.top, 14)

                    loadMoreButton
                        .padding(.top, 6)
                }

                legend
                    .padding(.top, 18)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadIfNeeded()
            await loadLibraryCandidates()
        }
        .navigationDestination(item: $mapRoute) { route in
            mapDestination(for: route)
        }
        .navigationDestination(item: $fillInRoute) { route in
            fillInDestination(for: route)
        }
        .navigationDestination(item: $verifiedRoute) { route in
            verifiedDestination(for: route)
        }
        .sheet(isPresented: $showLibraryMatchPicker) {
            ActualsLibraryMatchPicker(
                candidates: libraryCandidates,
                onPick: { candidate in
                    showLibraryMatchPicker = false
                    guard let cardID = libraryPickerCardID else { return }
                    // Match then land on Fill-in (RPE + Save) — don't dump back to the list.
                    Task {
                        await applyResolvedLibraryMatch(
                            candidate: candidate,
                            cardID: cardID
                        )
                    }
                },
                onCancel: {
                    showLibraryMatchPicker = false
                }
            )
        }
        .accessibilityIdentifier(ActualsCopy.historyAccessibilityID)
    }

    // MARK: - Header

    private var header: some View {
        Text(ActualsCopy.historyTitle)
            .ddDisplayText(28, weight: .heavy)
            .foregroundColor(DailyDriver.foreground)
    }

    // MARK: - Banner

    private var banner: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(
                ActualsCopy.historyPulledBanner(
                    days: viewModel.daysBack,
                    sessions: viewModel.totalSessions,
                    needFillIn: viewModel.needFillInCount
                )
            )
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.bannerExpanded.toggle()
                }
            } label: {
                Text(viewModel.bannerExpanded ? "Hide ›" : ActualsCopy.historyBannerShow)
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.lime)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Day list

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 18) {
            if viewModel.isLoading && viewModel.dayGroups.isEmpty {
                ProgressView()
                    .tint(DailyDriver.lime)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if viewModel.dayGroups.isEmpty {
                Text("No sessions in this window.")
                    .font(.system(size: 12))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(viewModel.dayGroups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ActualsDayBucketing.historyDayHeader(for: group.day))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)

                        VStack(spacing: 7) {
                            ForEach(group.cards) { card in
                                Button {
                                    openCard(card)
                                } label: {
                                    dayRow(card)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("af_actuals_history_row_\(card.id)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func openCard(_ card: ActualsTodayDemoCard) {
        switch card.kind {
        case .unmapped, .merged:
            let activity = card.activity ?? ActualsTodayDemoFeed.sampleUnmappedActivity()
            mapRoute = HistoryMapRoute(cardID: card.id, activity: activity)
        case .fillInDebt:
            // Already matched — go to Fill-in (RPE + Save), not Map again.
            // Rebuild session if an earlier match only renamed the title.
            if card.fillInSession == nil {
                _ = viewModel.applyLibraryMatch(planTitle: card.title, cardID: card.id)
            }
            openFillIn(cardID: card.id)
        case .verified:
            verifiedRoute = HistoryVerifiedRoute(cardID: card.id)
        }
    }

    private func openFillIn(cardID: String) {
        guard viewModel.card(withID: cardID)?.fillInSession != nil else { return }
        fillInRoute = HistoryFillInRoute(cardID: cardID)
    }

    private func mapDestination(for route: HistoryMapRoute) -> some View {
        ActualsMapToPlanView(
            activity: route.activity,
            matches: ActualsPlanMatcher.rank(
                activity: route.activity,
                candidates: libraryCandidates
            ),
            onSelect: { match in
                Task {
                    await applyResolvedLibraryMatch(
                        candidate: match.candidate,
                        cardID: route.cardID
                    )
                }
            },
            onKeepAsIs: {
                Task { await viewModel.applyKeepAsIs(cardID: route.cardID) }
                mapRoute = nil
            },
            onSearchAll: {
                libraryPickerCardID = route.cardID
                showLibraryMatchPicker = true
            },
            onCaptureMatched: { draft, _ in
                _ = viewModel.applyCaptureMatched(draft: draft, cardID: route.cardID)
                mapRoute = nil
                openFillIn(cardID: route.cardID)
            }
        )
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func fillInDestination(for route: HistoryFillInRoute) -> some View {
        if let session = resolvedFillInSession(for: route.cardID) {
            let fillInVM = ActualsFillInViewModel(
                session: session,
                repository: ActualsRepository()
            )
            ActualsFillInView(
                viewModel: fillInVM,
                onSaved: { saved in
                    viewModel.markVerified(saved: saved, cardID: route.cardID)
                },
                onBack: {
                    if !fillInVM.session.verified {
                        try? fillInVM.persistDraftProgress()
                        viewModel.applyFillInDraft(session: fillInVM.session, cardID: route.cardID)
                    }
                    fillInRoute = nil
                }
            )
            .navigationBarBackButtonHidden(true)
        } else {
            Text("Couldn't open fill-in for that session.")
                .foregroundColor(DailyDriver.foregroundDim)
                .padding()
        }
    }

    /// Prefer GRDB draft so Back → reopen keeps mid-edit confirms / RPE.
    private func resolvedFillInSession(for cardID: String) -> ActualsFillInSession? {
        let fallback = viewModel.card(withID: cardID)?.fillInSession
        if let persisted = try? ActualsRepository().fetchSession(id: cardID) {
            return ActualsTodayDemoFeed.mergePersistedFillIn(
                persisted,
                fallback: fallback ?? persisted
            )
        }
        if let fallback, let persisted = try? ActualsRepository().fetchSession(id: fallback.id) {
            return ActualsTodayDemoFeed.mergePersistedFillIn(persisted, fallback: fallback)
        }
        return fallback
    }

    @ViewBuilder
    private func verifiedDestination(for route: HistoryVerifiedRoute) -> some View {
        let card = viewModel.card(withID: route.cardID)
        let session = card?.fillInSession
            ?? (try? ActualsRepository().fetchSession(id: route.cardID))
        if let session {
            let detailSession = Self.enrichedVerifiedSession(
                session,
                cardID: route.cardID,
                cachedDescription: card?.activity?.activityDescription
            )
            let onEditActuals = {
                if card?.fillInSession == nil {
                    _ = viewModel.applyLibraryMatch(
                        planTitle: session.title,
                        cardID: route.cardID
                    )
                }
                verifiedRoute = nil
                openFillIn(cardID: route.cardID)
            }
            let onUnverify = {
                Task { await viewModel.applyUnverify(cardID: route.cardID, session: session) }
                verifiedRoute = nil
            }
            ActualsVerifiedView(
                session: detailSession,
                sourceName: ActualsCopy.sourceDisplayName(card?.sourceProvider ?? .strava),
                decoration: card?.stravaDecoration ?? .none,
                onEditActuals: onEditActuals,
                onUnverify: onUnverify
            ) { description in
                viewModel.applyActivityDescription(cardID: route.cardID, description: description)
            }
            .navigationBarBackButtonHidden(true)
        } else {
            Text("Couldn't open that verified session.")
                .foregroundColor(DailyDriver.foregroundDim)
                .padding()
        }
    }

    /// AMA-2405: backfill activity id + cached description for lazy Strava text.
    private static func enrichedVerifiedSession(
        _ session: ActualsFillInSession,
        cardID: String,
        cachedDescription: String?
    ) -> ActualsFillInSession {
        var next = session
        if next.stravaActivityId == nil {
            next.stravaActivityId = ActualsTodayDemoFeed.stravaActivityId(fromCardID: cardID)
        }
        if (next.stravaCurrentDescription ?? "").isEmpty,
           let cachedDescription, !cachedDescription.isEmpty {
            next.stravaCurrentDescription = cachedDescription
        }
        return next
    }

    private func dayRow(_ card: ActualsTodayDemoCard) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.title)
                        .ddDisplayText(13, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .lineLimit(1)
                    SZStravaBadge(decoration: card.stravaDecoration)
                }
                Text("\(card.timeLabel) · \(card.sourceLabel.uppercased())")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            rowCTA(for: card)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func rowCTA(for card: ActualsTodayDemoCard) -> some View {
        switch card.kind {
        case .unmapped, .merged:
            Text(ActualsCopy.historyFillInCTA)
                .ddDisplayText(11.5, weight: .bold)
                .foregroundColor(DailyDriver.amber)
        case .fillInDebt:
            // Matched — next step is Log RPE / Save, not "map again".
            Text("Log RPE ›")
                .ddDisplayText(11.5, weight: .bold)
                .foregroundColor(DailyDriver.amber)
        case .verified:
            Text(ActualsCopy.verifiedTimelineCTA)
                .ddDisplayText(11.5, weight: .bold)
                .foregroundColor(DailyDriver.lime)
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await viewModel.loadMore() }
        } label: {
            HStack {
                if viewModel.isLoading {
                    ProgressView().tint(DailyDriver.foregroundMuted)
                }
                Text(ActualsCopy.historyLoadMore)
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DailyDriver.card2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ActualsCopy.historyLegend)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(ActualsCopy.historyLocalTimeFooter)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundColor(DailyDriver.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func applyResolvedLibraryMatch(
        candidate: ActualsPlanCandidate,
        cardID: String
    ) async {
        let workout = await ActualsLibraryWorkoutResolver.resolveDetail(
            workoutID: candidate.id,
            title: candidate.title,
            local: libraryWorkoutsByID
        )
        if let workout {
            libraryWorkoutsByID[workout.id] = workout
        }
        _ = viewModel.applyLibraryMatch(
            planTitle: candidate.title,
            cardID: cardID,
            workout: workout
        )
        mapRoute = nil
        openFillIn(cardID: cardID)
    }

    private func loadLibraryCandidates() async {
        do {
            let workouts = try await APIService.shared.fetchWorkouts()
            let enriched = WorkoutLibraryDetailStore.enrichCollection(workouts)
            libraryCandidates = ActualsPlanCandidate.fromLibrary(enriched)
            libraryWorkoutsByID = Dictionary(
                uniqueKeysWithValues: enriched.map { ($0.id, $0) }
            )
        } catch {
            if libraryCandidates.isEmpty {
                libraryCandidates = ActualsTodayDemoFeed.samplePlanCandidates
            }
        }
    }
}
