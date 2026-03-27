//
//  LeaderboardView.swift
//  AmakaFlow
//
//  Multi-dimension leaderboard — dimension tabs, period selector, ranked list (AMA-1278)
//

import SwiftUI

struct LeaderboardView: View {
    @StateObject private var viewModel: LeaderboardViewModel

    init(crewId: String? = nil) {
        _viewModel = StateObject(wrappedValue: LeaderboardViewModel(crewId: crewId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Scope tabs (Friends / Crew) — only show if no crew preset
            if viewModel.crewId == nil {
                scopeTabs
            }

            // Dimension tabs
            dimensionTabs

            // Period selector
            periodSelector

            Divider()
                .padding(.top, Theme.Spacing.xs)

            // Content
            if viewModel.isLoading && viewModel.entries.isEmpty {
                Spacer()
                ProgressView("Loading leaderboard...")
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(error)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if viewModel.entries.isEmpty {
                Spacer()
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("No data yet")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("Complete workouts to see rankings")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                Spacer()
            } else {
                leaderboardList
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Leaderboards")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadLeaderboard()
        }
        .task {
            if viewModel.entries.isEmpty {
                await viewModel.loadLeaderboard()
            }
        }
    }

    // MARK: - Scope Tabs

    private var scopeTabs: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(LeaderboardScope.allCases) { scope in
                Button {
                    Task { await viewModel.changeScope(scope) }
                } label: {
                    Text(scope.displayName)
                        .font(.system(size: 14, weight: viewModel.selectedScope == scope ? .bold : .medium))
                        .foregroundColor(viewModel.selectedScope == scope ? .white : Theme.Colors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            viewModel.selectedScope == scope
                                ? Theme.Colors.accentBlue
                                : Theme.Colors.surface
                        )
                        .cornerRadius(20)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Dimension Tabs

    private var dimensionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(LeaderboardDimension.allCases) { dimension in
                    Button {
                        Task { await viewModel.changeDimension(dimension) }
                    } label: {
                        Text(dimension.displayName)
                            .font(.system(size: 13, weight: viewModel.selectedDimension == dimension ? .bold : .medium))
                            .foregroundColor(viewModel.selectedDimension == dimension ? Theme.Colors.accentBlue : Theme.Colors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                viewModel.selectedDimension == dimension
                                    ? Theme.Colors.accentBlue.opacity(0.12)
                                    : Color.clear
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        viewModel.selectedDimension == dimension
                                            ? Theme.Colors.accentBlue.opacity(0.3)
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        HStack(spacing: 0) {
            ForEach(LeaderboardPeriod.allCases) { period in
                Button {
                    Task { await viewModel.changePeriod(period) }
                } label: {
                    Text(period.displayName)
                        .font(.system(size: 12, weight: viewModel.selectedPeriod == period ? .semibold : .regular))
                        .foregroundColor(viewModel.selectedPeriod == period ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.selectedPeriod == period
                                ? Theme.Colors.surface
                                : Color.clear
                        )
                        .cornerRadius(8)
                }
            }
        }
        .padding(4)
        .background(Theme.Colors.background)
        .cornerRadius(10)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: - Leaderboard List

    private var leaderboardList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(viewModel.entries) { entry in
                    LeaderboardEntryRow(
                        entry: entry,
                        formattedValue: viewModel.formattedValue(entry)
                    )
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
    }
}
