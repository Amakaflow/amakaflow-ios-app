//
//  ScheduleStepView.swift
//  AmakaFlow
//
//  Wizard step 3: Choose schedule preferences (AMA-1413)
//

import SwiftUI

struct ScheduleStepView: View {
    @ObservedObject var viewModel: ProgramWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Set your schedule")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Tell us how often you can train and for how long.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            // Duration slider
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Program Duration")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Text("\(Int(viewModel.durationWeeks)) weeks")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.accentBlue)
                }

                Slider(value: $viewModel.durationWeeks, in: 4...52, step: 1)
                    .tint(Theme.Colors.accentBlue)

                HStack {
                    Text("4 wks")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    Text("52 wks")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)

            // Sessions per week slider
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Sessions per Week")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Text("\(Int(viewModel.sessionsPerWeek))x")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.accentBlue)
                }

                Slider(value: $viewModel.sessionsPerWeek, in: 1...7, step: 1)
                    .tint(Theme.Colors.accentBlue)

                HStack {
                    Text("1x")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    Text("7x")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)

            // Preferred days
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Preferred Days")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(0..<7, id: \.self) { day in
                        DayToggleButton(
                            label: ProgramWizardViewModel.dayNames[day],
                            isSelected: viewModel.preferredDays.contains(day)
                        ) {
                            if viewModel.preferredDays.contains(day) {
                                viewModel.preferredDays.remove(day)
                            } else {
                                viewModel.preferredDays.insert(day)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)

            // Time per session
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Time per Session")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(ProgramWizardViewModel.timeOptions, id: \.self) { minutes in
                        TimeOptionButton(
                            label: "\(minutes) min",
                            isSelected: viewModel.timePerSession == minutes
                        ) {
                            viewModel.timePerSession = minutes
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)
        }
    }
}

private struct DayToggleButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(isSelected ? Theme.Colors.accentBlue : Theme.Colors.surfaceElevated)
                .cornerRadius(Theme.CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }
}

private struct TimeOptionButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Colors.accentBlue : Theme.Colors.surfaceElevated)
                .cornerRadius(Theme.CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }
}
