//
//  ReviewStepView.swift
//  AmakaFlow
//
//  Wizard step 6: Review and generate program (AMA-1413)
//

import SwiftUI

struct ReviewStepView: View {
    @ObservedObject var viewModel: ProgramWizardViewModel
    var onViewProgram: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Review your program")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            if viewModel.isGenerating {
                generatingView
            } else if let programId = viewModel.generatedProgramId {
                successView(programId: programId)
            } else {
                summaryView
            }
        }
    }

    // MARK: - Summary

    private var summaryView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ReviewCard(title: "Goal") {
                viewModel.goal.map { goalLabel($0) } ?? "Not set"
            } onEdit: {
                viewModel.goToStep(.goal)
            }

            ReviewCard(title: "Experience") {
                viewModel.experienceLevel.map { $0.capitalized } ?? "Not set"
            } onEdit: {
                viewModel.goToStep(.experience)
            }

            ReviewCard(title: "Schedule") {
                "\(Int(viewModel.durationWeeks)) weeks · \(Int(viewModel.sessionsPerWeek))x/week · \(viewModel.timePerSession) min"
            } onEdit: {
                viewModel.goToStep(.schedule)
            }

            ReviewCard(title: "Equipment") {
                if viewModel.useCustomEquipment {
                    viewModel.customEquipment.isEmpty ? "None selected" : "\(viewModel.customEquipment.count) items"
                } else {
                    viewModel.equipmentPreset.flatMap { preset in
                        ProgramWizardViewModel.equipmentPresets.first(where: { $0.id == preset })?.name
                    } ?? "Not set"
                }
            } onEdit: {
                viewModel.goToStep(.equipment)
            }

            if !viewModel.injuries.isEmpty || !viewModel.focusAreas.isEmpty || !viewModel.avoidExercises.isEmpty {
                ReviewCard(title: "Preferences") {
                    var parts: [String] = []
                    if !viewModel.injuries.isEmpty { parts.append("Injuries noted") }
                    if !viewModel.focusAreas.isEmpty { parts.append("\(viewModel.focusAreas.count) focus areas") }
                    if !viewModel.avoidExercises.isEmpty { parts.append("\(viewModel.avoidExercises.count) exercises avoided") }
                    return parts.joined(separator: " · ")
                } onEdit: {
                    viewModel.goToStep(.preferences)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentRed)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.sm)
            }
        }
    }

    // MARK: - Generating

    private var generatingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.surfaceElevated, lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.generationProgress) / 100.0)
                    .stroke(Theme.Colors.accentBlue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: viewModel.generationProgress)

                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.Colors.accentBlue)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Generating your program...")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("\(viewModel.generationProgress)% complete")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Button {
                viewModel.cancelGeneration()
            } label: {
                Text("Cancel")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.accentRed)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - Success

    private func successView(programId: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentGreen.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(Theme.Colors.accentGreen)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Program Created!")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Your personalised training program is ready to go.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onViewProgram?(programId)
            } label: {
                Text("View Program")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - Helpers

    private func goalLabel(_ id: String) -> String {
        switch id {
        case "strength": return "Strength"
        case "hypertrophy": return "Hypertrophy"
        case "fat_loss": return "Fat Loss"
        case "endurance": return "Endurance"
        case "general_fitness": return "General Fitness"
        default: return id.capitalized
        }
    }
}

// MARK: - Review Card

private struct ReviewCard: View {
    let title: String
    let value: () -> String
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textSecondary)

                Text(value())
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Spacer()

            Button("Edit", action: onEdit)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.accentBlue)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }
}
