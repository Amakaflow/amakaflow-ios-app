//
//  TodayDiaryView.swift
//  AmakaFlow
//
//  AMA-2292: Daily Driver Today tab — completed-activities diary shell.
//  AMA-2289: Sync completions (Garmin / phone) onto the rail.
//  Strava landings appear once upstream sync writes completions (mobile BFF TBD).
//  Plan/schedule chrome is intentionally omitted.
//

import SwiftUI

struct TodayDiaryView: View {
    @StateObject private var historyViewModel = ActivityHistoryViewModel()
    @StateObject private var suggestWorkoutViewModel = SuggestWorkoutViewModel()
    @State private var selectedCompletionId: String?
    @State private var showingSuggestWorkout = false

    private var today: Date { Date() }

    private var todaysCompletions: [WorkoutCompletion] {
        historyViewModel.todaysCompletions
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    if historyViewModel.isLoading && historyViewModel.completions.isEmpty {
                        loadingState
                    } else if todaysCompletions.isEmpty {
                        emptyDiaryState
                    } else {
                        diaryList
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                await historyViewModel.loadCompletions()
            }
            .refreshable {
                await historyViewModel.refreshCompletions()
            }
            .sheet(item: $selectedCompletionId) { completionId in
                NavigationStack {
                    CompletionDetailView(completionId: completionId)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    selectedCompletionId = nil
                                }
                            }
                        }
                }
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

    private var header: some View {
        VStack(spacing: 2) {
            Text("Today")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .accessibilityIdentifier("af_today_title")
            AFLabel(
                text: today.formatted(.dateTime.weekday(.abbreviated)).uppercased()
                    + " · "
                    + today.formatted(.dateTime.month(.abbreviated).day()).uppercased()
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var loadingState: some View {
        AFCard(padding: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .tint(Theme.Colors.accentGreen)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Loading today’s diary")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Pulling completed activities only — no schedule.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("af_today_loading")
    }

    private var emptyDiaryState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AFLabel(text: "Completed diary")
            Text("No completed activities yet")
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Colors.textPrimary)
                .accessibilityIdentifier("af_today_empty_state")
            Text("Today shows finished sessions only — no plan or schedule. Completions sync from Garmin and phone land here automatically.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)

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
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        .accessibilityIdentifier("today_empty_diary")
    }

    private var diaryList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AFLabel(text: "Completed today")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("af_today_diary_header")

            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(todaysCompletions.enumerated()), id: \.element.id) { index, completion in
                    Button {
                        selectedCompletionId = completion.id
                    } label: {
                        CompletionRowView(completion: completion)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_today_completion_\(index)")
                }
            }
            .accessibilityIdentifier("af_today_diary_list")
        }
    }
}

#if DEBUG
#Preview("Today diary · empty") {
    TodayDiaryView()
        .preferredColorScheme(.dark)
}
#endif
