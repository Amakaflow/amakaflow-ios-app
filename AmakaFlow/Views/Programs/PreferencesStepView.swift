//
//  PreferencesStepView.swift
//  AmakaFlow
//
//  Wizard step 5: Injuries, focus areas, exercises to avoid (AMA-1413)
//

import SwiftUI

struct PreferencesStepView: View {
    @ObservedObject var viewModel: ProgramWizardViewModel
    @State private var avoidExerciseInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Any special preferences?")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("All fields are optional. This helps us personalise your program.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            // Injuries / limitations
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Injuries or Limitations")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                TextField("e.g. lower back pain, bad left knee", text: $viewModel.injuries, axis: .vertical)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(3, reservesSpace: true)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surfaceElevated)
                    .cornerRadius(Theme.CornerRadius.sm)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)

            // Focus areas
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Focus Areas (optional)")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Select muscle groups you want to prioritise.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                FlowLayout(spacing: Theme.Spacing.sm) {
                    ForEach(ProgramWizardViewModel.muscleGroups, id: \.self) { muscle in
                        MuscleChip(
                            label: muscle.capitalized,
                            isSelected: viewModel.focusAreas.contains(muscle)
                        ) {
                            if viewModel.focusAreas.contains(muscle) {
                                viewModel.focusAreas.remove(muscle)
                            } else {
                                viewModel.focusAreas.insert(muscle)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)

            // Exercises to avoid
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Exercises to Avoid (optional)")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(spacing: Theme.Spacing.sm) {
                    TextField("e.g. barbell squat", text: $avoidExerciseInput)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.surfaceElevated)
                        .cornerRadius(Theme.CornerRadius.sm)

                    Button {
                        addAvoidExercise()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(avoidExerciseInput.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.accentBlue)
                    }
                    .disabled(avoidExerciseInput.isEmpty)
                }

                if !viewModel.avoidExercises.isEmpty {
                    FlowLayout(spacing: Theme.Spacing.sm) {
                        ForEach(viewModel.avoidExercises, id: \.self) { exercise in
                            AvoidTag(label: exercise) {
                                viewModel.avoidExercises.removeAll { $0 == exercise }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)
        }
    }

    private func addAvoidExercise() {
        let trimmed = avoidExerciseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !viewModel.avoidExercises.contains(trimmed) else { return }
        viewModel.avoidExercises.append(trimmed)
        avoidExerciseInput = ""
    }
}

private struct MuscleChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(isSelected ? Theme.Colors.accentBlue : Theme.Colors.surfaceElevated)
                .cornerRadius(Theme.CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }
}

private struct AvoidTag: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surfaceElevated)
        .cornerRadius(Theme.CornerRadius.sm)
    }
}
