//
//  RPEFeedbackView.swift
//  AmakaFlow
//
//  Post-workout RPE feedback prompt (AMA-1266)
//  Designed for <10 second interaction — tap emoji, optionally check muscles, submit
//

import SwiftUI

struct RPEFeedbackView: View {
    @ObservedObject var viewModel: RPEFeedbackViewModel

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            if viewModel.isSubmitted {
                submittedView
            } else {
                feedbackForm
            }
        }
        .accessibilityIdentifier("rpe_feedback_screen")
    }

    // MARK: - Feedback Form

    private var feedbackForm: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.xl)

            // Title
            Text("How was that?")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Rate your effort")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            // RPE emoji buttons
            HStack(spacing: Theme.Spacing.md) {
                ForEach(RPEOption.allCases) { option in
                    RPEOptionButton(
                        option: option,
                        isSelected: viewModel.selectedOption == option,
                        onTap: { viewModel.selectOption(option) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)

            // Muscle soreness (shown after RPE selection)
            if viewModel.selectedOption != nil {
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Any soreness?")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textSecondary)

                    muscleGrid
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.2), value: viewModel.selectedOption)
            }

            Spacer()

            // Action buttons
            VStack(spacing: Theme.Spacing.sm) {
                if viewModel.selectedOption != nil {
                    Button(action: {
                        Task { await viewModel.submit() }
                    }) {
                        Group {
                            if viewModel.isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Submit")
                                    .font(Theme.Typography.bodyBold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(Theme.CornerRadius.md)
                    }
                    .disabled(viewModel.isSubmitting)
                    .accessibilityIdentifier("rpe_submit_button")
                }

                Button(action: viewModel.skip) {
                    Text("Skip")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .accessibilityIdentifier("rpe_skip_button")
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    // MARK: - Muscle Grid

    private var muscleGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: Theme.Spacing.xs),
            GridItem(.flexible(), spacing: Theme.Spacing.xs),
            GridItem(.flexible(), spacing: Theme.Spacing.xs)
        ]

        return LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
            ForEach(MuscleGroup.allCases) { muscle in
                MuscleChip(
                    muscle: muscle,
                    isSelected: viewModel.selectedMuscles.contains(muscle),
                    onTap: { viewModel.toggleMuscle(muscle) }
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Submitted View

    private var submittedView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.accentGreen)

            Text("Thanks!")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if viewModel.deloadRecommended {
                Text("Consider a lighter session next time")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.accentOrange)
            }
        }
        .transition(.opacity)
        .animation(.easeIn(duration: 0.3), value: viewModel.isSubmitted)
    }
}

// MARK: - RPE Option Button

private struct RPEOptionButton: View {
    let option: RPEOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Theme.Spacing.xs) {
                Text(option.emoji)
                    .font(.system(size: 36))

                Text(option.label)
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.accentBlue.opacity(0.2) : Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(isSelected ? Theme.Colors.accentBlue : Theme.Colors.borderLight, lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
        .accessibilityIdentifier("rpe_option_\(option.label.lowercased())")
    }
}

// MARK: - Muscle Chip

private struct MuscleChip: View {
    let muscle: MuscleGroup
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(muscle.displayName)
                .font(Theme.Typography.caption)
                .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Theme.Colors.accentBlue : Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                        .stroke(isSelected ? Theme.Colors.accentBlue : Theme.Colors.borderLight, lineWidth: 1)
                )
                .cornerRadius(Theme.CornerRadius.sm)
        }
        .accessibilityIdentifier("muscle_\(muscle.rawValue)")
    }
}

// MARK: - Preview

#Preview {
    RPEFeedbackView(
        viewModel: RPEFeedbackViewModel(
            workoutId: "preview-workout",
            onComplete: {}
        )
    )
    .preferredColorScheme(.dark)
}
