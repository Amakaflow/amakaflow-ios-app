//
//  ProgramDetailView.swift
//  AmakaFlow
//
//  Detail view for a Training Program with weeks and workouts (AMA-1231)
//

import SwiftUI

/// Simple flow layout that wraps items to multiple lines
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeight: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxHeight = currentY + lineHeight
        }

        return CGSize(width: containerWidth, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}


struct ProgramDetailView: View {
    let programId: String
    let programName: String

    @StateObject private var viewModel = ProgramsViewModel()
    @State private var expandedWeeks: Set<String> = []

    var body: some View {
        Group {
            if viewModel.isLoadingDetail && viewModel.selectedProgram == nil {
                loadingState
            } else if let program = viewModel.selectedProgram {
                programContent(program)
            } else if let error = viewModel.errorMessage {
                errorState(error)
            } else {
                loadingState
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle(programName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadProgramDetail(id: programId)
            // Auto-expand first week
            if let firstWeek = viewModel.selectedProgram?.weeks?.first {
                expandedWeeks.insert(firstWeek.id)
            }
        }
    }

    // MARK: - Program Content

    private func programContent(_ program: TrainingProgram) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Header card
                programHeader(program)

                // Weeks breakdown
                if let weeks = program.weeks, !weeks.isEmpty {
                    weeksSection(weeks)
                } else {
                    noWeeksState
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Program Header

    private func programHeader(_ program: TrainingProgram) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Title and status
            HStack(alignment: .top) {
                Text(program.name)
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Text(program.statusDisplayName)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(statusColor(program.status))
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(statusColor(program.status).opacity(0.15))
                    .cornerRadius(Theme.CornerRadius.sm)
            }

            // Description
            if let description = program.description {
                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            // Stats grid
            HStack(spacing: Theme.Spacing.md) {
                ProgramStat(label: "Goal", value: program.goalDisplayName)
                ProgramStat(label: "Level", value: program.experienceLevelDisplayName)
                ProgramStat(label: "Duration", value: "\(program.durationWeeks) weeks")
                ProgramStat(label: "Frequency", value: "\(program.sessionsPerWeek)x/wk")
            }

            // Equipment
            if let equipment = program.equipmentAvailable, !equipment.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Equipment")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)

                    FlowLayout(spacing: Theme.Spacing.xs) {
                        ForEach(equipment, id: \.self) { item in
                            Text(item.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.surfaceElevated)
                                .cornerRadius(Theme.CornerRadius.sm)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    // MARK: - Weeks Section

    private func weeksSection(_ weeks: [ProgramWeek]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("PROGRAM SCHEDULE")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)

            ForEach(weeks.sorted(by: { $0.weekNumber < $1.weekNumber })) { week in
                weekCard(week)
            }
        }
    }

    private func weekCard(_ week: ProgramWeek) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Week header (tappable)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedWeeks.contains(week.id) {
                        expandedWeeks.remove(week.id)
                    } else {
                        expandedWeeks.insert(week.id)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("Week \(week.weekNumber)")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)

                            if week.isDeload {
                                Text("Deload")
                                    .font(Theme.Typography.footnote)
                                    .foregroundColor(Theme.Colors.accentOrange)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .padding(.vertical, 2)
                                    .background(Theme.Colors.accentOrange.opacity(0.15))
                                    .cornerRadius(Theme.CornerRadius.sm)
                            }
                        }

                        if let focus = week.focus {
                            Text(focus)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    // Workout count
                    if let workouts = week.workouts {
                        let completed = workouts.filter { $0.isCompleted == true }.count
                        Text("\(completed)/\(workouts.count)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Image(systemName: expandedWeeks.contains(week.id) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.md)
            }
            .buttonStyle(.plain)

            // Expanded workouts
            if expandedWeeks.contains(week.id), let workouts = week.workouts {
                Divider()
                    .background(Theme.Colors.borderLight)

                VStack(spacing: 0) {
                    ForEach(workouts.sorted(by: { $0.dayOfWeek < $1.dayOfWeek })) { workout in
                        workoutRow(workout)

                        if workout.id != workouts.sorted(by: { $0.dayOfWeek < $1.dayOfWeek }).last?.id {
                            Divider()
                                .background(Theme.Colors.borderLight)
                                .padding(.leading, Theme.Spacing.md)
                        }
                    }
                }
            }
        }
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    // MARK: - Workout Row

    private func workoutRow(_ workout: ProgramWorkout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                // Completion indicator
                Image(systemName: workout.isCompleted == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(workout.isCompleted == true ? Theme.Colors.accentGreen : Theme.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    HStack(spacing: Theme.Spacing.sm) {
                        Text(workout.dayName)
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)

                        if let duration = workout.targetDurationMinutes {
                            Text("\(duration) min")
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }

                Spacer()
            }

            // Exercises list
            if let exercises = workout.exercises, !exercises.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(exercises) { exercise in
                        exerciseRow(exercise)
                    }
                }
                .padding(.leading, 28) // Align with workout name
            }

            // Notes
            if let notes = workout.notes, !notes.isEmpty {
                Text(notes)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .italic()
                    .padding(.leading, 28)
            }
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Exercise Row

    private func exerciseRow(_ exercise: ProgramExercise) -> some View {
        HStack {
            Text(exercise.name)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: Theme.Spacing.sm) {
                Text(exercise.setsRepsDisplay)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.accentBlue)

                if let weight = exercise.weight, weight > 0 {
                    Text("\(Int(weight))kg")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                if let rpe = exercise.rpe {
                    Text("RPE \(rpe)")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.accentOrange)
                }
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Theme.Colors.accentBlue)

            Text("Loading program...")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(Theme.Colors.accentOrange)

            Text("Failed to load program")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.loadProgramDetail(id: programId)
                }
            } label: {
                Text("Try Again")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noWeeksState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(Theme.Colors.textSecondary)

            Text("No weeks configured yet")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return Theme.Colors.accentGreen
        case "completed": return Theme.Colors.accentBlue
        case "draft": return Theme.Colors.textSecondary
        case "archived": return Theme.Colors.textTertiary
        default: return Theme.Colors.textSecondary
        }
    }
}

// MARK: - Program Stat

private struct ProgramStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)

            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProgramDetailView(programId: "preview-id", programName: "Preview Program")
    }
    .preferredColorScheme(.dark)
}
