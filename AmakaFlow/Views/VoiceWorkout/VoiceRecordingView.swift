//
//  VoiceRecordingView.swift
//  AmakaFlow
//
//  Initial view for starting voice recording to log a completed workout (AMA-5)
//

import SwiftUI

struct VoiceRecordingView: View {
    @ObservedObject var viewModel: VoiceWorkoutViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Microphone button
            Button {
                Task {
                    await viewModel.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.accentBlue)
                        .frame(width: 120, height: 120)
                        .shadow(color: Theme.Colors.accentBlue.opacity(0.4), radius: 20)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
            }

            // Instructions
            VStack(spacing: 8) {
                Text("Tap to Start Recording")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Describe the workout you just completed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Include exercises, sets, reps, and how long it took")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer()

            // Example prompts
            VStack(alignment: .leading, spacing: 16) {
                Text("Try saying something like:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    ExamplePrompt(text: "\"I just did a 45 minute strength workout with 4 sets of 10 squats, 3 sets of 12 lunges, and 3 sets of 15 pushups\"")

                    ExamplePrompt(text: "\"Just finished a 30 minute run, felt pretty good, did about 5K\"")

                    ExamplePrompt(text: "\"I did upper body today for about an hour: bench press 4x8, overhead press 3x10, and dumbbell rows 3x12 each side\"")
                }
            }
            .padding()
            .background(Theme.Colors.surface)
            .cornerRadius(12)
            .padding(.horizontal)

            Spacer()
        }
        .background(Theme.Colors.background)
    }
}

// MARK: - Example Prompt

private struct ExamplePrompt: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VoiceRecordingView(viewModel: VoiceWorkoutViewModel())
            .navigationTitle("Create Workout")
    }
}
