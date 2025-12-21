//
//  WorkoutPlayerView.swift
//  AmakaFlow
//
//  Main workout player UI for follow-along workouts on phone
//

import SwiftUI

struct WorkoutPlayerView: View {
    @ObservedObject var engine = WorkoutEngine.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showEndConfirmation = false
    @State private var showStepList = false

    var body: some View {
        ZStack {
            // Background
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                // Main content
                if engine.phase == .ended {
                    completionView
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.lg) {
                            // Current step display
                            StepDisplayView(engine: engine)

                            // Upcoming steps preview
                            upcomingStepsPreview
                        }
                    }

                    Spacer()

                    // Controls
                    PlayerControlsView(engine: engine) {
                        showEndConfirmation = true
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(engine.phase == .running)
        .confirmationDialog(
            "End Workout?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive) {
                engine.end(reason: .userEnded)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress will be saved.")
        }
        .sheet(isPresented: $showStepList) {
            stepListSheet
        }
        .onChange(of: engine.phase) { _, newPhase in
            if newPhase == .idle {
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Close button
            Button {
                showEndConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.surfaceElevated)
                    .clipShape(Circle())
            }

            Spacer()

            // Workout name
            VStack(spacing: 2) {
                Text(engine.workout?.name ?? "Workout")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                if engine.phase == .paused {
                    Text("PAUSED")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.accentRed)
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

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(Theme.Colors.accentGreen)

            Text("Workout Complete!")
                .font(Theme.Typography.title1)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Great job finishing \(engine.workout?.name ?? "your workout")!")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Stats
            HStack(spacing: Theme.Spacing.xl) {
                statItem(value: engine.formattedElapsedTime, label: "Duration")
                statItem(value: "\(engine.totalSteps)", label: "Steps")
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(Theme.Spacing.lg)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .monospacedDigit()

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
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
}

// MARK: - Preview

#Preview {
    WorkoutPlayerView()
}
