//
//  ActivityHistoryView.swift
//  AmakaFlow
//
//  Activity history list view showing completed workouts grouped by date
//

import SwiftUI

struct ActivityHistoryView: View {
    @StateObject private var viewModel = ActivityHistoryViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading && viewModel.completions.isEmpty {
                    loadingState
                } else if viewModel.isEmpty {
                    emptyState
                        .padding(.top, Theme.Spacing.xl * 2)
                } else {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Weekly Summary Card
                        if viewModel.weeklySummary.workoutCount > 0 {
                            WeeklySummaryCard(summary: viewModel.weeklySummary)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        // Grouped Completions
                        LazyVStack(spacing: Theme.Spacing.xl, pinnedViews: [.sectionHeaders]) {
                            ForEach(viewModel.groupedCompletions) { group in
                                Section {
                                    VStack(spacing: Theme.Spacing.sm) {
                                        ForEach(group.completions) { completion in
                                            NavigationLink(destination: CompletionDetailView(completionId: completion.id)) {
                                                CompletionRowView(completion: completion)
                                            }
                                            .buttonStyle(.plain)
                                            .onAppear {
                                                Task {
                                                    await viewModel.loadMoreIfNeeded(currentItem: completion)
                                                }
                                            }
                                        }
                                    }
                                } header: {
                                    sectionHeader(title: group.title)
                                }
                            }

                            // Loading more indicator
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .padding()
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                    .padding(.vertical, Theme.Spacing.lg)
                    .padding(.bottom, 100)
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Activity History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
            .refreshable {
                await viewModel.refreshCompletions()
            }
            .task {
                await viewModel.loadCompletions()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }

    // MARK: - Filter Menu

    private var filterMenu: some View {
        Menu {
            ForEach(ActivityHistoryFilter.allCases, id: \.self) { filter in
                Button {
                    viewModel.selectedFilter = filter
                } label: {
                    HStack {
                        Text(filter.rawValue)
                        if viewModel.selectedFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .semibold))
                Text("Filter")
                    .font(Theme.Typography.bodyBold)
            }
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading activities...")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, Theme.Spacing.xl * 3)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.surface)
                    .frame(width: 80, height: 80)

                Image(systemName: "figure.run")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text("No Activities Yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Complete a workout to see your\nactivity history here.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                // Navigate to workouts
            } label: {
                Text("Start a Workout")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accentGreen)
                    .cornerRadius(Theme.CornerRadius.md)
            }
            .padding(.top, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.xl)
    }
}

// MARK: - Completion Row View

struct CompletionRowView: View {
    let completion: WorkoutCompletion

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Checkmark icon
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentGreen.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.Colors.accentGreen)
            }

            // Workout info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(completion.workoutName)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(completion.formattedStartTime)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                // Metrics row
                HStack(spacing: Theme.Spacing.md) {
                    // Duration
                    metricLabel(icon: "timer", value: completion.formattedDuration)

                    // Heart rate
                    if let hr = completion.avgHeartRate {
                        metricLabel(icon: "heart.fill", value: "\(hr)", color: Theme.Colors.accentRed)
                    }

                    // Calories
                    if let cal = completion.activeCalories {
                        metricLabel(icon: "flame.fill", value: "\(cal)", color: Theme.Colors.accentOrange)
                    }
                }

                // Source row
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: completion.source.iconName)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Colors.textTertiary)

                    Text(completion.source.displayName)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)

                    if completion.isSyncedToStrava {
                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("Synced")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentGreen)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func metricLabel(icon: String, value: String, color: Color = Theme.Colors.textSecondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)

            Text(value)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}

// MARK: - Weekly Summary Card

struct WeeklySummaryCard: View {
    let summary: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("THIS WEEK")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)

            HStack(spacing: Theme.Spacing.lg) {
                summaryItem(value: "\(summary.workoutCount)", label: "workouts")
                summaryItem(value: summary.formattedDuration, label: "total time")
                summaryItem(value: "\(summary.formattedCalories)", label: "kcal")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func summaryItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }
}

// MARK: - Preview

#Preview {
    ActivityHistoryView()
        .preferredColorScheme(.dark)
}
