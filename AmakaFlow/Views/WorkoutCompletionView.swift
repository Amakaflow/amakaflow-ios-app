//
//  WorkoutCompletionView.swift
//  AmakaFlow
//
//  Summary screen shown after completing a workout with health metrics and HR chart
//

import SwiftUI
import Charts

struct WorkoutCompletionView: View {
    @ObservedObject var viewModel: WorkoutCompletionViewModel

    @State private var showPulse = true

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    Spacer(minLength: Theme.Spacing.xl)

                    // Success icon
                    successIcon

                    // Title and workout name
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Workout Complete!")
                            .font(Theme.Typography.title1)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text(viewModel.workoutName)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    // Stats grid
                    statsGrid

                    // Heart rate chart (if data available)
                    if !viewModel.heartRateSamples.isEmpty {
                        heartRateChart
                    } else if viewModel.hasHeartRateData {
                        // Has avg/max but no samples for chart
                        EmptyView()
                    } else {
                        noHeartRateDataView
                    }

                    Spacer(minLength: Theme.Spacing.xl)

                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xl)
            }
            .overlay(alignment: .top) {
                // Invisible marker for Maestro E2E tests (container views
                // don't expose accessibilityIdentifier on iOS 26)
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("workout_completion_screen")
            }

            // Coming Soon toast
            if viewModel.showComingSoonToast {
                VStack {
                    Spacer()
                    comingSoonToast
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: viewModel.showComingSoonToast)
            }
        }
        .onAppear {
            // Stop pulse animation after initial effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showPulse = false
                }
            }
        }
    }

    // MARK: - Success Icon

    private var successIcon: some View {
        ZStack {
            // Pulse animation
            if showPulse {
                Circle()
                    .fill(Theme.Colors.accentGreen.opacity(0.3))
                    .frame(width: 128, height: 128)
                    .scaleEffect(showPulse ? 1.3 : 1)
                    .opacity(showPulse ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: showPulse
                    )
            }

            // Outer ring
            Circle()
                .fill(Theme.Colors.accentGreen.opacity(0.2))
                .frame(width: 128, height: 128)

            // Inner circle
            Circle()
                .fill(Theme.Colors.accentGreen)
                .frame(width: 96, height: 96)

            // Checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: Theme.Spacing.sm),
            GridItem(.flexible(), spacing: Theme.Spacing.sm)
        ]

        return LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            // Duration
            StatCard(
                icon: "clock",
                iconColor: Theme.Colors.accentBlue,
                label: "Duration",
                value: viewModel.formattedDuration
            )

            // Calories
            if let calories = viewModel.calories {
                StatCard(
                    icon: "flame.fill",
                    iconColor: Theme.Colors.accentOrange,
                    label: "Calories",
                    value: "\(calories) kcal"
                )
            } else {
                StatCard(
                    icon: "flame.fill",
                    iconColor: Theme.Colors.textTertiary,
                    label: "Calories",
                    value: "--"
                )
            }

            // Avg Heart Rate
            if let avgHR = viewModel.calculatedAvgHeartRate {
                StatCard(
                    icon: "heart.fill",
                    iconColor: Theme.Colors.accentRed,
                    label: "Avg HR",
                    value: "\(avgHR) bpm"
                )
            } else {
                StatCard(
                    icon: "heart.fill",
                    iconColor: Theme.Colors.textTertiary,
                    label: "Avg HR",
                    value: "--"
                )
            }

            // Max Heart Rate
            if let maxHR = viewModel.calculatedMaxHeartRate {
                StatCard(
                    icon: "arrow.up.heart.fill",
                    iconColor: Theme.Colors.accentRed,
                    label: "Max HR",
                    value: "\(maxHR) bpm"
                )
            } else {
                StatCard(
                    icon: "arrow.up.heart.fill",
                    iconColor: Theme.Colors.textTertiary,
                    label: "Max HR",
                    value: "--"
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Heart Rate Chart

    private var heartRateChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.accentRed)
                Text("Heart Rate")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Chart(viewModel.heartRateSamples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("HR", sample.value)
                )
                .foregroundStyle(Theme.Colors.accentRed.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))

                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("HR", sample.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.accentRed.opacity(0.3), Theme.Colors.accentRed.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 80)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - No Heart Rate Data View

    private var noHeartRateDataView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "applewatch")
                .font(.system(size: 24))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No heart rate data")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            Text("Wear your Apple Watch during workouts to track heart rate")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // View Details button (stub)
            Button(action: viewModel.onViewDetails) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 14))
                    Text("View Details")
                        .font(Theme.Typography.bodyBold)
                }
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .cornerRadius(Theme.CornerRadius.md)
            }

            // Done button
            Button(action: viewModel.onDone) {
                Text("Done")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
            }
            .accessibilityIdentifier("completion_done_button")
        }
    }

    // MARK: - Coming Soon Toast

    private var comingSoonToast: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "clock")
                .font(.system(size: 14))
            Text("Coming Soon")
                .font(Theme.Typography.captionBold)
        }
        .foregroundColor(Theme.Colors.textPrimary)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.surfaceElevated)
        .cornerRadius(Theme.CornerRadius.lg)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)

                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }
}

// MARK: - Preview

#Preview {
    let sampleHR = (0..<20).map { i in
        HeartRateSample(
            timestamp: Date().addingTimeInterval(Double(i) * 30),
            value: Int.random(in: 120...160)
        )
    }

    return WorkoutCompletionView(
        viewModel: WorkoutCompletionViewModel(
            workoutName: "HIIT Cardio Blast",
            durationSeconds: 2700,
            deviceMode: .appleWatchPhone,
            calories: 320,
            avgHeartRate: 142,
            maxHeartRate: 175,
            heartRateSamples: sampleHR,
            onDismiss: {}
        )
    )
    .preferredColorScheme(.dark)
}
