//
//  WorkoutsView.swift
//  AmakaFlow
//
//  Main workouts screen with Upcoming and Incoming sections
//

import SwiftUI

struct WorkoutsView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @State private var selectedWorkout: Workout?
    @State private var showingDetail = false
    @AppStorage("workouts.selectedRange") private var selectedRange: WorkoutRange = .week
    @State private var showingCalendar = false
    @State private var monthOffset: Int = 0           // 0 = current month, -1 = prev, +1 = next
    @State private var selectedMonthDay: Date? = nil  // user-tapped day in Month view (filters Week list)
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        AFTopBar(title: selectedRange.title, subtitle: currentRangeSubtitle) {
                            EmptyView()
                        } right: {
                            Button {
                                showingCalendar = true
                            } label: {
                                Image(systemName: "calendar")
                                    .font(.system(size: 18))
                            }
                            .accessibilityLabel("Calendar")
                            .accessibilityIdentifier("workouts_calendar_button")
                        }

                        SearchBar(text: $viewModel.searchQuery)
                            .padding(.horizontal, Theme.Spacing.lg)

                        segmentedRange
                            .padding(.horizontal, Theme.Spacing.lg)

                        rangeContent
                            .padding(.horizontal, Theme.Spacing.lg)

                        #if DEBUG
                        // Add Sample Workout Button (for testing)
                        VStack(spacing: Theme.Spacing.md) {
                            Button(action: {
                                viewModel.addSampleWorkout()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                    Text("Add Sample Workout")
                                        .font(Theme.Typography.bodyBold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Theme.Colors.accentBlue)
                                .cornerRadius(Theme.CornerRadius.md)
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }
                        .padding(.bottom, Theme.Spacing.lg)
                        #endif
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingCalendar) {
                CalendarView(onAddWorkout: {
                    showingCalendar = false
                    // Route to the suggest-workout flow on Home — the closest
                    // existing surface for adding a session in MVP.
                    NotificationCenter.default.post(name: .deepLinkToWorkout, object: nil)
                })
                .environmentObject(viewModel)
            }
            .sheet(isPresented: $showingDetail) {
                if let workout = selectedWorkout {
                    WorkoutDetailView(workout: workout)
                        .environmentObject(viewModel)
                        .onAppear {
                            print("🔵 WorkoutDetailView.onAppear called!")
                        }
                } else {
                    VStack {
                        Text("ERROR: No workout selected")
                            .foregroundColor(.white)
                            .font(.title)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .onAppear {
                        print("🔵 ERROR: workout is nil in sheet!")
                    }
                }
            }
            .onChange(of: showingDetail) { oldValue, newValue in
                print("🔵 showingDetail changed: \(oldValue) → \(newValue)")
            }
            .overlay(alignment: .top) {
                // Invisible marker for Maestro E2E tests (container views
                // don't expose accessibilityIdentifier on iOS 26)
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("workouts_screen")
            }
        }
    }

    private var currentRangeSubtitle: String {
        switch selectedRange {
        case .week:
            let blockTag = viewModel.activeBlock.map { "Block \($0.index) of \($0.total)" } ?? "Current block"
            return "\(blockTag) · \(viewModel.upcomingWorkouts.count + viewModel.incomingWorkouts.count) planned"
        case .block:
            let count = blockRows.filter { $0.workout != nil }.count
            if let block = viewModel.activeBlock {
                return "\(count) session\(count == 1 ? "" : "s") in \(block.name)"
            } else {
                // No block info from API yet — fall back honestly. blockRows
                // returns all upcoming in this case; subtitle is renamed so
                // we don't fake a block count.
                return "Upcoming sessions · \(count) planned"
            }
        case .month:
            return currentMonthAnchor.formatted(.dateTime.month(.wide).year())
        }
    }

    private var segmentedRange: some View {
        HStack(spacing: 3) {
            ForEach(WorkoutRange.allCases) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.label)
                        .segmentPill(isSelected: selectedRange == range)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workouts_range_\(range.rawValue)")
            }
        }
        .padding(3)
        .background(Theme.Colors.inputBackground)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var rangeContent: some View {
        switch selectedRange {
        case .week:
            rowsList(planRows)
        case .block:
            rowsList(blockRows)
        case .month:
            monthGrid
        }
    }

    private func rowsList(_ rows: [PlanRow]) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                PlanRowView(row: row) {
                    if let workout = row.workout {
                        selectedWorkout = workout
                        showingDetail = true
                    }
                }
                .accessibilityIdentifier("workout_card_\(index)")
            }
        }
    }

    private var blockRows: [PlanRow] {
        let calendar = Calendar.current
        // AMA-1641: scope to the active block when the planner returns one.
        // Otherwise fall back to all filtered upcoming so the Block tab
        // still shows something, with the subtitle downgraded honestly in
        // currentRangeSubtitle so we don't fake a block count.
        let scheduled: [ScheduledWorkout] = viewModel.activeBlock?.scheduledWorkouts
            ?? viewModel.filteredUpcoming
        return scheduled
            .sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
            .enumerated()
            .map { index, scheduledWorkout in
                let workout = scheduledWorkout.workout
                let date = scheduledWorkout.scheduledDate ?? Date()
                return PlanRow(
                    id: "block-\(workout.id)-\(index)",
                    day: date.formatted(.dateTime.weekday(.abbreviated)),
                    date: date.formatted(.dateTime.day()),
                    type: workout.sport.rawValue.capitalized,
                    title: workout.name,
                    duration: workout.formattedDuration,
                    zone: zoneLabel(for: workout),
                    icon: icon(for: workout.sport),
                    done: false,
                    today: calendar.isDateInToday(date),
                    rest: false,
                    workout: workout
                )
            }
    }

    private var monthGrid: some View {
        let calendar = Calendar.current
        let monthStart = currentMonthAnchor
        let leadingEmpty = monthLeadingEmptyCells(for: monthStart, calendar: calendar)
        let days = currentMonthDates
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        return VStack(spacing: 8) {
            // Month nav (prev / current / next)
            HStack {
                Button { shiftMonth(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("Previous month")
                .accessibilityIdentifier("workouts_month_prev")

                Spacer()

                Text(monthStart.formatted(.dateTime.month(.wide).year()))
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button { shiftMonth(by: 1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("Next month")
                .accessibilityIdentifier("workouts_month_next")
            }
            .foregroundColor(Theme.Colors.textSecondary)

            // Weekday header (Sun..Sat for default US locale; locale-aware)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(monthWeekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid with leading empty cells so day-1 lands under correct weekday
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<leadingEmpty, id: \.self) { _ in
                    Color.clear.frame(minHeight: 44)
                }
                ForEach(days, id: \.self) { date in
                    let hasWorkout = viewModel.filteredUpcoming.contains { workout in
                        guard let scheduledDate = workout.scheduledDate else { return false }
                        return calendar.isDate(scheduledDate, inSameDayAs: date)
                    }
                    Button {
                        // Filter Week list to this day, then jump to Week.
                        // selectedMonthDay is exposed for downstream filtering;
                        // tapping again on a different day re-applies.
                        selectedMonthDay = date
                        selectedRange = .week
                    } label: {
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.day()))
                                .font(Theme.Typography.captionBold)
                            Circle()
                                .fill(hasWorkout ? Theme.Colors.accentBlue : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                        .foregroundColor(calendar.isDateInToday(date) ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(calendar.isDateInToday(date) ? Theme.Colors.surface : Theme.Colors.accentBackground.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workouts_month_day_\(calendar.component(.day, from: date))")
                }
            }
        }
        .accessibilityIdentifier("workouts_month_grid")
    }

    fileprivate var monthWeekdaySymbols: [String] {
        MonthGridLayout.weekdaySymbols(calendar: .current)
    }

    fileprivate var currentMonthAnchor: Date {
        MonthGridLayout.monthAnchor(offset: monthOffset)
    }

    fileprivate func monthLeadingEmptyCells(for monthStart: Date, calendar: Calendar) -> Int {
        MonthGridLayout.leadingEmptyCells(for: monthStart, calendar: calendar)
    }

    fileprivate func shiftMonth(by delta: Int) {
        monthOffset += delta
    }

    fileprivate func zoneLabel(for workout: Workout) -> String {
        // Prefer real intensity from the plan; fall back to "—" rather than
        // a fabricated zone. AMA-1641: previously hard-coded "Z3–4"/"Ready".
        // Workout currently has no top-level intensity field — derive from
        // the first non-nil interval target as a best-effort label.
        for interval in workout.intervals {
            switch interval {
            case .time(_, let target?), .warmup(_, let target?), .cooldown(_, let target?), .distance(_, let target?):
                if !target.isEmpty { return target }
            default:
                continue
            }
        }
        return "—"
    }

    private var planRows: [PlanRow] {
        let scheduled = viewModel.filteredUpcoming
        let weekDates = currentWeekDates
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        // Build one row per day using only real ScheduledWorkout data.
        // Days with no scheduled workout show an empty-state row — no fabricated sessions.
        return weekDates.map { date in
            let dayStart = calendar.startOfDay(for: date)
            let isToday = calendar.isDate(dayStart, inSameDayAs: todayStart)
            let dayLabel = date.formatted(.dateTime.weekday(.abbreviated))
            let dateLabel = date.formatted(.dateTime.day())

            if let scheduledWorkout = scheduled.first(where: {
                guard let d = $0.scheduledDate else { return false }
                return calendar.isDate(calendar.startOfDay(for: d), inSameDayAs: dayStart)
            }) {
                let workout = scheduledWorkout.workout
                return PlanRow(
                    id: "workout-\(workout.id)-\(isoDayString(date))",
                    day: dayLabel, date: dateLabel,
                    type: workout.sport.rawValue.capitalized,
                    title: workout.name,
                    duration: workout.formattedDuration,
                    zone: zoneLabel(for: workout),
                    icon: icon(for: workout.sport),
                    done: false, today: isToday, rest: false, workout: workout
                )
            } else {
                return PlanRow(
                    id: "empty-\(isoDayString(date))",
                    day: dayLabel, date: dateLabel,
                    type: "—", title: "No session",
                    duration: "—", zone: "—",
                    icon: "minus.circle", done: false,
                    today: isToday, rest: true, workout: nil
                )
            }
        }
    }

    private func icon(for sport: WorkoutSport) -> String {
        switch sport {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.yoga"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "heart.fill"
        case .other: return "flag.fill"
        }
    }

    private var currentWeekDates: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start) ?? today }
    }

    private var currentMonthDates: [Date] {
        MonthGridLayout.dates(inMonthContaining: currentMonthAnchor, calendar: .current)
    }

    private func isoDayString(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}


enum WorkoutRange: String, CaseIterable, Identifiable {
    case week
    case block
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "Week"
        case .block: return "Block"
        case .month: return "Month"
        }
    }

    var title: String {
        switch self {
        case .week: return "This week"
        case .block: return "Current block"
        case .month: return "This month"
        }
    }
}

private struct PlanRow {
    let id: String
    let day: String
    let date: String
    let type: String
    let title: String
    let duration: String
    let zone: String
    let icon: String
    let done: Bool
    let today: Bool
    let rest: Bool
    let workout: Workout?
}

private struct PlanRowView: View {
    let row: PlanRow
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    AFLabel(text: row.day)
                    Text(row.date)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                .frame(width: 38)

                RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                    .fill(Theme.Colors.accentBackground)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: row.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(row.rest ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        AFLabel(text: row.type)
                        if row.today { AFChip(text: "TODAY") }
                        if row.done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.Colors.readyHigh)
                        }
                    }

                    Text(row.title)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text("\(row.duration) · \(row.zone)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(row.today ? Theme.Colors.textPrimary : Theme.Colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .opacity(row.done ? 0.6 : 1)
        }
        .buttonStyle(.plain)
    }
}

private extension Text {
    func segmentPill(isSelected: Bool) -> some View {
        self
            .font(Theme.Typography.captionBold)
            .foregroundColor(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.Colors.surface : Color.clear)
            .clipShape(Capsule())
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.Colors.textSecondary)
                .font(.system(size: 16))
            
            TextField("Search workouts...", text: $text)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .autocorrectionDisabled()
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 12)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 64, height: 64)
                .background(Theme.Colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .cornerRadius(Theme.CornerRadius.lg)
            
            Text(title)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            
            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.xl)
    }
}

#Preview {
    WorkoutsView()
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}


