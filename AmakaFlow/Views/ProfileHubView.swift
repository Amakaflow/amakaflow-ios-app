//
//  ProfileHubView.swift
//  AmakaFlow
//
//  AMA-2292: Daily Driver Profile tab — identity, stat tiles, week activity.
//  AMA-2417: Strava-backed Monday-week totals; remove hardcoded Monday backfill card.
//

import SwiftUI

enum ProfileHubRoute: Hashable {
    case settings
    case history
    case coach
    /// AMA-2389: Friends management (add / remove / requests).
    case friends
    /// AMA-2396: Sync v2 — day-grouped Strava history + write-back state.
    case actualsHistory
    /// AMA-2396: Connect sources + Strava write-back toggle (discoverable from Profile).
    case actualsConnectSources
}

// swiftlint:disable:next type_body_length
struct ProfileHubView: View {
    @Binding var navigateToSyncDashboard: Bool
    @Binding var path: NavigationPath

    @EnvironmentObject private var pairingService: PairingService
    @AppStorage(DefaultsKey.userDisplayName.rawValue) private var displayNameOverride: String = ""
    @StateObject private var historyViewModel = ActivityHistoryViewModel()
    @ObservedObject private var friendsStore = FriendsSharingStore.shared
    @ObservedObject private var actualsSources = ActualsSourceConnectionStore.shared
    @State private var weekExpanded = false
    /// AMA-2417 / AMA-2419: Strava + Apple Health mapped into Profile completion rows.
    @State private var externalCompletions: [WorkoutCompletion] = []
    @State private var externalStatsLoaded = false

    private var mondayCalendar: Calendar { ProfileTrainingStats.mondayFirstCalendar }

    private var displayName: String {
        let trimmed = displayNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let name = pairingService.userProfile?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return pairingService.userProfile?.email ?? "Athlete"
    }

    private var usesProfileFixture: Bool {
        DDHandoffFixtures.isEnabled
            && !historyViewModel.isLoading
            && historyViewModel.completions.isEmpty
            && externalCompletions.isEmpty
    }

    /// Prefer connected Actuals sources (Strava / Apple Health); else mapper completions.
    private var profileCompletions: [WorkoutCompletion] {
        if usesProfileFixture {
            return WorkoutCompletion.profileHubSampleData(now: today)
        }
        if externalStatsLoaded,
           actualsSources.isConnected(.strava) || actualsSources.isConnected(.appleHealth) {
            return externalCompletions
        }
        return historyViewModel.completions
    }

    private var usesExternalProfileStats: Bool {
        !usesProfileFixture
            && externalStatsLoaded
            && (actualsSources.isConnected(.strava) || actualsSources.isConnected(.appleHealth))
    }

    private var weekSummary: WeeklySummary {
        WeeklySummary(completions: weekCompletions)
    }

    private var weekCompletions: [WorkoutCompletion] {
        ProfileTrainingStats.weekCompletions(
            from: profileCompletions,
            now: today,
            calendar: mondayCalendar
        )
    }

    private var weekListCompletions: [WorkoutCompletion] {
        if usesProfileFixture {
            let sample = WorkoutCompletion.profileHubSampleData(now: today)
            let handoffIDs = ["profile-easy-shakeout", "profile-amrap", "profile-long-run"]
            return handoffIDs.compactMap { id in sample.first { $0.id == id } }
        }
        return weekCompletions.sorted { $0.startedAt > $1.startedAt }
    }

    private var detailRoute: ProfileHubRoute {
        usesExternalProfileStats ? .actualsHistory : .history
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileHeader
                    screenPad
                }
                .padding(.bottom, 120)
            }
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            // Keep title for pushed screens' back label ("< Profile") while hiding chrome on the hub.
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .navigationDestination(for: ProfileHubRoute.self) { route in
                switch route {
                case .settings:
                    SettingsView(navigateToSyncDashboard: $navigateToSyncDashboard)
                case .history:
                    ActivityHistoryView()
                case .coach:
                    CoachChatView()
                        .overlay(alignment: .top) {
                            Text(" ")
                                .font(.system(size: 1))
                                .opacity(0.01)
                                .accessibilityIdentifier("coach_screen")
                        }
                case .friends:
                    FriendsListView(store: friendsStore)
                case .actualsHistory:
                    ActualsHistoryView()
                case .actualsConnectSources:
                    ActualsConnectSourcesView()
                }
            }
            .task(id: "\(actualsSources.isConnected(.strava))-\(actualsSources.isConnected(.appleHealth))") {
                await historyViewModel.loadCompletions()
                await loadExternalProfileStats()
                await friendsStore.reload()
            }
            .overlay(alignment: .top) {
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("profile_screen")
            }
        }
    }

    private var profileHeader: some View {
        HStack(alignment: .center) {
            Text("Profile")
                .ddDisplayText(32, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)

            Spacer()

            Button {
                path.append(ProfileHubRoute.settings)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DailyDriver.foreground)
                    .frame(width: 38, height: 38)
                    .background(DailyDriver.card2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_profile_settings_entry")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var screenPad: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityRow
                .padding(.top, 10)

            statGrid
                .padding(.top, 14)

            weekDots
                .padding(.top, 12)

            // AMA-2389 mockup: Friends management lives on Profile (not only Settings).
            ProfileFriendsEntryRow(
                friendCount: friendsStore.acceptedFriends.count,
                waitingCount: friendsStore.unhandledShareCount,
                requestCount: friendsStore.incomingRequests.count
            ) {
                path.append(ProfileHubRoute.friends)
            }
            .padding(.top, 14)

            actualsHistoryEntryRow
                .padding(.top, 10)

            actualsConnectSourcesEntryRow
                .padding(.top, 10)

            ProfileThisWeekSection(
                entries: weekListCompletions,
                weekExpanded: $weekExpanded
            ) {
                path.append(detailRoute)
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 18)
    }

    /// AMA-2396: day-grouped Strava sync history — separate from the general
    /// planned-vs-actual `ActivityHistoryView` pushed from the stat tiles.
    private var actualsHistoryEntryRow: some View {
        Button {
            path.append(ProfileHubRoute.actualsHistory)
        } label: {
            HStack(spacing: 12) {
                DDIconChip(systemName: "clock.arrow.circlepath", background: DailyDriver.stravaBrand, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ActualsCopy.historyTitle)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(ActualsCopy.historyProfileEntrySub)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_profile_sync_history_entry")
    }

    /// AMA-2396: write-back lived only under Today → Connect Sources; surface it on Profile.
    private var actualsConnectSourcesEntryRow: some View {
        Button {
            path.append(ProfileHubRoute.actualsConnectSources)
        } label: {
            HStack(spacing: 12) {
                DDIconChip(systemName: "link", background: DailyDriver.orange, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ActualsCopy.connectSourcesProfileTitle)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(ActualsCopy.connectSourcesProfileSub)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_profile_connect_sources_entry")
    }

    private var identityRow: some View {
        HStack(spacing: 12) {
            Text(String(displayName.prefix(1)).uppercased())
                .ddDisplayText(17, weight: .heavy)
                .foregroundColor(DailyDriver.ink)
                .frame(width: 44, height: 44)
                .background(DailyDriver.lime)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .ddDisplayText(16, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                    .accessibilityIdentifier("af_profile_identity_name")
                Text("Hyrox prep · Week 3 of 12")
                    .font(.system(size: 10.5))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .opacity(usesProfileFixture ? 1 : 0)
                    .frame(height: usesProfileFixture ? nil : 0)
            }
        }
        .accessibilityIdentifier("af_profile_identity")
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            DDStatTile(
                value: weekSessionsValue,
                label: "sessions this week",
                valueColor: DailyDriver.lime
            ) {
                weekExpanded = true
                path.append(detailRoute)
            }
            .accessibilityIdentifier("af_profile_summary_week")

            DDStatTile(
                value: trainingTimeValue,
                label: "training time"
            ) {
                path.append(detailRoute)
            }
            .accessibilityIdentifier("af_profile_summary_totals")

            DDStatTile(
                value: streakDisplay.value,
                label: streakDisplay.label
            ) {
                path.append(detailRoute)
            }
            .accessibilityIdentifier("af_profile_summary_streak")

            DDStatTile(
                value: monthSessionCount,
                label: monthSessionsLabel
            ) {
                path.append(detailRoute)
            }
            .accessibilityIdentifier("af_profile_summary_calendar")
        }
        .accessibilityIdentifier("af_profile_summaries")
    }

    private var weekSessionsValue: String {
        if usesProfileFixture { return "1" }
        if weekSummary.workoutCount > 0 { return "\(weekSummary.workoutCount)" }
        if hasKnownTrainingData { return "0" }
        return "—"
    }

    private var trainingTimeValue: String {
        if usesProfileFixture { return "2h 14m" }
        if weekSummary.workoutCount > 0 { return weekSummary.formattedDuration }
        if hasKnownTrainingData { return "0m" }
        return "—"
    }

    private var hasKnownTrainingData: Bool {
        !profileCompletions.isEmpty || usesExternalProfileStats
    }

    private var monthSessionsLabel: String {
        let month = today.formatted(.dateTime.month(.wide))
        return "sessions in \(month)"
    }

    private var monthSessionCount: String {
        if usesProfileFixture { return "9" }
        let monthCompletions = ProfileTrainingStats.monthCompletions(
            from: profileCompletions,
            now: today,
            calendar: mondayCalendar
        )
        if !monthCompletions.isEmpty { return "\(monthCompletions.count)" }
        if hasKnownTrainingData { return "0" }
        return "—"
    }

    private var today: Date { Date() }

    private var streakDisplay: (value: String, label: String) {
        if usesProfileFixture {
            return ("3 🔥", "day streak · best 6")
        }
        let streak = ProfileTrainingStats.dayStreak(
            from: profileCompletions,
            today: today,
            calendar: mondayCalendar
        )
        if streak.current > 0 {
            return ("\(streak.current) 🔥", "day streak · best \(streak.best)")
        }
        if streak.best > 0 {
            return ("0", "day streak · best \(streak.best)")
        }
        return ("—", "day streak · best —")
    }

    private var weekDots: some View {
        profileWeekDots(
            usesFixture: usesProfileFixture,
            weekCompletions: weekCompletions,
            calendar: mondayCalendar
        )
    }

    private func loadExternalProfileStats() async {
        let wantsStrava = actualsSources.isConnected(.strava)
        let wantsApple = actualsSources.isConnected(.appleHealth)
        guard wantsStrava || wantsApple else {
            externalCompletions = []
            externalStatsLoaded = false
            return
        }

        var merged: [WorkoutCompletion] = []

        if wantsStrava {
            do {
                let result = try await BFFStravaClient.live().syncCompleted(daysBack: 60)
                if result.success {
                    merged.append(contentsOf: ProfileTrainingStats.completions(
                        from: result.activities,
                        calendar: mondayCalendar,
                        now: today
                    ))
                }
            } catch {
                // Fall through — Apple Health may still load.
            }
        }

        if wantsApple {
            do {
                let samples = try await LiveActualsHealthKitWorkoutFetcher().fetchWorkouts(daysBack: 60)
                merged.append(contentsOf: ActualsTodayDemoFeed.completions(from: samples))
            } catch {
                // Keep Strava rows if present.
            }
        }

        // AMA-2422: certain Strava↔Apple Health duplicates must not inflate week/month hours.
        externalCompletions = ActualsCrossSourceDeduper.dedupeCompletions(merged)
            .sorted { $0.startedAt > $1.startedAt }
        externalStatsLoaded = true
    }
}

private func profileWeekDots(
    usesFixture: Bool,
    weekCompletions: [WorkoutCompletion],
    calendar: Calendar
) -> DDWeekDots {
    let labels = ["M", "T", "W", "T", "F", "S", "S"]
    if usesFixture {
        return DDWeekDots(labels: labels, activeIndices: [0, 1])
    }
    let activeDays = Set(
        weekCompletions.map { calendar.component(.weekday, from: $0.startedAt) }
            .map { weekday in ((weekday + 5) % 7) }
    )
    return DDWeekDots(labels: labels, activeIndices: activeDays)
}
