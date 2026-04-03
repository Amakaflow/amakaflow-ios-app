//
//  AnalyticsView.swift
//  AmakaFlow
//
//  Analytics Hub showing workout trends, records, and distribution. (AMA-1234)
//

import SwiftUI

struct AnalyticsView: View {
    @StateObject private var viewModel = AnalyticsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    if viewModel.isLoading {
                        loadingState
                    } else if let error = viewModel.errorMessage {
                        errorState(error)
                    } else {
                        // Weekly Summary
                        weeklySummaryCard

                        // Volume Trends
                        volumeTrendsCard

                        // Fatigue Indicator
                        if viewModel.fatigueLevel != nil {
                            fatigueCard
                        }

                        // Personal Records
                        if !viewModel.personalRecords.isEmpty {
                            personalRecordsCard
                        }

                        // Sport Distribution
                        if !viewModel.sportDistribution.isEmpty {
                            sportDistributionCard
                        }

                        // Volume Analytics (AMA-1414)
                        VolumeAnalyticsSection()
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .padding(.bottom, 40)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await viewModel.loadAnalytics()
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer().frame(height: 60)
            ProgressView()
                .scaleEffect(1.2)
                .tint(Theme.Colors.accentBlue)
            Text("Loading analytics...")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer().frame(height: 60)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(Theme.Colors.accentOrange)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.loadAnalytics() }
            }
            .font(Theme.Typography.bodyBold)
            .foregroundColor(Theme.Colors.accentBlue)
        }
    }

    // MARK: - Weekly Summary Card

    private var weeklySummaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "calendar")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.accentBlue)
                Text("This Week")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            HStack(spacing: Theme.Spacing.md) {
                SummaryStatView(
                    value: "\(viewModel.weeklyWorkoutCount)",
                    label: "Workouts",
                    color: Theme.Colors.accentBlue
                )
                SummaryStatView(
                    value: viewModel.formattedWeeklyDuration,
                    label: "Duration",
                    color: Theme.Colors.accentGreen
                )
                SummaryStatView(
                    value: "\(viewModel.weeklyExerciseCount)",
                    label: "Exercises",
                    color: Theme.Colors.accentOrange
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    // MARK: - Volume Trends Card

    private var volumeTrendsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.accentGreen)
                Text("Workout Volume")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("Last 8 weeks")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if viewModel.volumeTrends.isEmpty {
                Text("No data yet")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.Spacing.lg)
            } else {
                // Bar chart
                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.volumeTrends) { trend in
                        VStack(spacing: Theme.Spacing.xs) {
                            Text("\(trend.workoutCount)")
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.textSecondary)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(trend.workoutCount > 0 ? Theme.Colors.accentGreen : Theme.Colors.surfaceElevated)
                                .frame(
                                    height: max(4, CGFloat(trend.workoutCount) / CGFloat(max(viewModel.maxTrendCount, 1)) * 100)
                                )

                            Text(trend.weekLabel)
                                .font(.system(size: 9))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    // MARK: - Fatigue Card

    private var fatigueCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 16))
                    .foregroundColor(fatigueColor)
                Text("Fatigue Level")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                if let level = viewModel.fatigueLevel {
                    Text(level)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(fatigueColor)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(fatigueColor.opacity(0.15))
                        .cornerRadius(Theme.CornerRadius.sm)
                }
            }

            if let message = viewModel.fatigueMessage {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    private var fatigueColor: Color {
        switch viewModel.fatigueLevel?.lowercased() {
        case "low": return Theme.Colors.accentGreen
        case "moderate": return Theme.Colors.accentOrange
        case "high": return Theme.Colors.accentRed
        case "critical": return Color(hex: "DC2626")
        default: return Theme.Colors.textSecondary
        }
    }

    // MARK: - Personal Records Card

    private var personalRecordsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "FBBF24"))
                Text("Personal Records")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.personalRecords.indices, id: \.self) { index in
                    let record = viewModel.personalRecords[index]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.title)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                            Text(record.workoutName)
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(record.value)
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(record.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)

                    if index < viewModel.personalRecords.count - 1 {
                        Divider()
                            .background(Theme.Colors.borderLight)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    // MARK: - Sport Distribution Card

    private var sportDistributionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.accentBlue)
                Text("Workout Types")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.sportDistribution) { dist in
                    HStack(spacing: Theme.Spacing.md) {
                        Circle()
                            .fill(sportColor(for: dist.sport))
                            .frame(width: 10, height: 10)

                        Text(dist.sport)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Spacer()

                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.Colors.surfaceElevated)
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(sportColor(for: dist.sport))
                                    .frame(width: geometry.size.width * dist.percentage / 100, height: 6)
                            }
                        }
                        .frame(width: 80, height: 6)

                        Text("\(dist.count)")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    private func sportColor(for sport: String) -> Color {
        switch sport.lowercased() {
        case "running": return Theme.Colors.accentGreen
        case "strength": return Theme.Colors.accentBlue
        case "mobility": return Color(hex: "9333EA")
        case "cycling": return Color(hex: "06B6D4")
        case "swimming": return Color(hex: "06B6D4")
        case "cardio": return Theme.Colors.accentRed
        default: return Theme.Colors.textSecondary
        }
    }
}

// MARK: - Summary Stat View

private struct SummaryStatView: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.Typography.title2)
                .foregroundColor(color)
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    AnalyticsView()
        .preferredColorScheme(.dark)
}
