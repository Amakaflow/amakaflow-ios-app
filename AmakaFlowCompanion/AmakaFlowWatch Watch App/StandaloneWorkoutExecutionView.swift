//
//  StandaloneWorkoutExecutionView.swift
//  AmakaFlowWatch Watch App
//
//  Execution UI for standalone watch workouts with live heart rate display
//

import SwiftUI

struct StandaloneWorkoutExecutionView: View {
    @StateObject private var engine = StandaloneWorkoutEngine.shared
    @Environment(\.dismiss) private var dismiss

    let workout: Workout

    @State private var showEndConfirmation = false

    var body: some View {
        Group {
            if engine.phase == .ended {
                completeView
            } else if engine.isActive {
                activeWorkoutView
            } else {
                // Starting state
                ProgressView("Starting...")
                    .onAppear {
                        Task {
                            await engine.start(workout: workout)
                        }
                    }
            }
        }
        .navigationBarBackButtonHidden(engine.isActive)
        .confirmationDialog(
            "End Workout?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive) {
                Task {
                    await engine.end(reason: .userEnded)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Active Workout View

    private var activeWorkoutView: some View {
        ScrollView {
            VStack(spacing: 4) {
                // Heart Rate Display
                if engine.heartRate > 0 {
                    heartRateView
                }

                // Step name (primary focus)
                Text(engine.currentStep?.label ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                // Timer (large and prominent)
                if engine.currentStep?.stepType == .timed {
                    Text(engine.formattedRemainingTime)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(engine.phase == .paused ? .orange : .primary)
                } else if let reps = engine.currentStep?.targetReps {
                    Text("\(reps) reps")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.blue)
                }

                // Progress
                HStack {
                    ProgressView(value: engine.progress)
                        .tint(.blue)
                    Text("\(engine.currentStepIndex + 1)/\(engine.totalSteps)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)

                // Round info
                if let roundInfo = engine.currentStep?.roundInfo {
                    Text(roundInfo)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Controls
                controlsView
                    .padding(.top, 4)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Heart Rate View

    private var heartRateView: some View {
        HStack(spacing: 8) {
            // Heart rate
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                Text("\(Int(engine.heartRate))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            // Calories
            if engine.activeCalories > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("\(Int(engine.activeCalories))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 6) {
            // Play/Pause + Navigation Row
            HStack(spacing: 16) {
                // Previous
                Button {
                    engine.previousStep()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(engine.currentStepIndex == 0 ? .gray : .primary)
                }
                .buttonStyle(.plain)
                .disabled(engine.currentStepIndex == 0)

                // Play/Pause (prominent)
                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.phase == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22))
                        .frame(width: 50, height: 50)
                        .background(engine.phase == .paused ? Color.green : Color.orange)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Next / Done
                Button {
                    if engine.currentStepIndex >= engine.totalSteps - 1 {
                        // Last step - complete workout
                        Task {
                            await engine.end(reason: .completed)
                        }
                    } else {
                        engine.nextStep()
                    }
                } label: {
                    Image(systemName: engine.currentStepIndex >= engine.totalSteps - 1 ? "checkmark" : "forward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(engine.currentStepIndex >= engine.totalSteps - 1 ? .green : .primary)
                }
                .buttonStyle(.plain)
            }

            // End button
            Button {
                showEndConfirmation = true
            } label: {
                Text("End Workout")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Complete View

    private var completeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)

            Text("Complete!")
                .font(.title2)
                .fontWeight(.bold)

            // Stats
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text(engine.formattedElapsedTime)
                        .font(.headline)
                }

                if engine.activeCalories > 0 {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("\(Int(engine.activeCalories)) cal")
                            .font(.headline)
                    }
                }
            }
            .padding(.vertical, 8)

            Button("Done") {
                engine.reset()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    // Create a sample workout for preview
    let sampleWorkout = Workout(
        id: "preview-1",
        name: "Sample Workout",
        sport: .strength,
        duration: 150,
        intervals: [
            .warmup(seconds: 60, target: "Get ready"),
            .reps(reps: 10, name: "Push-ups", load: nil, restSec: 30, followAlongUrl: nil),
            .cooldown(seconds: 60, target: "Stretch")
        ],
        description: "A sample workout",
        source: .ai
    )
    StandaloneWorkoutExecutionView(workout: sampleWorkout)
}
