//
//  VoiceWorkoutView.swift
//  AmakaFlow
//
//  Main container view for voice logging of completed workouts (AMA-5)
//

import SwiftUI

struct VoiceWorkoutView: View {
    @StateObject private var viewModel = VoiceWorkoutViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(viewModel.state.displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        if viewModel.state == .idle || viewModel.state == .completed {
                            Button("Close") {
                                dismiss()
                            }
                        } else if !viewModel.state.isProcessing {
                            Button("Back") {
                                viewModel.goBack()
                            }
                        }
                    }

                    if viewModel.state == .reviewingWorkout {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Log") {
                                Task {
                                    await viewModel.logCompletedWorkout()
                                }
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            VoiceRecordingView(viewModel: viewModel)

        case .permissionRequired:
            PermissionRequiredView(viewModel: viewModel)

        case .recording:
            RecordingInProgressView(viewModel: viewModel)

        case .transcribing:
            ProcessingView(message: "Transcribing your voice...", icon: "waveform")

        case .reviewingTranscription:
            TranscriptionReviewView(viewModel: viewModel)

        case .parsing:
            ProcessingView(message: "Creating your workout...", icon: "dumbbell.fill")

        case .reviewingWorkout:
            VoiceWorkoutReviewView(viewModel: viewModel)

        case .saving:
            ProcessingView(message: "Logging to activity history...", icon: "checkmark.circle")

        case .completed:
            CompletedView(viewModel: viewModel, dismiss: { dismiss() })

        case .error(let message):
            ErrorView(message: message, viewModel: viewModel)
        }
    }
}

// MARK: - Permission Required View

private struct PermissionRequiredView: View {
    @ObservedObject var viewModel: VoiceWorkoutViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Permissions Required")
                .font(.title2)
                .fontWeight(.bold)

            Text("AmakaFlow needs access to your microphone and speech recognition to create workouts from your voice.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.requestPermissions()
                    }
                } label: {
                    Text("Enable Permissions")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(12)
                }

                Button("Open Settings") {
                    viewModel.openSettings()
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .background(Theme.Colors.background)
    }
}

// MARK: - Recording In Progress View

private struct RecordingInProgressView: View {
    @ObservedObject var viewModel: VoiceWorkoutViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Pulsing microphone animation
            ZStack {
                // Outer pulse
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 180, height: 180)
                    .scaleEffect(1.0 + CGFloat(viewModel.audioLevel) * 0.5)
                    .animation(.easeInOut(duration: 0.1), value: viewModel.audioLevel)

                // Inner pulse
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 140, height: 140)
                    .scaleEffect(1.0 + CGFloat(viewModel.audioLevel) * 0.3)
                    .animation(.easeInOut(duration: 0.1), value: viewModel.audioLevel)

                // Microphone icon
                Circle()
                    .fill(Color.red)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    )
            }

            // Duration
            Text(viewModel.formattedDuration)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text("Describe your workout...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            // Stop button
            Button {
                Task {
                    await viewModel.stopRecording()
                }
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop Recording")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            // Cancel button
            Button("Cancel") {
                viewModel.cancelRecording()
            }
            .foregroundColor(.secondary)
            .padding(.bottom)
        }
        .background(Theme.Colors.background)
    }
}

// MARK: - Processing View

private struct ProcessingView: View {
    let message: String
    let icon: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(Theme.Colors.accentBlue)

            ProgressView()
                .scaleEffect(1.5)
                .padding()

            Text(message)
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}

// MARK: - Completed View

private struct CompletedView: View {
    @ObservedObject var viewModel: VoiceWorkoutViewModel
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Workout Logged!")
                .font(.title)
                .fontWeight(.bold)

            if let workout = viewModel.workout {
                Text(workout.name)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            Text("Added to your activity history")
                .font(.subheadline)
                .foregroundColor(Theme.Colors.textTertiary)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    viewModel.startOver()
                } label: {
                    Text("Log Another")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(12)
                }

                Button("Done") {
                    dismiss()
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Theme.Colors.background)
    }
}

// MARK: - Error View

private struct ErrorView: View {
    let message: String
    @ObservedObject var viewModel: VoiceWorkoutViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Something went wrong")
                .font(.title2)
                .fontWeight(.bold)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    viewModel.startOver()
                } label: {
                    Text("Try Again")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(12)
                }

                Button("Go Back") {
                    viewModel.goBack()
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Theme.Colors.background)
    }
}

// MARK: - Preview

#Preview {
    VoiceWorkoutView()
}
