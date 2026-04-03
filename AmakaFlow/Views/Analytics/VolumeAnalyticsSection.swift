//
//  VolumeAnalyticsSection.swift
//  AmakaFlow
//
//  Container for all volume analytics components (AMA-1414)
//

import SwiftUI

struct VolumeAnalyticsSection: View {
    @StateObject private var viewModel = VolumeAnalyticsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Section header with period picker
            HStack {
                Text("Volume Analytics")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Picker("Period", selection: $viewModel.selectedPeriod) {
                    ForEach(VolumeAnalyticsViewModel.AnalyticsPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: viewModel.selectedPeriod) { newPeriod in
                    viewModel.changePeriod(newPeriod)
                }
            }

            if viewModel.isLoading {
                ProgressView("Loading volume data...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.lg)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentRed)
            } else if let data = viewModel.currentData {
                // Summary comparison cards
                summaryCards(data.summary)

                // Stacked bar chart
                VolumeBarChart(dataPoints: data.data)
                    .padding(.vertical, Theme.Spacing.sm)

                // Balance indicators
                BalanceIndicatorsView(
                    pushPullRatio: viewModel.pushPullRatio,
                    upperLowerRatio: viewModel.upperLowerRatio
                )

                // Muscle group breakdown
                Text("Muscle Groups")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                MuscleGroupBreakdown(groups: viewModel.sortedMuscleGroups)
            } else {
                Text("Complete some workouts to see volume analytics.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.vertical, Theme.Spacing.lg)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.lg)
        .task {
            await viewModel.loadVolume()
        }
    }

    private func summaryCards(_ summary: VolumeSummary) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            summaryCard("Volume", value: formatVolume(summary.totalVolume), change: viewModel.volumeChange)
            summaryCard("Sets", value: "\(summary.totalSets)", change: nil)
            summaryCard("Reps", value: "\(summary.totalReps)", change: nil)
        }
    }

    private func summaryCard(_ title: String, value: String, change: Double?) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(title)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
            if let change {
                HStack(spacing: 2) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8))
                    Text(String(format: "%.0f%%", abs(change)))
                        .font(.system(size: 10))
                }
                .foregroundColor(change >= 0 ? Theme.Colors.accentGreen : Theme.Colors.accentRed)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surfaceElevated)
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.1fk kg", value / 1000) }
        return "\(Int(value)) kg"
    }
}
