//
//  GoalStepView.swift
//  AmakaFlow
//
//  Wizard step 1: Choose training goal (AMA-1413)
//

import SwiftUI

struct GoalStepView: View {
    @ObservedObject var viewModel: ProgramWizardViewModel

    private let goals: [(id: String, label: String, icon: String)] = [
        ("strength", "Strength", "dumbbell.fill"),
        ("hypertrophy", "Hypertrophy", "flame.fill"),
        ("fat_loss", "Fat Loss", "scalemass.fill"),
        ("endurance", "Endurance", "heart.fill"),
        ("general_fitness", "General Fitness", "figure.run")
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("What's your primary goal?")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("Choose the goal that best describes what you want to achieve.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, Theme.Spacing.sm)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(goals, id: \.id) { goal in
                    GoalButton(
                        id: goal.id,
                        label: goal.label,
                        icon: goal.icon,
                        isSelected: viewModel.goal == goal.id
                    ) {
                        viewModel.goal = goal.id
                    }
                }
            }
        }
    }
}

private struct GoalButton: View {
    let id: String
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : Theme.Colors.accentBlue)
                    .frame(width: 36)

                Text(label)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.accentBlue : Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(isSelected ? Theme.Colors.accentBlue : Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
        .buttonStyle(.plain)
    }
}
