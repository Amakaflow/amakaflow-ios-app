//
//  WorkoutPlayerView.swift
//  AmakaFlow
//
//  Main workout player UI for follow-along workouts on phone
//

import SwiftUI

struct WorkoutPlayerView: View {
    @ObservedObject var engine = WorkoutEngine.shared
    @ObservedObject var watchManager = WatchConnectivityManager.shared
    @ObservedObject var garminManager = GarminConnectManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showEndConfirmation = false
    @State private var showStepList = false
    @State private var deviceMode: DevicePreference = .phoneOnly
    @State private var shouldDismissImmediately = false  // Track if workout was discarded or saved for later

    var body: some View {
        ZStack {
            // Background - always visible
            Theme.Colors.background.ignoresSafeArea()

            // Debug: Show if no workout loaded
            if engine.workout == nil {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("No workout loaded")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Please try starting the workout again")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Go Back") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 0) {
                    // Header
                    header

                    // Main content
                    if engine.phase == .ended, let workout = engine.workout, !shouldDismissImmediately {
                    WorkoutCompletionView(
                        viewModel: WorkoutCompletionViewModel(
                            workoutName: workout.name,
                            durationSeconds: engine.elapsedSeconds,
                            deviceMode: deviceMode,
                            calories: watchManager.watchActiveCalories > 0 ? Int(watchManager.watchActiveCalories) : nil,
                            avgHeartRate: calculateAvgHeartRate(),
                            maxHeartRate: watchManager.watchMaxHeartRate > 0 ? Int(watchManager.watchMaxHeartRate) : nil,
                            heartRateSamples: watchManager.heartRateSamples,
                            onDismiss: {
                                watchManager.clearHealthMetrics()
                                garminManager.clearHealthMetrics()
                                dismiss()
                            }
                        )
                    )
                } else if engine.phase == .resting {
                    // Rest screen between exercises
                    RestPeriodView(engine: engine)
                        .id("rest-\(engine.currentStepIndex)")
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.lg) {
                            // Current step display
                            StepDisplayView(engine: engine)
                                .id("step-\(engine.currentStepIndex)-\(engine.stateVersion)")

                            // Upcoming steps preview
                            upcomingStepsPreview
                        }
                    }
                    .id("scroll-\(engine.currentStepIndex)")

                    Spacer()

                    // Controls
                    PlayerControlsView(engine: engine) {
                        // Pause while showing confirmation to stop timer updates
                        if engine.phase == .running {
                            engine.pause()
                        }
                        showEndConfirmation = true
                    }
                }
                }
            }
        }
        // Note: Removed .id("player-\(engine.stateVersion)") as it caused @State to reset
        // when stateVersion changed, dismissing the end workout confirmation dialog
        .navigationBarHidden(true)
        .statusBarHidden(engine.phase == .running)
        .alert("End Workout?", isPresented: $showEndConfirmation) {
            Button("Save & End") {
                engine.end(reason: .userEnded)
            }
            Button("Resume Later") {
                shouldDismissImmediately = true
                engine.end(reason: .savedForLater)
            }
            Button("Discard", role: .destructive) {
                shouldDismissImmediately = true
                engine.end(reason: .discarded)
            }
            Button("Cancel", role: .cancel) {
                // Resume workout if it was paused for the confirmation dialog
                if engine.phase == .paused {
                    engine.resume()
                }
            }
        } message: {
            Text("Save progress, resume later, or discard.")
        }
        .sheet(isPresented: $showStepList) {
            stepListSheet
        }
        .onChange(of: engine.phase) { oldPhase, newPhase in
            if newPhase == .idle {
                watchManager.clearHealthMetrics()
                garminManager.clearHealthMetrics()
                dismiss()
            } else if newPhase == .ended {
                // If workout was discarded or saved for later, dismiss immediately without showing completion view
                if shouldDismissImmediately {
                    watchManager.clearHealthMetrics()
                    garminManager.clearHealthMetrics()
                    // Small delay to allow engine to clean up
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                }
                // Otherwise keep metrics for display in completion view
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Close button
            Button {
                // Pause while showing confirmation to stop timer updates
                if engine.phase == .running {
                    engine.pause()
                }
                showEndConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.surfaceElevated)
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("CloseWorkoutButton")

            Spacer()

            // Workout name and heart rate
            VStack(spacing: 2) {
                Text(engine.workout?.name ?? "Workout")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                if engine.phase == .paused {
                    Text("PAUSED")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.accentRed)
                } else if engine.phase == .resting {
                    Text("REST")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.accentBlue)
                } else if watchManager.watchHeartRate > 0 {
                    watchHeartRateView
                } else if garminManager.isGarminHRAvailable && garminManager.garminHeartRate > 0 {
                    garminHeartRateView
                }
            }

            Spacer()

            // Step list button
            Button {
                showStepList = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.surfaceElevated)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Watch Heart Rate View

    private var watchHeartRateView: some View {
        HStack(spacing: 8) {
            // Heart rate
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                Text("\(Int(watchManager.watchHeartRate))")
                    .font(Theme.Typography.captionBold)
                    .monospacedDigit()
            }

            // Calories (if available)
            if watchManager.watchActiveCalories > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("\(Int(watchManager.watchActiveCalories))")
                        .font(Theme.Typography.caption)
                        .monospacedDigit()
                }
                .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.1))
        .cornerRadius(Theme.CornerRadius.sm)
    }

    // MARK: - Garmin Heart Rate View

    private var garminHeartRateView: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
            Text("\(Int(garminManager.garminHeartRate))")
                .font(Theme.Typography.captionBold)
                .monospacedDigit()
            // Small Garmin indicator to differentiate from Apple Watch
            Text("G")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.1))
        .cornerRadius(Theme.CornerRadius.sm)
    }

    // MARK: - Upcoming Steps Preview

    private var upcomingStepsPreview: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Coming Up")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(upcomingSteps) { step in
                        upcomingStepCard(step)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }

    private var upcomingSteps: [FlattenedInterval] {
        let nextIndex = engine.currentStepIndex + 1
        let endIndex = min(nextIndex + 3, engine.flattenedSteps.count)
        guard nextIndex < engine.flattenedSteps.count else { return [] }
        return Array(engine.flattenedSteps[nextIndex..<endIndex])
    }

    private func upcomingStepCard(_ step: FlattenedInterval) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(step.label)
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)

            if let time = step.formattedTime {
                Text(time)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textSecondary)
            } else {
                Text(step.details)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 120)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.sm)
    }

    // MARK: - Step List Sheet

    private var stepListSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(engine.flattenedSteps.enumerated()), id: \.element.id) { index, step in
                    Button {
                        engine.skipToStep(index)
                        showStepList = false
                    } label: {
                        HStack {
                            // Step number
                            Text("\(index + 1)")
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(stepNumberColor(for: index))
                                .frame(width: 28, height: 28)
                                .background(stepNumberBackground(for: index))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.label)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                HStack(spacing: Theme.Spacing.xs) {
                                    if let time = step.formattedTime {
                                        Text(time)
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.textSecondary)
                                    }

                                    if let round = step.roundInfo {
                                        Text(round)
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.accentBlue)
                                    }
                                }
                            }

                            Spacer()

                            if index == engine.currentStepIndex {
                                Image(systemName: "play.fill")
                                    .foregroundColor(Theme.Colors.accentBlue)
                            } else if index < engine.currentStepIndex {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.Colors.accentGreen)
                            }
                        }
                    }
                    .listRowBackground(
                        index == engine.currentStepIndex
                            ? Theme.Colors.accentBlue.opacity(0.1)
                            : Theme.Colors.surface
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("All Steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showStepList = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func stepNumberColor(for index: Int) -> Color {
        if index == engine.currentStepIndex {
            return .white
        } else if index < engine.currentStepIndex {
            return Theme.Colors.accentGreen
        } else {
            return Theme.Colors.textSecondary
        }
    }

    private func stepNumberBackground(for index: Int) -> Color {
        if index == engine.currentStepIndex {
            return Theme.Colors.accentBlue
        } else if index < engine.currentStepIndex {
            return Theme.Colors.accentGreen.opacity(0.2)
        } else {
            return Theme.Colors.surfaceElevated
        }
    }

    // MARK: - Heart Rate Helpers

    private func calculateAvgHeartRate() -> Int? {
        let samples = watchManager.heartRateSamples
        guard !samples.isEmpty else { return nil }
        let sum = samples.reduce(0) { $0 + $1.value }
        return sum / samples.count
    }
}

// MARK: - Preview

#Preview {
    WorkoutPlayerView()
}
