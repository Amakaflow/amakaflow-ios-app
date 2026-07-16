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
    @State private var backfillDrafts: [StrengthBackfillExerciseDraft] = []
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

    private var weekSummary: WeeklySummary {
        historyViewModel.weeklySummary
    }

    private var weekCompletions: [WorkoutCompletion] {
        historyViewModel.filteredCompletions.filter {
            ActivityHistoryFilter.thisWeek.includes(
                $0.startedAt,
                now: Date(),
                calendar: .current
            )
        }
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
            .sheet(isPresented: $showingBackfill) {
                NavigationStack {
                    StrengthBackfillView(
                        drafts: $backfillDrafts,
                        onSave: {
                            backfillCompleted = true
                            showingBackfill = false
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingBackfill = false }
                        }
                    }
                }
                .onAppear {
                    if backfillDrafts.isEmpty {
                        backfillDrafts = StrengthBackfill.draft(
                            from: [
                                .reps(sets: 3, reps: 8, name: "Back Squat", load: nil, restSec: 90, followAlongUrl: nil),
                                .reps(sets: 3, reps: 10, name: "Romanian Deadlift", load: nil, restSec: 60, followAlongUrl: nil)
                            ],
                            existingSetLogs: nil
                        )
                    }
                }
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

            coachAndHistorySection
                .padding(.top, 20)

            thisWeekSection
                .padding(.top, 8)
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
            }
        }
        .accessibilityIdentifier("af_profile_identity")
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            DDStatTile(
                value: weekSummary.workoutCount > 0 ? "\(weekSummary.workoutCount)/5" : "—",
                label: "sessions this week",
                valueColor: DailyDriver.lime
            ) {
                weekExpanded = true
                path.append(ProfileHubRoute.history)
            }
            .accessibilityIdentifier("af_profile_summary_week")

            DDStatTile(
                value: weekSummary.workoutCount > 0 ? weekSummary.formattedDuration : "—",
                label: "training time"
            ) {
                path.append(ProfileHubRoute.history)
            }
            .accessibilityIdentifier("af_profile_summary_totals")

            DDStatTile(
                value: "—",
                label: "day streak · best —"
            ) {
                path.append(ProfileHubRoute.history)
            }
            .accessibilityIdentifier("af_profile_summary_streak")

            DDStatTile(
                value: weekSummary.workoutCount > 0 ? "\(weekSummary.workoutCount)" : "—",
                label: "sessions this month"
            ) {
                path.append(ProfileHubRoute.history)
            }
            .accessibilityIdentifier("af_profile_summary_calendar")
        }
        .accessibilityIdentifier("af_profile_summaries")
    }

    private var weekDots: some View {
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
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

    private var coachAndHistorySection: some View {
        VStack(spacing: 8) {
            profileLinkRow(
                icon: "bubble.left.and.bubble.right.fill",
                iconBackground: DailyDriver.blue,
                title: "Coach",
                subtitle: "Chat, fatigue, readiness",
                identifier: "coach_tab"
            ) {
                path.append(ProfileHubRoute.coach)
            }

            profileLinkRow(
                icon: "clock.arrow.circlepath",
                iconBackground: DailyDriver.purple,
                title: "Activity History",
                subtitle: "Completed sessions",
                identifier: "history_tab"
            ) {
                path.append(ProfileHubRoute.history)
            }
        }
        .accessibilityIdentifier("af_profile_destinations")
    }

    private var thisWeekSection: some View {
        let entries = weekCompletions
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
                    systemName: completion.workoutTypeIconName,
                    background: DailyDriver.purple,
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

    private func profileLinkRow(
        icon: String,
        iconBackground: Color,
        title: String,
        subtitle: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                DDIconChip(systemName: icon, background: iconBackground, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                Spacer(minLength: 0)
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
        .accessibilityIdentifier(identifier)
    }
}

private extension WorkoutCompletion {
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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · HH:mm"
        return formatter.string(from: startedAt).uppercased()
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
