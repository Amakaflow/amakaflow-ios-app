//
//  FollowAlongPlayerView.swift
//  AmakaFlow
//
//  AMA-1182: Follow-along video playback view.
//  AVPlayer video with step overlay, play/pause, skip controls,
//  auto-advance on timed steps, and a scrollable step list.
//

import SwiftUI
import AVKit

struct FollowAlongPlayerView: View {
    @StateObject private var viewModel = FollowAlongPlayerViewModel()
    @Environment(\.dismiss) private var dismiss

    let workout: Workout

    @State private var showStepList = false
    @State private var showEndConfirmation = false

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                ProgressView("Loading workout...")
                    .foregroundColor(Theme.Colors.textPrimary)

            case .ended:
                endedView

            default:
                mainPlayerContent
            }
        }
        .overlay(alignment: .top) {
            Text(" ")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("follow_along_player_screen")
        }
        .navigationBarHidden(true)
        .statusBarHidden(viewModel.phase == .playing)
        .onAppear {
            viewModel.loadWorkout(workout)
        }
        .alert("End Follow-Along?", isPresented: $showEndConfirmation) {
            Button("End & Close") {
                viewModel.endWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress will not be saved.")
        }
        .sheet(isPresented: $showStepList) {
            stepListSheet
        }
    }

    // MARK: - Main Player Content

    private var mainPlayerContent: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            // Video player area
            videoPlayerArea
                .frame(maxHeight: UIScreen.main.bounds.height * 0.4)

            // Step overlay: current step info
            currentStepOverlay
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)

            // Progress bar
            progressBar
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)

            Spacer()

            // Step list (scrollable, current highlighted)
            stepListPreview
                .padding(.top, Theme.Spacing.sm)

            // Player controls
            controlsBar
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                if viewModel.phase == .playing {
                    viewModel.pause()
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
            .accessibilityIdentifier("CloseFollowAlongButton")

            Spacer()

            VStack(spacing: 2) {
                Text(workout.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)

                Text(viewModel.formattedElapsed)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }

            Spacer()

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

    // MARK: - Video Player

    private var videoPlayerArea: some View {
        Group {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                    .padding(.horizontal, Theme.Spacing.md)
            } else {
                // No video - show a placeholder with exercise name
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Theme.Colors.surface)

                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Theme.Colors.textTertiary)

                        if let step = viewModel.currentStep {
                            Text(step.name)
                                .font(Theme.Typography.title2)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }

    // MARK: - Step Overlay

    private var currentStepOverlay: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let step = viewModel.currentStep {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Step \(viewModel.currentStepIndex + 1) of \(viewModel.steps.count)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)

                        Text(step.name)
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    Spacer()

                    if step.isTimeBased {
                        Text(formatTime(viewModel.stepRemainingSeconds))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.Colors.accentGreen)
                    } else if let reps = step.reps {
                        VStack {
                            Text("\(reps)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(Theme.Colors.accentBlue)
                            Text("reps")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.md)
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.surface)
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.accentGreen)
                    .frame(width: geo.size.width * CGFloat(viewModel.progress), height: 4)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Step List Preview

    private var stepListPreview: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                        stepChip(step: step, index: index)
                            .id(step.id)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .onChange(of: viewModel.currentStepIndex) { _, newIndex in
                if let id = viewModel.steps[safe: newIndex]?.id {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 56)
    }

    private func stepChip(step: FollowAlongStep, index: Int) -> some View {
        let isCurrent = index == viewModel.currentStepIndex
        let isPast = index < viewModel.currentStepIndex

        return VStack(spacing: 2) {
            Text(step.name)
                .font(Theme.Typography.captionBold)
                .foregroundColor(isCurrent ? .white : (isPast ? Theme.Colors.accentGreen : Theme.Colors.textSecondary))
                .lineLimit(1)

            Text(step.formattedDuration)
                .font(Theme.Typography.footnote)
                .foregroundColor(isCurrent ? .white.opacity(0.8) : Theme.Colors.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(minWidth: 80)
        .background(isCurrent ? Theme.Colors.accentBlue : (isPast ? Theme.Colors.accentGreen.opacity(0.15) : Theme.Colors.surface))
        .cornerRadius(Theme.CornerRadius.sm)
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack(spacing: Theme.Spacing.xl) {
            // Previous step
            Button {
                viewModel.skipToPreviousStep()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(viewModel.currentStepIndex > 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            }
            .disabled(viewModel.currentStepIndex <= 0)
            .accessibilityIdentifier("PreviousStepButton")

            // Play / Pause
            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: viewModel.phase == .playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Theme.Colors.accentGreen)
            }
            .accessibilityIdentifier("PlayPauseButton")

            // Next step
            Button {
                viewModel.skipToNextStep()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .accessibilityIdentifier("NextStepButton")
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
        .background(Theme.Colors.surface)
    }

    // MARK: - Ended View

    private var endedView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.Colors.accentGreen)

            Text("Follow-Along Complete!")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Duration: \(viewModel.formattedElapsed)")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    // MARK: - Step List Sheet

    private var stepListSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                    Button {
                        viewModel.skipToStep(index)
                        showStepList = false
                    } label: {
                        HStack {
                            Text("\(index + 1)")
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(stepNumberColor(for: index))
                                .frame(width: 28, height: 28)
                                .background(stepNumberBackground(for: index))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.name)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text(step.formattedDuration)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            if index == viewModel.currentStepIndex {
                                Image(systemName: "play.fill")
                                    .foregroundColor(Theme.Colors.accentBlue)
                            } else if index < viewModel.currentStepIndex {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.Colors.accentGreen)
                            }
                        }
                    }
                    .listRowBackground(
                        index == viewModel.currentStepIndex
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

    // MARK: - Helpers

    private func stepNumberColor(for index: Int) -> Color {
        if index == viewModel.currentStepIndex { return .white }
        if index < viewModel.currentStepIndex { return Theme.Colors.accentGreen }
        return Theme.Colors.textSecondary
    }

    private func stepNumberBackground(for index: Int) -> Color {
        if index == viewModel.currentStepIndex { return Theme.Colors.accentBlue }
        if index < viewModel.currentStepIndex { return Theme.Colors.accentGreen.opacity(0.2) }
        return Theme.Colors.surfaceElevated
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// Safe subscript for Array in the view layer
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    FollowAlongPlayerView(
        workout: Workout(
            name: "HIIT Follow-Along",
            sport: .strength,
            duration: 600,
            intervals: [
                .warmup(seconds: 60, target: nil),
                .reps(sets: nil, reps: 20, name: "Jumping Jacks", load: nil, restSec: 15, followAlongUrl: nil),
                .reps(sets: nil, reps: 10, name: "Burpees", load: nil, restSec: 15, followAlongUrl: nil),
                .cooldown(seconds: 60, target: nil)
            ],
            description: "Follow-along HIIT",
            source: .coach
        )
    )
    .preferredColorScheme(.dark)
}
