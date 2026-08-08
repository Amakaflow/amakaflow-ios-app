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
    @State private var showConnectSources = false
    @State private var actualsDestination: ActualsTodayDestination?
    @State private var activeMergedSession: ActualsSession?
    @State private var activeUnmapped: ActualsUnmappedActivity?
    @State private var verifiedSession: ActualsFillInSession?
    @State private var verifiedSourceName = ActualsCopy.sourceDisplayName(.strava)

    private var today: Date { Date() }

    private var todaysCompletions: [WorkoutCompletion] {
        historyViewModel.todaysCompletions
    }

    private var usesTodayFixture: Bool {
        todaysCompletions.contains(where: \.wasSimulated)
    }

    private var scrubberDays: [DDScrubberDay] {
        historyViewModel.completions.scrubberDays(now: today)
    }

    private var watchConnected: Bool {
        watchConnectivity.isWatchReachable || watchConnectivity.isWatchAppInstalled
    }

    private var showsActualsTeachCard: Bool {
        ActualsTeachCardVisibility.shouldShow(
            hasEverConnected: actualsSources.hasEverConnected,
            todayEmpty: todaysCompletions.isEmpty && !actualsDemo.isActive
        )
    }

    private var showsActualsDemoRail: Bool {
        actualsDemo.isActive
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow

                if !scrubberDays.isEmpty {
                    DDDayScrubber(days: scrubberDays, selectedIndex: $scrubberSelectedIndex)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let progress = actualsSyncProgress.progress, progress.shouldShowBanner {
                            ActualsSyncCounterBanner(progress: progress)
                                .padding(.bottom, 12)
                        }

                        if historyViewModel.isLoading && historyViewModel.completions.isEmpty && !showsActualsDemoRail {
                            loadingState
                        } else if showsActualsTeachCard {
                            ActualsTeachCard {
                                showConnectSources = true
                            }
                            .padding(.top, 12)
                        } else if showsActualsDemoRail {
                            actualsDemoContent
                        } else if todaysCompletions.isEmpty {
                            emptyDiaryState
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
                await historyViewModel.loadCompletions()
                syncScrubberToToday()
                #if DEBUG
                if ActualsTodayDemoFeed.shouldAutoActivate {
                    actualsDemo.activateColdStart(
                        sources: actualsSources,
                        sync: actualsSyncProgress
                    )
                }
                #endif
            }
            .refreshable {
                await historyViewModel.refreshCompletions()
            }
            .sheet(item: $selectedCompletionId) { completionId in
                DDActivityDetailView(completionId: completionId)
            }
            .navigationDestination(isPresented: $showConnectSources) {
                ActualsConnectSourcesView(store: actualsSources) { _ in
                    // Children already markConnected + announce on real grant/success.
                    #if DEBUG
                    if ActualsTodayDemoFeed.shouldAutoActivate {
                        actualsDemo.activateAfterConnect(sync: actualsSyncProgress)
                    }
                    #endif
                    showConnectSources = false
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
            ForEach(Array(actualsDemo.cards.enumerated()), id: \.element.id) { index, card in
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
        }
    }

    private func iconName(for card: ActualsTodayDemoCard) -> String {
        switch card.kind {
        case .unmapped: return "figure.run"
        case .merged: return "applewatch"
        case .fillInDebt: return "figure.strengthtraining.traditional"
        case .verified:
            if card.session != nil { return "applewatch" }
            if card.title.localizedCaseInsensitiveContains("run") { return "figure.run" }
            return "figure.strengthtraining.traditional"
        }
    }

    private func iconBackground(for card: ActualsTodayDemoCard) -> Color {
        switch card.kind {
        case .unmapped: return DailyDriver.stravaBrand
        case .merged: return DailyDriver.blue
        case .fillInDebt: return DailyDriver.lime
        case .verified:
            return card.session != nil ? DailyDriver.blue : DailyDriver.lime
        }
    }

    private func openActualsCard(_ card: ActualsTodayDemoCard) {
        switch card.kind {
        case .merged:
            guard let session = card.session else { return }
            activeMergedSession = session
            actualsDestination = .mergedDetail
        case .unmapped:
            // Activity must ride on the destination — separate @State races to a blank push.
            let activity = card.activity ?? ActualsTodayDemoFeed.sampleUnmappedActivity()
            activeUnmapped = activity
            actualsDestination = .mapToPlan(activity)
        case .fillInDebt:
            actualsDemo.prepareFillIn(from: card)
            guard actualsDemo.fillInViewModel != nil else { return }
            actualsDestination = .fillIn
        case .verified:
            if let saved = card.fillInSession {
                verifiedSession = saved
                verifiedSourceName = sourceDisplayName(for: card)
                actualsDestination = .verified
            }
        }
    }

    @ViewBuilder
    // swiftlint:disable:next cyclomatic_complexity
    private func actualsDestinationView(_ destination: ActualsTodayDestination) -> some View {
        switch destination {
        case .mergedDetail:
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
        case .mapToPlan(let activity):
            ActualsMapToPlanView(
                activity: activity,
                matches: ActualsPlanMatcher.rank(
                    activity: activity,
                    candidates: ActualsTodayDemoFeed.samplePlanCandidates
                ),
                onSelect: { match in
                    // Keep the session on Today — attach the plan, then RPE.
                    actualsDemo.applyLibraryMatch(planTitle: match.candidate.title)
                    if let matched = actualsDemo.cards.first(where: { $0.id == "today_demo_unmapped" }) {
                        actualsDemo.prepareFillIn(from: matched)
                    }
                    guard actualsDemo.fillInViewModel != nil else {
                        actualsDestination = nil
                        return
                    }
                    actualsDestination = .fillIn
                },
                onKeepAsIs: {
                    actualsDestination = nil
                },
                onCaptureMatched: { draft, _ in
                    actualsDemo.applyCaptureMatched(draft: draft)
                    actualsDestination = nil
                    activeUnmapped = nil
                }
            )
            .navigationBarBackButtonHidden(true)
        case .matchSave:
            // Match-save is presented from Map (fullScreenCover). Pop if we land here.
            missingDestinationFallback(nil)
        case .fillIn:
            if let viewModel = actualsDemo.fillInViewModel {
                ActualsFillInView(
                    viewModel: viewModel,
                    onSaved: { session in
                        verifiedSession = session
                        if let card = actualsDemo.cards.first(where: {
                            $0.id == actualsDemo.pendingFillInCardID || $0.fillInSession?.id == session.id
                        }) {
                            verifiedSourceName = sourceDisplayName(for: card)
                        }
                        actualsDemo.markVerified(saved: session)
                        actualsDestination = .verified
                    },
                    presentsVerifiedOnSave: false,
                    dismissOnSave: false
                )
                .navigationBarBackButtonHidden(true)
            } else {
                missingDestinationFallback("Couldn't open fill-in.")
            }
        case .verified:
            if let session = verifiedSession {
                ActualsVerifiedView(session: session, sourceName: verifiedSourceName)
                    .navigationBarBackButtonHidden(true)
            } else {
                missingDestinationFallback(nil)
            }
        }
    }

    private func sourceDisplayName(for card: ActualsTodayDemoCard) -> String {
        if let provider = card.activity?.provider {
            return ActualsCopy.sourceDisplayName(provider)
        }
        if let provider = card.session?.primaryRecording?.provider {
            return ActualsCopy.sourceDisplayName(provider)
        }
        // Verified cards rewrite sourceLabel to "Verified · RPE N" — use stored provider.
        if let provider = card.sourceProvider {
            return ActualsCopy.sourceDisplayName(provider)
        }
        // "Synced from Garmin" / "Matched · Garmin" → last token after · or from.
        let label = card.sourceLabel
        if let range = label.range(of: "· ") {
            return String(label[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let range = label.range(of: "from ", options: .caseInsensitive) {
            return String(label[range.upperBound...]).trimmingCharacters(in: .whitespaces)
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
            Text("Today")
                .ddDisplayText(32, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .accessibilityIdentifier("af_today_title")
            Spacer(minLength: 0)
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
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
        Text("Sessions land here as they happen — or add one with ＋")
            .font(.system(size: 12))
            .foregroundColor(DailyDriver.foregroundDim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 26)
            .accessibilityIdentifier("af_today_empty_state")
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
        if let todayIndex = scrubberDays.firstIndex(where: { $0.isToday }) {
            scrubberSelectedIndex = todayIndex
        }
    }
}

// MARK: - Navigation

private enum ActualsTodayDestination: Hashable, Identifiable {
    case mergedDetail
    /// Payload is the activity — avoids blank Map when @State races.
    case mapToPlan(ActualsUnmappedActivity)
    case matchSave
    case fillIn
    case verified

    var id: String {
        switch self {
        case .mergedDetail: return "mergedDetail"
        case .mapToPlan(let activity):
            return "mapToPlan-\(activity.title)-\(activity.startDate.timeIntervalSince1970)"
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
