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
    @StateObject private var suggestWorkoutViewModel = SuggestWorkoutViewModel()
    @State private var selectedCompletionId: String?
    @State private var showingSuggestWorkout = false
    @State private var scrubberSelectedIndex = 0

    private var today: Date { Date() }

    private var todaysCompletions: [WorkoutCompletion] {
        historyViewModel.todaysCompletions
    }

    private var scrubberDays: [DDScrubberDay] {
        historyViewModel.completions.scrubberDays(now: today)
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
            .sheet(isPresented: $showingSuggestWorkout) {
                SuggestWorkoutView(viewModel: suggestWorkoutViewModel)
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
                DevicesView()
                    .ddSuppressFloatingChrome()
            } label: {
                DDWatchReadinessPill(isConnected: watchConnectivity.isWatchReachable || watchConnectivity.isWatchAppInstalled)
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
        VStack(spacing: Theme.Spacing.md) {
            Text("Sessions land here as they happen — or add one with ＋")
                .font(.system(size: 12))
                .foregroundColor(DailyDriver.foregroundDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 26)
                .accessibilityIdentifier("af_today_empty_state")

            Button {
                suggestWorkoutViewModel.requestSuggestion()
                showingSuggestWorkout = true
            } label: {
                Text("Suggest a workout")
                    .font(Theme.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .md))
            .accessibilityIdentifier("ama1842.suggest.button")
            .accessibilityLabel("Suggest a Workout")
        }
        .accessibilityIdentifier("today_empty_diary")
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
                        title: completion.workoutName,
                        stats: completion.ddTimelineStats,
                        sourceLabel: completion.ddSourceCaption,
                        showsChevron: true,
                        trailingAction: AnyView(
                            Text("Log RPE")
                                .ddDisplayText(12, weight: .bold)
                                .foregroundColor(DailyDriver.amber)
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_today_completion_\(index)")
            }
        }
        .accessibilityIdentifier("af_today_diary_list")
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
