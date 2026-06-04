//
//  ReviewStepView.swift
//  AmakaFlow
//
//  Wizard step 6: Review, generate, and save program (AMA-1413 / AMA-2096)
//

import SwiftUI

struct ReviewStepView: View {
    @ObservedObject var viewModel: ProgramWizardViewModel
    var onViewProgram: ((String) -> Void)?

    @State private var scheduleStartDate = Date.nextMonday

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            if viewModel.isGenerating || viewModel.isSaving {
                generatingView
            } else if let programId = viewModel.generatedProgramId {
                successView(programId: programId)
            } else if let program = viewModel.proposedProgram {
                proposedProgramView(program)
            } else {
                summaryView
            }
        }
    }

    private var title: String {
        if viewModel.generatedProgramId != nil { return "Program saved" }
        if viewModel.proposedProgram != nil { return "Review your plan" }
        return "Review your program"
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

            errorMessageView
        }
    }

    // MARK: - Proposed Program

    private func proposedProgramView(_ program: ProposedProgram) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(program.name)
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(spacing: Theme.Spacing.sm) {
                    if let goal = program.goalDisplayName {
                        ProposalMetaChip(icon: "target", text: goal)
                    }
                    if let duration = program.durationWeeks {
                        ProposalMetaChip(icon: "calendar", text: "\(duration) weeks")
                    }
                    if let sessions = program.sessionsPerWeek {
                        ProposalMetaChip(icon: "figure.strengthtraining.traditional", text: "\(sessions)x/week")
                    }
                }

                if let model = program.periodizationModel {
                    Text("Periodization: \(model.replacingOccurrences(of: "_", with: " ").capitalized)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.lg)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Schedule start date")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                DatePicker("Start date", selection: $scheduleStartDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("program_wizard_schedule_start_date")
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.lg)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Weeks")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(program.weeks) { week in
                    ProposedWeekCard(week: week)
                }
            }

            errorMessageView

            Button {
                Task { await viewModel.saveProgram(startDate: scheduleStartDate) }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "calendar.badge.checkmark")
                    Text("Save & schedule")
                }
                .font(Theme.Typography.bodyBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accentBlue)
                .cornerRadius(Theme.CornerRadius.md)
            }
            .accessibilityIdentifier("program_wizard_save_schedule")
        }
    }

    // MARK: - Generating / Saving

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

                Image(systemName: viewModel.isSaving ? "tray.and.arrow.down.fill" : "sparkles")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.Colors.accentBlue)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text(viewModel.isSaving ? "Saving your program..." : "Generating your program...")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                if let stageMessage = viewModel.stageMessage {
                    Text(stageMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

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

                let scheduledText = viewModel.scheduledCount > 0 ? " Scheduled \(viewModel.scheduledCount) sessions." : ""
                Text("Your personalised training program is saved.\(scheduledText)")
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

    private var errorMessageView: some View {
        Group {
            if let error = viewModel.errorMessage {
                Text(viewModel.isErrorRecoverable ? "\(error) You can try again." : error)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentRed)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity)
            }
        }
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

// MARK: - Proposed Program Cards

private struct ProposedWeekCard: View {
    let week: ProposedProgramWeek

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(week.weekNumber)")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                if week.isDeload == true {
                    Text("Deload")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentOrange)
                }
                Spacer()
                if let intensity = week.intensityPercentage {
                    Text("\(intensity)%")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            if let focus = week.focus {
                Text(focus)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            ForEach(week.workouts) { workout in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(workout.name)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        if let dayName = workout.dayName {
                            Text(dayName)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    let exerciseNames = workout.exercises.prefix(3).map(\.name).joined(separator: " · ")
                    if !exerciseNames.isEmpty {
                        Text(exerciseNames + (workout.exercises.count > 3 ? " · +\(workout.exercises.count - 3)" : ""))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
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

private struct ProposalMetaChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .background(Theme.Colors.surfaceElevated)
            .cornerRadius(Theme.CornerRadius.sm)
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

private extension Date {
    static var nextMonday: Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: start) // Sunday = 1
        let daysUntilMonday = (9 - weekday) % 7
        let offset = daysUntilMonday == 0 ? 7 : daysUntilMonday
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }
}
