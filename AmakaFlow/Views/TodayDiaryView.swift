//
//  TodayDiaryView.swift
//  AmakaFlow
//
//  AMA-2292: Daily Driver Today tab — completed-activities diary shell.
//  AMA-2289: Sync completions (Garmin / phone) onto the rail.
//  AMA-2387: Actuals teach → connect → (demo) merge / map / fill-in in-shell.
//  Daily Driver Proto: DDTodayScreen — day scrubber + timeline cards.
//

// swiftlint:disable file_length

import SwiftUI

// swiftlint:disable:next type_body_length
struct TodayDiaryView: View {
    @StateObject private var historyViewModel = ActivityHistoryViewModel()
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    @StateObject private var actualsSources = ActualsSourceConnectionStore()
    @StateObject private var actualsSyncProgress = ActualsSyncProgressStore()
    @StateObject private var actualsDemo = ActualsTodayDemoFeed()
    @State private var selectedCompletionId: String?
    @State private var scrubberSelectedIndex = 0
    /// AMA-2396: explicit selected day so the scrubber window can shift backward
    /// without a circular dependency on `scrubberDays[index]`.
    @State private var selectedScrubberDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var showConnectSources = false
    @State private var actualsDestination: ActualsTodayDestination?
    @State private var activeMergedSession: ActualsSession?
    @State private var activeUnmapped: ActualsUnmappedActivity?
    @State private var verifiedSession: ActualsFillInSession?
    @State private var verifiedSourceName = ActualsCopy.sourceDisplayName(.strava)
    @State private var verifiedCardID: String?

    private var today: Date { Date() }

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedScrubberDay)
    }

    private var todaysCompletions: [WorkoutCompletion] {
        let calendar = Calendar.current
        return historyViewModel.completions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: selectedScrubberDay) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var usesTodayFixture: Bool {
        todaysCompletions.contains(where: \.wasSimulated)
    }

    private var scrubberDays: [DDScrubberDay] {
        historyViewModel.completions.scrubberDays(
            now: today,
            selectedDay: selectedScrubberDay
        )
    }

    private var watchConnected: Bool {
        watchConnectivity.isWatchReachable || watchConnectivity.isWatchAppInstalled
    }

    private var showsActualsTeachCard: Bool {
        // Never flash teach/Connect while Strava is already linked or re-syncing.
        guard !actualsSources.isConnected(.strava), !actualsDemo.isRefreshing else {
            return false
        }
        return ActualsTeachCardVisibility.shouldShow(
            hasEverConnected: actualsSources.hasEverConnected,
            todayEmpty: todaysCompletions.isEmpty && !actualsDemo.isActive
        )
    }

    private var showsActualsDemoRail: Bool {
        actualsDemo.isActive
    }

    /// Linked Strava with an in-flight sync — show progress, never Connect CTA.
    private var showsStravaRefreshing: Bool {
        actualsDemo.isRefreshing && actualsSources.isConnected(.strava)
    }

    /// Actuals rail cards restricted to the scrubber-selected local day.
    private var actualsCardsForSelectedDay: [ActualsTodayDemoCard] {
        let calendar = Calendar.current
        return actualsDemo.cards.filter { card in
            if let start = card.activity?.startDate {
                return calendar.isDate(start, inSameDayAs: selectedScrubberDay)
            }
            if let start = card.session?.primaryRecording?.startDate {
                return calendar.isDate(start, inSameDayAs: selectedScrubberDay)
            }
            // Fixture / undated demo cards only belong on calendar-today.
            return calendar.isDateInToday(selectedScrubberDay)
        }
    }

    /// Linked, sync done, nothing for the selected local day.
    private var showsLinkedStravaEmptyToday: Bool {
        actualsSources.isConnected(.strava)
            && actualsDemo.isActive
            && !actualsDemo.isRefreshing
            && actualsCardsForSelectedDay.isEmpty
            && todaysCompletions.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow

                if !scrubberDays.isEmpty {
                    DDDayScrubber(days: scrubberDays, selectedIndex: $scrubberSelectedIndex)
                        .onChange(of: scrubberSelectedIndex) { _, newIndex in
                            let days = scrubberDays
                            guard days.indices.contains(newIndex) else { return }
                            selectedScrubberDay = days[newIndex].id
                        }
                    Text(ActualsCopy.historyScrubberHint)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 4)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let progress = actualsSyncProgress.progress, progress.shouldShowBanner {
                            ActualsSyncCounterBanner(progress: progress)
                                .padding(.bottom, 12)
                        }

                        if historyViewModel.isLoading && historyViewModel.completions.isEmpty
                            && !showsActualsDemoRail && !showsStravaRefreshing {
                            loadingState
                        } else if showsStravaRefreshing && !showsActualsDemoRail {
                            // Already linked — keep the 30-day pull banner; no Connect CTA.
                            Color.clear.frame(height: 8)
                        } else if showsActualsTeachCard {
                            ActualsTeachCard {
                                showConnectSources = true
                            }
                            .padding(.top, 12)
                        } else if showsActualsDemoRail, !actualsCardsForSelectedDay.isEmpty {
                            actualsDemoContent
                        } else if showsLinkedStravaEmptyToday {
                            linkedStravaEmptyTodayState
                        } else if todaysCompletions.isEmpty, !actualsSources.isConnected(.strava) {
                            emptyDiaryState
                        } else if todaysCompletions.isEmpty {
                            // Linked but feed not active yet (edge) — still no Connect flash.
                            linkedStravaEmptyTodayState
                        } else {
                            timeline
                            systemEventRows
                            timelineFooterHint
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 100)
                }
            }
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .navigationBarHidden(true)
            .preferredColorScheme(.dark)
            .task {
                #if DEBUG
                if ActualsTodayDemoFeed.shouldAutoActivate {
                    actualsDemo.activateColdStart(
                        sources: actualsSources,
                        sync: actualsSyncProgress
                    )
                }
                #endif
                // Kick Strava re-pull first so Connect never flashes while history loads.
                async let history: Void = historyViewModel.loadCompletions()
                if actualsSources.isConnected(.strava), !actualsDemo.isActive {
                    await actualsDemo.handleProviderConnected(
                        .strava,
                        sync: actualsSyncProgress
                    )
                }
                await history
                syncScrubberToToday()
            }
            .refreshable {
                await historyViewModel.refreshCompletions()
                if actualsSources.isConnected(.strava) {
                    await actualsDemo.handleProviderConnected(
                        .strava,
                        sync: actualsSyncProgress
                    )
                }
            }
            .sheet(item: $selectedCompletionId) { completionId in
                DDActivityDetailView(completionId: completionId)
            }
            .navigationDestination(isPresented: $showConnectSources) {
                ActualsConnectSourcesView(store: actualsSources) { provider in
                    // Children already markConnected + announce on real grant/success.
                    showConnectSources = false
                    Task {
                        await actualsDemo.handleProviderConnected(
                            provider,
                            sync: actualsSyncProgress
                        )
                    }
                }
            }
            .navigationDestination(item: $actualsDestination) { destination in
                actualsDestinationView(destination)
            }
            .overlay(alignment: .top) {
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("today_screen")
            }
        }
    }

    // MARK: - Actuals demo rail (real Today chrome)

    @ViewBuilder
    private var actualsDemoContent: some View {
        if actualsDemo.showMergeAsk,
           let left = actualsDemo.mergeLeft,
           let right = actualsDemo.mergeRight {
            ActualsMergeAskCard(
                left: left,
                right: right,
                onMerge: {
                    actualsDemo.applyMerge()
                    if let session = actualsDemo.cards.first(where: { $0.kind == .merged })?.session {
                        activeMergedSession = session
                        actualsDestination = .mergedDetail
                    }
                },
                onKeepBoth: {
                    actualsDemo.applyKeepBoth()
                }
            )
            .padding(.bottom, 14)
        }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(actualsCardsForSelectedDay.enumerated()), id: \.element.id) { index, card in
                Button {
                    openActualsCard(card)
                } label: {
                    DDTimelineCard(
                        icon: iconName(for: card),
                        iconBackground: iconBackground(for: card),
                        time: card.timeLabel,
                        title: card.title,
                        stats: card.stats,
                        sourceLabel: card.sourceLabel,
                        showsChevron: true,
                        trailingAction: AnyView(actualsTrailingAction(for: card))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_today_actuals_card_\(index)")
            }
        }
        .accessibilityIdentifier("af_today_actuals_demo_list")

        systemEventRows
        timelineFooterHint
    }

    @ViewBuilder
    private func actualsTrailingAction(for card: ActualsTodayDemoCard) -> some View {
        switch card.kind {
        case .unmapped:
            Text("Fill in ›")
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.amber)
        case .fillInDebt:
            Text("Log RPE")
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.amber)
        case .merged:
            Text("Fill in ›")
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.amber)
        case .verified:
            Text(ActualsCopy.verifiedTimelineCTA)
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.lime)
        case .counted:
            Text(ActualsCopy.historyCountedCTA)
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.lime)
        }
    }

    private func iconName(for card: ActualsTodayDemoCard) -> String {
        switch card.kind {
        case .unmapped:
            return Self.symbolName(for: card.activity?.type)
        case .merged: return "applewatch"
        case .fillInDebt: return "figure.strengthtraining.traditional"
        case .verified, .counted:
            if card.session != nil { return "applewatch" }
            if card.title.localizedCaseInsensitiveContains("run") { return "figure.run" }
            return "figure.strengthtraining.traditional"
        }
    }

    private func iconBackground(for card: ActualsTodayDemoCard) -> Color {
        switch card.kind {
        case .unmapped:
            return card.sourceProvider == .strava
                ? DailyDriver.stravaBrand
                : DailyDriver.card2
        case .merged: return DailyDriver.blue
        case .fillInDebt: return DailyDriver.lime
        case .verified, .counted:
            return card.session != nil ? DailyDriver.blue : DailyDriver.lime
        }
    }

    /// SF Symbol for Strava/unmapped activity types (not always a run).
    private static func symbolName(for type: ActualsWorkoutType?) -> String {
        switch type {
        case .run: return "figure.run"
        case .ride: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .other, .none: return "figure.mixed.cardio"
        }
    }

    private func openActualsCard(_ card: ActualsTodayDemoCard) {
        switch card.kind {
        case .merged:
            guard let session = card.session else { return }
            activeMergedSession = session
            actualsDestination = .mergedDetail
        case .unmapped:
            // Activity + card id must ride on the destination — separate @State races to a blank push,
            // and live Strava rows (strava_*) must keep their identity through Map → match.
            let activity = card.activity ?? ActualsTodayDemoFeed.sampleUnmappedActivity()
            activeUnmapped = activity
            actualsDestination = .mapToPlan(cardID: card.id, activity: activity)
        case .fillInDebt:
            actualsDemo.prepareFillIn(from: card)
            guard actualsDemo.fillInViewModel != nil else { return }
            actualsDestination = .fillIn
        case .verified:
            if let saved = card.fillInSession {
                verifiedSession = saved
                verifiedSourceName = sourceDisplayName(for: card)
                verifiedCardID = card.id
                actualsDestination = .verified
            }
        case .counted:
            break
        }
    }

    @ViewBuilder
    private func actualsDestinationView(_ destination: ActualsTodayDestination) -> some View {
        switch destination {
        case .mergedDetail:
            mergedDetailDestinationView
        case .mapToPlan(let cardID, let activity):
            mapToPlanDestinationView(cardID: cardID, activity: activity)
        case .matchSave:
            // Match-save is presented from Map (fullScreenCover). Pop if we land here.
            missingDestinationFallback(nil)
        case .fillIn:
            fillInDestinationView
        case .verified:
            verifiedDestinationView
        }
    }

    @ViewBuilder
    private var mergedDetailDestinationView: some View {
        if let session = activeMergedSession {
            ActualsMergedDetailView(
                session: session,
                onSplit: { restored in
                    actualsDemo.applySplit(
                        restored: restored,
                        fromMergedSessionID: session.id
                    )
                    actualsDestination = nil
                    activeMergedSession = nil
                },
                onFillIn: {
                    if let merged = actualsDemo.cards.first(where: { $0.kind == .merged }) {
                        actualsDemo.prepareFillIn(from: merged)
                    } else {
                        actualsDemo.prepareFillIn()
                    }
                    guard actualsDemo.fillInViewModel != nil else { return }
                    actualsDestination = .fillIn
                }
            )
            .navigationBarBackButtonHidden(true)
        } else {
            missingDestinationFallback("Couldn't open that session.")
        }
    }

    private func mapToPlanDestinationView(
        cardID: String,
        activity: ActualsUnmappedActivity
    ) -> some View {
        ActualsMapToPlanView(
            activity: activity,
            matches: ActualsPlanMatcher.rank(
                activity: activity,
                candidates: ActualsTodayDemoFeed.samplePlanCandidates
            ),
            onSelect: { match in
                // Keep the session on Today — attach the plan, then RPE.
                actualsDemo.applyLibraryMatch(
                    planTitle: match.candidate.title,
                    unmappedCardID: cardID
                )
                if let matched = actualsDemo.cards.first(where: { $0.id == cardID }) {
                    actualsDemo.prepareFillIn(from: matched)
                }
                guard actualsDemo.fillInViewModel != nil else {
                    actualsDestination = nil
                    return
                }
                actualsDestination = .fillIn
            },
            onKeepAsIs: {
                actualsDemo.applyKeepAsIs(unmappedCardID: cardID)
                actualsDestination = nil
            },
            onCaptureMatched: { draft, _ in
                actualsDemo.applyCaptureMatched(draft: draft, unmappedCardID: cardID)
                actualsDestination = nil
                activeUnmapped = nil
            }
        )
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var fillInDestinationView: some View {
        if let viewModel = actualsDemo.fillInViewModel {
            // Named closures avoid trailing_closure vs multiple_closures_with_trailing_closure.
            let onSaved: (ActualsFillInSession) -> Void = { session in
                verifiedSession = session
                if let card = actualsDemo.cards.first(where: {
                    $0.id == actualsDemo.pendingFillInCardID || $0.fillInSession?.id == session.id
                }) {
                    verifiedCardID = card.id
                    verifiedSourceName = sourceDisplayName(for: card)
                }
                actualsDemo.markVerified(saved: session)
                actualsDestination = .verified
            }
            let onUnverify = {
                actualsDemo.applyUnverify(sessionID: viewModel.session.id)
            }
            let onWriteBackDecoration: (StravaDecorationState) -> Void = { state in
                if let cardID = verifiedCardID {
                    actualsDemo.applyDecoration(cardID: cardID, state: state)
                }
            }
            ActualsFillInView(
                viewModel: viewModel,
                onSaved: onSaved,
                presentsVerifiedOnSave: false,
                dismissOnSave: false,
                onUnverify: onUnverify,
                onWriteBackDecoration: onWriteBackDecoration
            )
            .navigationBarBackButtonHidden(true)
        } else {
            missingDestinationFallback("Couldn't open fill-in.")
        }
    }

    @ViewBuilder
    private var verifiedDestinationView: some View {
        if let session = verifiedSession {
            let onEditActuals = {
                actualsDemo.prepareFillIn(
                    from: actualsDemo.cards.first { $0.id == verifiedCardID }
                )
                guard actualsDemo.fillInViewModel != nil else { return }
                actualsDestination = .fillIn
            }
            let onUnverify = {
                Task { await unverifyVerifiedSession(session) }
            }
            let onUnmatch = {
                guard let cardID = verifiedCardID else {
                    actualsDestination = nil
                    return
                }
                let activity = actualsDemo.cards.first { $0.id == cardID }?.activity
                    ?? ActualsTodayDemoFeed.sampleUnmappedActivity()
                actualsDestination = .mapToPlan(cardID: cardID, activity: activity)
            }
            ActualsVerifiedView(
                session: session,
                sourceName: verifiedSourceName,
                decoration: actualsDemo.cards.first { $0.id == verifiedCardID }?
                    .stravaDecoration ?? .none,
                onEditActuals: onEditActuals,
                onRemoveFromStrava: removeVerifiedFromStrava,
                onUnverify: onUnverify,
                onUnmatch: onUnmatch
            )
            .navigationBarBackButtonHidden(true)
        } else {
            missingDestinationFallback(nil)
        }
    }

    private func unverifyVerifiedSession(_ session: ActualsFillInSession) async {
        let repository = ActualsRepository()
        let provider = StravaWriteBackFactory.makeDefault()
        let sessionID = session.id
        let cardID = verifiedCardID
        if let snapshot = try? repository.fetchPreUpdateSnapshot(forSessionID: sessionID) {
            let outcome = await provider.restore(
                activityId: snapshot.activityId,
                snapshot: snapshot
            )
            if case .restored = outcome {
                try? repository.clearPreUpdateSnapshot(forSessionID: sessionID)
                try? repository.storeDecoration(.untouched, forSessionID: sessionID)
                if let cardID {
                    await MainActor.run {
                        actualsDemo.applyDecoration(cardID: cardID, state: .untouched)
                    }
                }
            }
        }
        await MainActor.run {
            actualsDemo.applyUnverify(sessionID: sessionID)
            try? repository.unverifySession(id: sessionID)
            actualsDestination = nil
        }
    }

    private func removeVerifiedFromStrava() {
        guard let cardID = verifiedCardID, let session = verifiedSession else { return }
        let sessionID = session.id
        Task {
            let repository = ActualsRepository()
            let provider = StravaWriteBackFactory.makeDefault()
            var restoredOK = false
            if let snapshot = try? repository.fetchPreUpdateSnapshot(forSessionID: sessionID) {
                let outcome = await provider.restore(
                    activityId: snapshot.activityId,
                    snapshot: snapshot
                )
                if case .restored = outcome {
                    try? repository.clearPreUpdateSnapshot(forSessionID: sessionID)
                    restoredOK = true
                }
            }
            // Only flip local badge after a successful restore (or when nothing to restore).
            if restoredOK || (try? repository.fetchPreUpdateSnapshot(forSessionID: sessionID)) == nil {
                try? repository.storeDecoration(.untouched, forSessionID: sessionID)
                await MainActor.run {
                    actualsDemo.applyDecoration(cardID: cardID, state: .untouched)
                }
            }
        }
    }

    private func sourceDisplayName(for card: ActualsTodayDemoCard) -> String {
        // Prefer the stored provider — verified cards rewrite sourceLabel to "Verified · RPE N".
        if let provider = card.sourceProvider
            ?? card.activity?.provider
            ?? card.session?.primaryRecording?.provider {
            return ActualsCopy.sourceDisplayName(provider)
        }
        return ActualsCopy.sourceDisplayName(.appleHealth)
    }

    /// Never push an empty view — that was the blank Fill in screen.
    @ViewBuilder
    private func missingDestinationFallback(_ message: String?) -> some View {
        VStack(spacing: 12) {
            if let message {
                Text(message)
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .multilineTextAlignment(.center)
            }
            Button("Back to Today") {
                actualsDestination = nil
            }
            .buttonStyle(.plain)
            .foregroundColor(DailyDriver.lime)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if message == nil {
                actualsDestination = nil
            }
        }
    }

    // MARK: - Chrome

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text(headerTitle)
                .ddDisplayText(32, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .accessibilityIdentifier("af_today_title")
            Spacer(minLength: 0)
            if !isViewingToday {
                Button {
                    syncScrubberToToday()
                } label: {
                    Text(ActualsCopy.historyJumpToday)
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.lime)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_today_jump_today")
            } else {
                NavigationLink {
                    DDDeviceDetailView()
                        .ddSuppressFloatingChrome()
                } label: {
                    DDWatchReadinessPill(
                        isConnected: watchConnected || usesTodayFixture || showsActualsDemoRail,
                        batteryPercent: usesTodayFixture ? DDDeviceFixture.batteryPercent : nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var headerTitle: String {
        if isViewingToday { return "Today" }
        return selectedScrubberDay.formatted(.dateTime.weekday(.wide))
    }

    private var loadingState: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(DailyDriver.lime)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Loading today’s diary")
                    .ddDisplayText(15, weight: .bold)
                Text("Pulling completed activities only — no schedule.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("af_today_loading")
    }

    private var emptyDiaryState: some View {
        // Teach card is first-time only (`hasEverConnected`). Once that flag is set
        // (stub dogfood / prior connect), empty Today had no path to Connect Sources —
        // AMA-2391: keep a Connect CTA while any source is still unlinked.
        VStack(spacing: 16) {
            Text("Sessions land here as they happen — or add one with ＋")
                .font(.system(size: 12))
                .foregroundColor(DailyDriver.foregroundDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("af_today_empty_state")

            // Offer Connect Sources only when nothing is linked yet.
            Button {
                showConnectSources = true
            } label: {
                Text(ActualsCopy.teachCTA)
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(ActualsCopy.teachCTAAccessibilityID)
        }
        .padding(.top, 26)
    }

    private var linkedStravaEmptyTodayState: some View {
        VStack(spacing: 12) {
            Text(ActualsCopy.linkedEmptyToday)
                .font(.system(size: 12))
                .foregroundColor(DailyDriver.foregroundDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("af_today_strava_empty_today")

            Text("Sessions land here as they happen — or add one with ＋")
                .font(.system(size: 12))
                .foregroundColor(DailyDriver.foregroundMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 26)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(todaysCompletions.enumerated()), id: \.element.id) { index, completion in
                Button {
                    selectedCompletionId = completion.id
                } label: {
                    let icon = completion.ddTimelineIcon
                    DDTimelineCard(
                        icon: icon.name,
                        iconBackground: icon.background,
                        time: completion.ddTimeRange,
                        title: completion.ddTimelineTitle,
                        stats: completion.ddTimelineStats,
                        sourceLabel: completion.ddSourceCaption,
                        showsChevron: true,
                        trailingAction: AnyView(timelineAction(for: completion))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_today_completion_\(index)")
            }
        }
        .accessibilityIdentifier("af_today_diary_list")
    }

    @ViewBuilder
    private func timelineAction(for completion: WorkoutCompletion) -> some View {
        if completion.ddNeedsActivityMapping {
            Text("What was this?")
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.amber)
        } else {
            Text("Log RPE")
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.amber)
        }
    }

    /// Plain rail rows from proto (GARMIN SYNCED · DAY STARTED).
    private var systemEventRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsGarminSyncRow {
                DDTimelineCard(
                    icon: "applewatch",
                    iconBackground: DailyDriver.card2,
                    time: garminSyncTimeLabel,
                    label: "GARMIN SYNCED · \(garminPulledCount) ACTIVITIES PULLED"
                )
            }
            DDTimelineCard(
                icon: "sun.max.fill",
                iconBackground: DailyDriver.card2,
                time: dayStartedTimeLabel,
                label: "DAY STARTED"
            )
        }
    }

    private var showsGarminSyncRow: Bool {
        todaysCompletions.contains { $0.source == .garmin }
            || usesTodayFixture
            || showsActualsDemoRail
    }

    private var garminPulledCount: Int {
        let garminCount = todaysCompletions.filter { $0.source == .garmin }.count
        if usesTodayFixture || showsActualsDemoRail { return max(2, garminCount) }
        return max(1, garminCount)
    }

    private var garminSyncTimeLabel: String {
        if usesTodayFixture || showsActualsDemoRail { return "07:41" }
        let garminCompletions = todaysCompletions.filter { $0.source == .garmin }
        guard let earliest = garminCompletions.map(\.startedAt).min() else {
            return "—"
        }
        return earliest.formatted(date: .omitted, time: .shortened)
    }

    private var dayStartedTimeLabel: String {
        if usesTodayFixture || showsActualsDemoRail { return "06:58" }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let morning = calendar.date(byAdding: .minute, value: 58, to: start) ?? start
        return morning.formatted(date: .omitted, time: .shortened)
    }

    private var timelineFooterHint: some View {
        Text("Sessions land here as they happen — or add one with ＋.")
            .font(.system(size: 12))
            .foregroundColor(DailyDriver.foregroundDim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 26)
    }

    private func syncScrubberToToday() {
        selectedScrubberDay = Calendar.current.startOfDay(for: today)
        if let todayIndex = scrubberDays.firstIndex(where: { $0.isToday }) {
            scrubberSelectedIndex = todayIndex
        }
    }
}

// MARK: - Navigation

private enum ActualsTodayDestination: Hashable, Identifiable {
    case mergedDetail
    /// Card id + activity — avoids blank Map when @State races, and keeps live Strava rows addressable.
    case mapToPlan(cardID: String, activity: ActualsUnmappedActivity)
    case matchSave
    case fillIn
    case verified

    var id: String {
        switch self {
        case .mergedDetail: return "mergedDetail"
        case .mapToPlan(let cardID, let activity):
            return "mapToPlan-\(cardID)-\(activity.startDate.timeIntervalSince1970)"
        case .matchSave: return "matchSave"
        case .fillIn: return "fillIn"
        case .verified: return "verified"
        }
    }
}

#if DEBUG
#Preview("Today diary · empty") {
    TodayDiaryView()
        .preferredColorScheme(.dark)
}
#endif
