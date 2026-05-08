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

    /// AMA-1803 P0: the engine drives the honest verdict. If
    /// `engine.lastSaveError != nil` we replace the optimistic
    /// "Workout Complete!" header with a failure state and surface
    /// an `ErrorToast`. Optional so legacy call sites that don't pass
    /// an engine still compile (the success-path UI still renders).
    @ObservedObject var engine: WorkoutEngine

    @State private var showPulse = true

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // AMA-1803 P1 fix (CR major on PR #181): honest
                    // verdict header keys on the engine's tri-state
                    // saveStatus, not the nil-vs-non-nil error flag.
                    // The earlier P0 implementation showed
                    // "Workout Complete!" whenever lastSaveError == nil
                    // — which was ALSO true during the network round-
                    // trip. The user saw the green checkmark BEFORE
                    // the backend confirmed the save persisted. This
                    // fix splits idle/inFlight/succeeded/failed so
                    // each UI state is explicit.
                    switch engine.saveStatus {
                    case .idle, .succeeded:
                        successIcon
                        VStack(spacing: Theme.Spacing.sm) {
                            Text("Workout Complete!")
                                .font(Theme.Typography.title1)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(viewModel.workoutName)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    case .inFlight:
                        savingIcon
                        VStack(spacing: Theme.Spacing.sm) {
                            Text("Saving workout…")
                                .font(Theme.Typography.title1)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(viewModel.workoutName)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    case .failed:
                        failureIcon
                        VStack(spacing: Theme.Spacing.sm) {
                            Text("Couldn't save workout")
                                .font(Theme.Typography.title1)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(viewModel.workoutName)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
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

            // AMA-1803 P0: save-failure toast. Shown whenever the
            // post-end completion save terminally failed. The toast
            // names the action, surfaces the server error_code (when
            // the body provided one), and offers a Report button that
            // drops a Sentry breadcrumb correlated to AMA-1805's
            // server-side capture via `requestId`.
            //
            // CR-fix: wire onRetry for retryable failures (transient
            // network + 5xx). The earlier P0 cut at `onRetry: nil`
            // was over-aggressive — even though the network-resume
            // queue retries automatically, a synchronous user-tapped
            // Retry beats waiting for connectivity changes when the
            // user knows they're back online. ErrorToast itself
            // hides the button when isRetryable returns false.
            if let saveError = engine.lastSaveError {
                VStack {
                    Spacer()
                    ErrorToast(
                        actionTitle: "Couldn't save workout",
                        error: saveError,
                        onRetry: {
                            // Kick the persistent pending queue. Don't
                            // clear lastSaveError here — let the queue's
                            // success path naturally update state on the
                            // next round-trip. Manual dismiss still works.
                            Task {
                                await WorkoutCompletionService.shared.retryPendingCompletions()
                            }
                        },
                        onReport: {
                            ErrorReporter.shared.report(
                                action: "workout_save",
                                error: saveError,
                                endpoint: "/workouts/complete",
                                userId: PairingService.shared.userProfile?.id
                            )
                        },
                        onDismiss: {
                            engine.acknowledgeSaveError()
                        }
                    )
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: engine.lastSaveError == nil)
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
            Circle()
                .fill(Theme.Colors.readyHigh.opacity(0.18))
                .frame(width: 48, height: 48)

            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.Colors.readyHigh)
        }
    }

    /// AMA-1803 P1: shown while the post-end save is in flight.
    /// Same circle dimensions as success/failure so the layout
    /// doesn't shift between states. A spinner keeps the user
    /// honest that the operation is still pending.
    private var savingIcon: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.accentBlue.opacity(0.18))
                .frame(width: 48, height: 48)

            ProgressView()
                .progressViewStyle(.circular)
                .tint(Theme.Colors.accentBlue)
        }
        .accessibilityIdentifier("workout_save_in_flight_icon")
    }

    /// AMA-1803 P0: shown when the post-end save terminally failed.
    /// Same shape as `successIcon` so the layout doesn't shift, but
    /// red and unmistakable. Pairs with the "Couldn't save workout"
    /// header above it.
    private var failureIcon: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.18))
                .frame(width: 48, height: 48)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.red)
        }
        .accessibilityIdentifier("workout_save_failure_icon")
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
                .foregroundColor(Theme.Colors.surface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.textPrimary)
                .clipShape(Capsule())
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
        ),
        engine: WorkoutEngine.shared
    )
    .preferredColorScheme(.dark)
}
