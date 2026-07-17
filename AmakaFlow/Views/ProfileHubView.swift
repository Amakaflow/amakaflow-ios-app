//
//  ProfileHubView.swift
//  AmakaFlow
//
//  AMA-2292: Daily Driver Profile tab — identity, stat tiles, week activity.
//

import SwiftUI

enum ProfileHubRoute: Hashable {
    case settings
    case history
    case coach
}

struct ProfileHubView: View {
    @Binding var navigateToSyncDashboard: Bool
    @Binding var path: NavigationPath

    @EnvironmentObject private var pairingService: PairingService
    @AppStorage(DefaultsKey.userDisplayName.rawValue) private var displayNameOverride: String = ""
    @StateObject private var historyViewModel = ActivityHistoryViewModel()
    @State private var weekExpanded = false
    @State private var showingBackfill = false
    @AppStorage("dd_profile_backfill_completed") private var backfillCompleted = false

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
        DDHandoffFixtures.isEnabled && !historyViewModel.isLoading && historyViewModel.completions.isEmpty
    }

    private var profileCompletions: [WorkoutCompletion] {
        usesProfileFixture
            ? WorkoutCompletion.profileHubSampleData(now: today)
            : historyViewModel.completions
    }

    private var weekSummary: WeeklySummary {
        WeeklySummary(completions: weekCompletions)
    }

    private var weekCompletions: [WorkoutCompletion] {
        profileCompletions.filter {
            ActivityHistoryFilter.thisWeek.includes(
                $0.startedAt,
                now: today,
                calendar: .current
            )
        }
    }

    private var weekListCompletions: [WorkoutCompletion] {
        if usesProfileFixture {
            let sample = WorkoutCompletion.profileHubSampleData(now: today)
            let handoffIDs = ["profile-easy-shakeout", "profile-amrap", "profile-long-run"]
            return handoffIDs.compactMap { id in sample.first { $0.id == id } }
        }
        return weekCompletions.sorted { $0.startedAt > $1.startedAt }
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
            .navigationBarHidden(true)
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
                }
            }
            .task {
                await historyViewModel.loadCompletions()
            }
            .overlay(alignment: .top) {
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("profile_screen")
            }
            .fullScreenCover(isPresented: $showingBackfill) {
                DDEditorView(mode: .backfill) {
                    backfillCompleted = true
                }
                .ddSuppressFloatingChrome()
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

            if !backfillCompleted {
                DDInsightBanner(
                    title: "Monday's strength needs weights",
                    subtitle: "2-minute backfill"
                ) {
                    showingBackfill = true
                }
                .padding(.top, 14)
            }

            thisWeekSection
                .padding(.top, 20)
        }
        .padding(.horizontal, 18)
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
                value: usesProfileFixture ? "1/5" : (weekSummary.workoutCount > 0 ? "\(weekSummary.workoutCount)/5" : "—"),
                label: "sessions this week",
                valueColor: DailyDriver.lime
            ) {
                weekExpanded = true
                path.append(ProfileHubRoute.history)
            }
            .accessibilityIdentifier("af_profile_summary_week")

            DDStatTile(
                value: usesProfileFixture ? "2h 14m" : (weekSummary.workoutCount > 0 ? weekSummary.formattedDuration : "—"),
                label: "training time"
            ) {
                path.append(ProfileHubRoute.history)
            }
            .accessibilityIdentifier("af_profile_summary_totals")

            DDStatTile(
                value: streakDisplay.value,
                label: streakDisplay.label
            ) {
                path.append(ProfileHubRoute.history)
            }
            .accessibilityIdentifier("af_profile_summary_streak")

            DDStatTile(
                value: monthSessionCount,
                label: monthSessionsLabel
            ) {
                path.append(ProfileHubRoute.history)
            }
            .accessibilityIdentifier("af_profile_summary_calendar")
        }
        .accessibilityIdentifier("af_profile_summaries")
    }

    private var monthSessionsLabel: String {
        let month = today.formatted(.dateTime.month(.wide))
        return "sessions in \(month)"
    }

    private var monthSessionCount: String {
        if usesProfileFixture { return "9" }
        let calendar = Calendar.current
        let monthCompletions = profileCompletions.filter {
            calendar.isDate($0.startedAt, equalTo: today, toGranularity: .month)
        }
        return monthCompletions.isEmpty ? "—" : "\(monthCompletions.count)"
    }

    private var today: Date { Date() }

    private var streakDisplay: (value: String, label: String) {
        if usesProfileFixture {
            return ("3 🔥", "day streak · best 6")
        }
        let streak = computeDayStreak(from: profileCompletions)
        if streak.current > 0 {
            return ("\(streak.current) 🔥", "day streak · best \(streak.best)")
        }
        return ("—", "day streak · best —")
    }

    private func computeDayStreak(from completions: [WorkoutCompletion]) -> (current: Int, best: Int) {
        let calendar = Calendar.current
        let activeDays = Set(
            completions.map { calendar.startOfDay(for: $0.startedAt) }
        )
        guard !activeDays.isEmpty else { return (0, 0) }

        var current = 0
        var cursor = calendar.startOfDay(for: today)
        while activeDays.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let sortedDays = activeDays.sorted()
        var best = 0
        var run = 0
        var prior: Date?
        for day in sortedDays {
            if let prior,
               let next = calendar.date(byAdding: .day, value: 1, to: prior),
               calendar.isDate(day, inSameDayAs: next) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            prior = day
        }
        return (current, best)
    }

    private var weekDots: some View {
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
        if usesProfileFixture {
            return DDWeekDots(labels: labels, activeIndices: [0, 1])
        }
        let calendar = Calendar.current
        let activeDays = Set(
            weekCompletions.map { calendar.component(.weekday, from: $0.startedAt) }
                .map { weekdayIndex(from: $0) }
        )
        return DDWeekDots(labels: labels, activeIndices: activeDays)
    }

    private func weekdayIndex(from weekday: Int) -> Int {
        // Calendar weekday: 1 = Sunday. Design labels start Monday.
        ((weekday + 5) % 7)
    }

    private var thisWeekSection: some View {
        let entries = weekListCompletions
        let shown = weekExpanded ? entries : Array(entries.prefix(3))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week")
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Spacer()
                if entries.count > 3 {
                    Button(weekExpanded ? "Show less" : "See all (\(entries.count))") {
                        weekExpanded.toggle()
                    }
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
                }
            }

            if shown.isEmpty {
                Text("No sessions yet this week.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(shown) { completion in
                    weekActivityRow(completion)
                }
            }
        }
    }

    private func weekActivityRow(_ completion: WorkoutCompletion) -> some View {
        Button {
            path.append(ProfileHubRoute.history)
        } label: {
            HStack(spacing: 12) {
                DDIconChip(
                    systemName: completion.profileIconName,
                    background: completion.profileIconBackground,
                    size: 34
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(completion.workoutName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DailyDriver.foreground)
                        .lineLimit(1)
                    Text(completion.profileMetaLine)
                        .font(.system(size: 10))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(completion.profileBigValue)
                        .ddDisplayText(18, weight: .heavy)
                        .foregroundColor(DailyDriver.foreground)
                    Text(completion.profileUnitLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private extension WorkoutCompletion {
    var profileIconName: String {
        if distanceMeters != nil { return "figure.run" }
        if workoutName.localizedCaseInsensitiveContains("amrap") { return "bolt.fill" }
        return "figure.cooldown"
    }

    var profileIconBackground: Color {
        if distanceMeters != nil { return DailyDriver.blue }
        if workoutName.localizedCaseInsensitiveContains("amrap") { return DailyDriver.purple }
        return DailyDriver.blue
    }

    var workoutTypeIconName: String {
        if distanceMeters != nil { return "figure.run" }
        return "dumbbell.fill"
    }

    var profileBigValue: String {
        if let distanceMeters, distanceMeters > 0 {
            return String(format: "%.1f", Double(distanceMeters) / 1000.0)
        }
        let minutes = durationSeconds / 60
        return "\(minutes)"
    }

    var profileUnitLabel: String {
        distanceMeters != nil ? "KM" : "MIN"
    }

    var profileMetaLine: String {
        let day = startedAt.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let minutes = max(1, durationSeconds / 60)
        let duration: String
        if minutes >= 60 {
            duration = "\(minutes / 60)H \(minutes % 60)M"
        } else {
            duration = "\(minutes) MIN"
        }
        var parts = [day, duration]
        if let hr = avgHeartRate {
            parts.append("\(hr) BPM")
        }
        switch source {
        case .garmin: parts.append("GARMIN")
        case .appleWatch: parts.append("APPLE WATCH")
        case .phone: parts.append("ON PHONE")
        case .manual: break
        }
        if isSyncedToStrava, source != .garmin {
            parts.append("STRAVA")
        }
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
#Preview("Profile hub") {
    ProfileHubView(
        navigateToSyncDashboard: .constant(false),
        path: .constant(NavigationPath())
    )
    .environmentObject(PairingService.shared)
}
#endif
