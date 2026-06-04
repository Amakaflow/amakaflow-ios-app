//
//  RPEFeedbackView.swift
//  AmakaFlow
//
//  Post-workout RPE feedback (AMA-1266, design refresh completion screen).
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

    private var feedbackForm: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    Text("How hard did it feel?")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("Rate perceived exertion from 1 (easy) to 10 (max effort).")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.xl)

                AFLabel(text: "RPE (1–10)")
                AFRPEGrid(selection: $viewModel.selectedRPE)
                    .padding(.horizontal, Theme.Spacing.md)
                    .accessibilityIdentifier("rpe_grid")

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    AFLabel(text: "Injury or soreness (optional)")
                    TextField("e.g. tight left calf, sore quads", text: $viewModel.injuryNotes, axis: .vertical)
                        .lineLimit(2...4)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                                .stroke(Theme.Colors.borderLight, lineWidth: 1)
                        )
                        .accessibilityIdentifier("rpe_injury_notes")
                }
                .padding(.horizontal, Theme.Spacing.lg)

                VStack(spacing: Theme.Spacing.sm) {
                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        Group {
                            if viewModel.isSubmitting {
                                ProgressView()
                                    .tint(Theme.Colors.primaryForeground)
                            } else {
                                Text("Save workout")
                                    .font(Theme.Typography.bodyBold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                    .disabled(viewModel.selectedRPE == nil || viewModel.isSubmitting)
                    .accessibilityIdentifier("rpe_submit_button")

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
    }

    private var submittedView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.readyHigh)

            Text("Thanks!")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if viewModel.deloadRecommended {
                Text("Consider a lighter session next time")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.readyModerate)
            }
        }
        .transition(.opacity)
        .animation(.easeIn(duration: 0.3), value: viewModel.isSubmitted)
    }
}

#Preview {
    RPEFeedbackView(
        viewModel: RPEFeedbackViewModel(
            workoutId: "preview-workout",
            onComplete: {}
        )
    )
    .preferredColorScheme(.dark)
}
