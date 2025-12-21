//
//  PlayerControlsView.swift
//  AmakaFlow
//
//  Playback controls for the workout player
//

import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var engine: WorkoutEngine
    var onEnd: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Progress bar
            progressBar

            // Main controls
            HStack(spacing: Theme.Spacing.xl) {
                // Previous button
                Button {
                    engine.previousStep()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 28))
                        .foregroundColor(engine.currentStepIndex > 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                }
                .disabled(engine.currentStepIndex == 0)

                // Play/Pause button
                Button {
                    engine.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.accentBlue)
                            .frame(width: 72, height: 72)

                        Image(systemName: engine.phase == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                }

                // Next button
                Button {
                    engine.nextStep()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }

            // Step counter
            Text(engine.formattedStepProgress)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            // End workout button
            Button {
                onEnd()
            } label: {
                Text("End Workout")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.accentRed)
                    .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // Progress track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.borderLight)
                        .frame(height: 8)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.accentBlue)
                        .frame(width: geometry.size.width * engine.progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: engine.progress)
                }
            }
            .frame(height: 8)

            // Time labels
            HStack {
                Text(engine.formattedElapsedTime)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .monospacedDigit()

                Spacer()

                Text("\(Int(engine.progress * 100))%")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }
}

// MARK: - Mini Controls (for collapsed state)

struct MiniPlayerControlsView: View {
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // Previous
            Button {
                engine.previousStep()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 20))
                    .foregroundColor(engine.currentStepIndex > 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            }
            .disabled(engine.currentStepIndex == 0)

            // Play/Pause
            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.phase == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.Colors.accentBlue)
            }

            // Next
            Button {
                engine.nextStep()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()

        VStack {
            Spacer()
            PlayerControlsView(engine: WorkoutEngine.shared) {
                print("End workout")
            }
        }
    }
}
