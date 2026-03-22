//
//  CalendarView.swift
//  AmakaFlow
//
//  Calendar screen with week strip and upcoming workouts
//

import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @StateObject private var calendarVM = CalendarViewModel()
    @State private var currentDate = Date()
    @State private var selectedDate: Date?
    @State private var selectedWorkout: Workout?
    @State private var showingMonthPicker = false
    @State private var showingGenerateWeek = false

    let onAddWorkout: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month navigation
                monthNavigation
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)

                // Week strip
                weekStrip
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.lg)

                // Generate Week button (AMA-1147)
                generateWeekButton
                    .padding(.horizontal, Theme.Spacing.lg)

                // Proposed plan or upcoming workouts
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        // Show proposed plan if generated (AMA-1133)
                        if let plan = calendarVM.proposedPlan {
                            proposedPlanSection(plan)
                        }

                        // Day-state session cards for the selected week (AMA-1133)
                        if !calendarVM.dayStates.isEmpty {
                            dayStateSessionCards
                        }

                        // Conflict warnings (AMA-1133)
                        if !calendarVM.conflicts.isEmpty {
                            conflictWarningsSection
                        }

                        Text("Upcoming Workouts")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)

                        if upcomingWorkouts.isEmpty && calendarVM.proposedPlan == nil {
                            emptyState
                        } else {
                            ForEach(upcomingWorkouts) { workout in
                                CalendarWorkoutRow(workout: workout) {
                                    selectedWorkout = workout
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, 100)
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Theme.Spacing.sm) {
                        // Month picker button
                        Button {
                            showingMonthPicker = true
                        } label: {
                            Image(systemName: "calendar")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .frame(width: 36, height: 36)
                                .background(Theme.Colors.surface)
                                .cornerRadius(Theme.CornerRadius.md)
                        }
                        .buttonStyle(.plain)

                        // Add button - navigates to Workouts to select workout
                        Button {
                            onAddWorkout()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Theme.Colors.accentBlue)
                                .cornerRadius(Theme.CornerRadius.md)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingMonthPicker) {
                FullMonthPickerView(
                    selectedDate: currentDate,
                    onSelectDate: { date in
                        currentDate = date
                        showingMonthPicker = false
                    },
                    onCancel: {
                        showingMonthPicker = false
                    }
                )
            }
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
            .sheet(isPresented: showingDayDetail) {
                if let date = selectedDate {
                    dayDetailSheet(for: date)
                }
            }
            .task {
                await loadCalendarData()
            }
            .onChange(of: currentDate) { _ in
                Task { await loadCalendarData() }
            }
        }
    }

    /// Load day states and conflicts for the current week range
    private func loadCalendarData() async {
        guard let start = weekDates.first, let end = weekDates.last else { return }
        await calendarVM.loadDayStates(from: start, to: end)
        await calendarVM.detectConflicts(from: start, to: end)
    }

    // MARK: - Month Navigation

    private var monthNavigation: some View {
        HStack {
            Button {
                goToPreviousWeek()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.md)
            }

            Spacer()

            Text(monthYearString)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            Button {
                goToNextWeek()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.md)
            }
        }
    }

    // MARK: - Week Strip

    private var weekStrip: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(weekDates, id: \.self) { date in
                weekDayCell(for: date)
            }
        }
    }

    private func weekDayCell(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let workoutsForDay = workouts(for: date)
        let readiness = calendarVM.readiness(for: date)
        let hasConflict = calendarVM.hasConflict(on: date)

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Text(dayName(for: date))
                    .font(Theme.Typography.footnote)
                    .foregroundColor(isToday ? .white : Theme.Colors.textSecondary)

                Text("\(calendar.component(.day, from: date))")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(isToday ? .white : Theme.Colors.textPrimary)

                // Readiness pill (AMA-1147)
                if let readiness = readiness {
                    readinessPill(readiness, isToday: isToday)
                }

                // Workout dots + conflict indicator
                HStack(spacing: 2) {
                    if hasConflict {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(isToday ? .white : Theme.Colors.accentOrange)
                    }
                    if !workoutsForDay.isEmpty {
                        ForEach(workoutsForDay.prefix(3)) { workout in
                            Circle()
                                .fill(isToday ? .white : sportColor(for: workout.sport))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .frame(height: 8)
            }
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(isToday ? Theme.Colors.accentBlue : Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.lg)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Readiness Pill (AMA-1147)

    private func readinessPill(_ level: ReadinessLevel, isToday: Bool) -> some View {
        Text(readinessLabel(level))
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(isToday ? .white : readinessColor(level))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                (isToday ? Color.white.opacity(0.25) : readinessColor(level).opacity(0.15))
            )
            .cornerRadius(4)
    }

    private func readinessLabel(_ level: ReadinessLevel) -> String {
        switch level {
        case .green: return "Ready"
        case .yellow: return "Moderate"
        case .red: return "Fatigued"
        case .rest: return "Rest"
        case .unknown: return ""
        }
    }

    private func readinessColor(_ level: ReadinessLevel) -> Color {
        switch level {
        case .green: return Theme.Colors.accentGreen
        case .yellow: return Theme.Colors.accentOrange
        case .red: return Theme.Colors.accentRed
        case .rest: return Theme.Colors.accentBlue
        case .unknown: return Theme.Colors.textTertiary
        }
    }

    // MARK: - Generate Week Button (AMA-1147)

    private var generateWeekButton: some View {
        Button {
            Task { await calendarVM.generateWeek() }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if calendarVM.isGeneratingWeek {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .medium))
                }
                Text("Generate My Week")
                    .font(Theme.Typography.captionBold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.accentBlue)
            .cornerRadius(Theme.CornerRadius.md)
        }
        .disabled(calendarVM.isGeneratingWeek)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Proposed Plan Section (AMA-1133)

    private func proposedPlanSection(_ plan: ProposedPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(Theme.Colors.accentBlue)
                Text("Proposed Week Plan")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                if let score = plan.totalLoadScore {
                    Text("Load: \(Int(score))")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.accentOrange)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.accentOrange.opacity(0.15))
                        .cornerRadius(Theme.CornerRadius.sm)
                }
            }

            if let rationale = plan.rationale {
                Text(rationale)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.md)
            }

            ForEach(plan.days) { day in
                ProposedDayCard(day: day)
            }
        }
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Day State Session Cards (AMA-1133)

    private var dayStateSessionCards: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("This Week")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(weekDates, id: \.self) { date in
                let formatter = ISO8601DateFormatter()
                let _ = formatter.formatOptions = [.withFullDate]
                let key = formatter.string(from: date)

                if let dayState = calendarVM.dayStates[key] {
                    DayStateCard(dayState: dayState, date: date)
                }
            }
        }
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Conflict Warnings (AMA-1133)

    private var conflictWarningsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.Colors.accentOrange)
                Text("Conflicts Detected")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            ForEach(calendarVM.conflicts) { conflict in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Circle()
                        .fill(conflictSeverityColor(conflict.severity))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(conflict.description)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textPrimary)

                        if let suggestion = conflict.suggestion {
                            Text(suggestion)
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.accentBlue)
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.sm)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accentOrange.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.accentOrange.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
        .padding(.bottom, Theme.Spacing.md)
    }

    private func conflictSeverityColor(_ severity: ConflictSeverity) -> Color {
        switch severity {
        case .low: return Theme.Colors.accentOrange
        case .medium: return Theme.Colors.accentOrange
        case .high: return Theme.Colors.accentRed
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("No scheduled workouts")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    // MARK: - Day Detail Sheet

    private var showingDayDetail: Binding<Bool> {
        Binding(
            get: { selectedDate != nil },
            set: { if !$0 { selectedDate = nil } }
        )
    }

    private func dayDetailSheet(for date: Date) -> some View {
        let workoutsForDay = workouts(for: date)

        return NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if workoutsForDay.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Text("No workouts scheduled for this day")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)

                        Button {
                            selectedDate = nil
                            onAddWorkout()
                        } label: {
                            Text("Add Workout")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.Spacing.lg)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(Theme.Colors.accentBlue)
                                .cornerRadius(Theme.CornerRadius.md)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xl)
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(workoutsForDay) { workout in
                                CalendarWorkoutRow(workout: workout) {
                                    selectedDate = nil
                                    selectedWorkout = workout
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.surface.ignoresSafeArea())
            .navigationTitle(dateString(for: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        selectedDate = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var weekDates: [Date] {
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate)
        )!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private var monthYearString: String {
        currentDate.formatted(.dateTime.month(.wide).year())
    }

    private func dayName(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func dateString(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func goToPreviousWeek() {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentDate) {
            currentDate = newDate
        }
    }

    private func goToNextWeek() {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate) {
            currentDate = newDate
        }
    }

    private func workouts(for date: Date) -> [Workout] {
        // For now, return all workouts as we don't have scheduling yet
        // In a real app, filter by scheduled date
        viewModel.incomingWorkouts
    }

    private var upcomingWorkouts: [Workout] {
        viewModel.incomingWorkouts
    }

    private func sportColor(for sport: WorkoutSport) -> Color {
        switch sport {
        case .running: return Theme.Colors.accentGreen
        case .strength: return Theme.Colors.accentBlue
        case .mobility: return Color(hex: "9333EA")
        default: return Theme.Colors.accentBlue
        }
    }
}

// MARK: - Proposed Day Card (AMA-1133)

private struct ProposedDayCard: View {
    let day: ProposedDay

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(day.date)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                if day.isRestDay {
                    Text("Rest Day")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.accentBlue)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.accentBlue.opacity(0.15))
                        .cornerRadius(Theme.CornerRadius.sm)
                }
            }

            if !day.isRestDay {
                ForEach(day.workouts) { workout in
                    HStack(spacing: Theme.Spacing.sm) {
                        Circle()
                            .fill(sportColor(workout.sport))
                            .frame(width: 8, height: 8)

                        Text(workout.name)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Spacer()

                        if let mins = workout.estimatedDurationMinutes {
                            Text("\(mins)m")
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        if let priority = workout.priority {
                            Text(priority.rawValue.capitalized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(priorityColor(priority))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(priorityColor(priority).opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            if let rationale = day.rationale {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.accentBlue)
                    Text(rationale)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.top, Theme.Spacing.xs)
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

    private func sportColor(_ sport: String) -> Color {
        switch sport.lowercased() {
        case "running": return Theme.Colors.accentGreen
        case "strength": return Theme.Colors.accentBlue
        case "mobility": return Color(hex: "9333EA")
        default: return Theme.Colors.accentBlue
        }
    }

    private func priorityColor(_ priority: WorkoutPriority) -> Color {
        switch priority {
        case .key: return Theme.Colors.accentRed
        case .normal: return Theme.Colors.accentBlue
        case .optional: return Theme.Colors.textSecondary
        }
    }
}

// MARK: - Day State Card (AMA-1133)

private struct DayStateCard: View {
    let dayState: DayState
    let date: Date

    private let cal = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(cal.isDateInToday(date) ? Theme.Colors.accentBlue : Theme.Colors.textPrimary)

                Spacer()

                // Readiness pill
                readinessPill(dayState.readiness)

                // Fatigue score
                if let fatigue = dayState.fatigueScore {
                    Text("Fatigue: \(Int(fatigue))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            // Planned workouts
            if !dayState.plannedWorkouts.isEmpty {
                ForEach(dayState.plannedWorkouts) { workout in
                    HStack(spacing: Theme.Spacing.sm) {
                        Circle()
                            .fill(sportColor(workout.sport))
                            .frame(width: 6, height: 6)

                        Text(workout.name)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        if let time = workout.scheduledTime {
                            Text(time)
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                }
            }

            // Completed indicators
            if !dayState.completedWorkouts.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.accentGreen)
                    Text("\(dayState.completedWorkouts.count) completed")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.accentGreen)
                }
            }

            // Notes
            if let notes = dayState.notes {
                Text(notes)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .italic()
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.sm)
    }

    private func readinessPill(_ level: ReadinessLevel) -> some View {
        Text(readinessLabel(level))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(readinessColor(level))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(readinessColor(level).opacity(0.15))
            .cornerRadius(4)
    }

    private func readinessLabel(_ level: ReadinessLevel) -> String {
        switch level {
        case .green: return "Ready"
        case .yellow: return "Moderate"
        case .red: return "Fatigued"
        case .rest: return "Rest"
        case .unknown: return "Unknown"
        }
    }

    private func readinessColor(_ level: ReadinessLevel) -> Color {
        switch level {
        case .green: return Theme.Colors.accentGreen
        case .yellow: return Theme.Colors.accentOrange
        case .red: return Theme.Colors.accentRed
        case .rest: return Theme.Colors.accentBlue
        case .unknown: return Theme.Colors.textTertiary
        }
    }

    private func sportColor(_ sport: String) -> Color {
        switch sport.lowercased() {
        case "running": return Theme.Colors.accentGreen
        case "strength": return Theme.Colors.accentBlue
        case "mobility": return Color(hex: "9333EA")
        default: return Theme.Colors.accentBlue
        }
    }
}

// MARK: - Calendar Workout Row

private struct CalendarWorkoutRow: View {
    let workout: Workout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                // Date & Time
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Today")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)

                    Text("9:00")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                .frame(width: 60)

                // Divider
                Rectangle()
                    .fill(Theme.Colors.borderLight)
                    .frame(width: 1)

                // Workout Info
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Circle()
                            .fill(sportColor)
                            .frame(width: 8, height: 8)

                        Text(workout.name)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                    }

                    Text(workout.formattedDuration)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    HStack(spacing: Theme.Spacing.sm) {
                        Text(workout.sport.rawValue.capitalized)
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.surfaceElevated)
                            .cornerRadius(Theme.CornerRadius.sm)

                        Text("Synced")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.accentGreen)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.accentGreen.opacity(0.1))
                            .cornerRadius(Theme.CornerRadius.sm)
                    }
                }

                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.lg)
        }
        .buttonStyle(.plain)
    }

    private var sportColor: Color {
        switch workout.sport {
        case .running: return Theme.Colors.accentGreen
        case .strength: return Theme.Colors.accentBlue
        case .mobility: return Color(hex: "9333EA")
        default: return Theme.Colors.accentBlue
        }
    }
}

// MARK: - Full Month Picker View

private struct FullMonthPickerView: View {
    let selectedDate: Date
    let onSelectDate: (Date) -> Void
    let onCancel: () -> Void

    @State private var viewDate: Date
    private let calendar = Calendar.current

    init(selectedDate: Date, onSelectDate: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.selectedDate = selectedDate
        self.onSelectDate = onSelectDate
        self.onCancel = onCancel
        self._viewDate = State(initialValue: selectedDate)
    }

    // Generate months: 3 months back, 12 months forward
    private var months: [Date] {
        let current = Date()
        return (-3..<12).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: current)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.lg) {
                        ForEach(months, id: \.self) { month in
                            MonthGridView(
                                month: month,
                                selectedDate: selectedDate,
                                onSelectDate: onSelectDate
                            )
                            .id(month)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                }
                .onAppear {
                    // Scroll to current month
                    if let currentMonth = months.first(where: { calendar.isDate($0, equalTo: selectedDate, toGranularity: .month) }) {
                        proxy.scrollTo(currentMonth, anchor: .top)
                    }
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle(viewDate.formatted(.dateTime.month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(Theme.Colors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        onSelectDate(Date())
                    }
                    .foregroundColor(Theme.Colors.accentBlue)
                }
            }
        }
    }
}

// MARK: - Month Grid View

private struct MonthGridView: View {
    let month: Date
    let selectedDate: Date
    let onSelectDate: (Date) -> Void

    private let calendar = Calendar.current
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: month)
        }
    }

    private var firstWeekdayOffset: Int {
        guard let firstDay = daysInMonth.first else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay)
        // Convert Sunday (1) to 6, Monday (2) to 0, etc.
        return weekday == 1 ? 6 : weekday - 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Month header
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                // Empty cells for offset
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Color.clear
                        .frame(height: 40)
                }

                // Day cells
                ForEach(daysInMonth, id: \.self) { day in
                    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                    let isToday = calendar.isDateInToday(day)

                    Button {
                        onSelectDate(day)
                    } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .font(Theme.Typography.body)
                            .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(isSelected ? Theme.Colors.accentBlue : Color.clear)
                            )
                            .overlay(
                                Circle()
                                    .stroke(isToday && !isSelected ? Theme.Colors.accentBlue : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CalendarView(onAddWorkout: {})
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}
