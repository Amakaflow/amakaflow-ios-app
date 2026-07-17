//
//  TodayDiaryView.swift
//  AmakaFlow
//
//  AMA-2292: Daily Driver Today tab — completed-activities diary shell.
//  AMA-2289: Sync completions (Garmin / phone) onto the rail.
//  Daily Driver Proto: DDTodayScreen — day scrubber + timeline cards.
//

import SwiftUI

struct TodayDiaryView: View {
    @StateObject private var historyViewModel = ActivityHistoryViewModel()
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    @State private var selectedCompletionId: String?
    @State private var scrubberSelectedIndex = 0

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow

                if !scrubberDays.isEmpty {
                    DDDayScrubber(days: scrubberDays, selectedIndex: $scrubberSelectedIndex)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if historyViewModel.isLoading && historyViewModel.completions.isEmpty {
                            loadingState
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
            }
            .refreshable {
                await historyViewModel.refreshCompletions()
            }
            .sheet(item: $selectedCompletionId) { completionId in
                DDActivityDetailView(completionId: completionId)
            }
            .overlay(alignment: .top) {
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("today_screen")
            }
        }
    }

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
                    isConnected: watchConnected || usesTodayFixture,
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
        todaysCompletions.contains { $0.source == .garmin } || usesTodayFixture
    }

    private var garminPulledCount: Int {
        let garminCount = todaysCompletions.filter { $0.source == .garmin }.count
        if usesTodayFixture { return max(2, garminCount) }
        return max(1, garminCount)
    }

    private var garminSyncTimeLabel: String {
        if usesTodayFixture { return "07:41" }
        let garminCompletions = todaysCompletions.filter { $0.source == .garmin }
        guard let earliest = garminCompletions.map(\.startedAt).min() else {
            return "—"
        }
        return earliest.formatted(date: .omitted, time: .shortened)
    }

    private var dayStartedTimeLabel: String {
        if usesTodayFixture { return "06:58" }
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

#if DEBUG
#Preview("Today diary · empty") {
    TodayDiaryView()
        .preferredColorScheme(.dark)
}
#endif
