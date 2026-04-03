//
//  ExperienceStepView.swift
//  AmakaFlow
//
//  Wizard step 2: Choose experience level (AMA-1413)
//

import SwiftUI

struct ExperienceStepView: View {
    @ObservedObject var viewModel: ProgramWizardViewModel

    private let levels: [(id: String, label: String, description: String, icon: String)] = [
        ("beginner", "Beginner", "Less than 1 year of consistent training", "leaf.fill"),
        ("intermediate", "Intermediate", "1–3 years of consistent training", "chart.line.uptrend.xyaxis"),
        ("advanced", "Advanced", "3+ years of structured training", "trophy.fill")
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("What's your experience level?")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("Be honest — this helps us set the right intensity.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, Theme.Spacing.sm)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(levels, id: \.id) { level in
                    ExperienceButton(
                        id: level.id,
                        label: level.label,
                        description: level.description,
                        icon: level.icon,
                        isSelected: viewModel.experienceLevel == level.id
                    ) {
                        viewModel.experienceLevel = level.id
                    }
                }
            }
        }
    }
}

private struct ExperienceButton: View {
    let id: String
    let label: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .white : Theme.Colors.accentBlue)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)

                    Text(description)
                        .font(Theme.Typography.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : Theme.Colors.textSecondary)
                }

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
