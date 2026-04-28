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
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        AFTopBar(title: "This week", subtitle: currentWeekSubtitle) {
                            EmptyView()
                        } right: {
                            Image(systemName: "calendar")
                                .font(.system(size: 18))
                        }

                        SearchBar(text: $viewModel.searchQuery)
                            .padding(.horizontal, Theme.Spacing.lg)

                        segmentedRange
                            .padding(.horizontal, Theme.Spacing.lg)

                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(planRows.enumerated()), id: \.offset) { index, row in
                                PlanRowView(row: row) {
                                    if let workout = row.workout {
                                        selectedWorkout = workout
                                        showingDetail = true
                                    }
                                }
                                .accessibilityIdentifier("workout_card_\(index)")
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)

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
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
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

    private var currentWeekSubtitle: String {
        "Block 2 of 4 · \(viewModel.upcomingWorkouts.count + viewModel.incomingWorkouts.count) planned"
    }

    private var segmentedRange: some View {
        HStack(spacing: 3) {
            Text("Week")
                .segmentPill(isSelected: true)
            Text("Block")
                .segmentPill(isSelected: false)
            Text("Month")
                .segmentPill(isSelected: false)
        }
        .padding(3)
        .background(Theme.Colors.inputBackground)
        .clipShape(Capsule())
    }

    private var planRows: [PlanRow] {
        let allWorkouts = viewModel.filteredUpcoming.map(\.workout) + viewModel.filteredIncoming
        let fallback: [PlanRow] = [
            PlanRow(day: "Mon", date: "21", type: "Strength", title: "Lower body — posterior", duration: "52m", zone: "Z2", icon: "dumbbell.fill", done: true, today: false, rest: false, workout: nil),
            PlanRow(day: "Tue", date: "22", type: "Easy run", title: "Aerobic base, 75% MAF", duration: "48m", zone: "Z2", icon: "figure.run", done: true, today: false, rest: false, workout: nil),
            PlanRow(day: "Wed", date: "23", type: "Ride", title: "Recovery spin", duration: "40m", zone: "Z1", icon: "bicycle", done: true, today: false, rest: false, workout: nil),
            PlanRow(day: "Thu", date: "24", type: "Run", title: "4×8 min @ threshold", duration: "64m", zone: "Z3–4", icon: "figure.run", done: false, today: true, rest: false, workout: allWorkouts.first),
            PlanRow(day: "Fri", date: "25", type: "Strength", title: "Upper body — pull focus", duration: "45m", zone: "Z2", icon: "dumbbell.fill", done: false, today: false, rest: false, workout: allWorkouts.dropFirst().first),
            PlanRow(day: "Sat", date: "26", type: "Ride", title: "Long endurance ride", duration: "2h 10m", zone: "Z2", icon: "bicycle", done: false, today: false, rest: false, workout: allWorkouts.dropFirst(2).first),
            PlanRow(day: "Sun", date: "27", type: "Rest", title: "Rest / mobility", duration: "20m", zone: "—", icon: "heart.fill", done: false, today: false, rest: true, workout: nil)
        ]

        guard !allWorkouts.isEmpty else { return fallback }
        return fallback.enumerated().map { index, row in
            guard index < allWorkouts.count else { return row }
            let workout = allWorkouts[index]
            return PlanRow(
                day: row.day,
                date: row.date,
                type: workout.sport.rawValue.capitalized,
                title: workout.name,
                duration: workout.formattedDuration,
                zone: workout.sport == .running ? "Z3–4" : "Ready",
                icon: icon(for: workout.sport),
                done: row.done,
                today: row.today,
                rest: false,
                workout: workout
            )
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
}

private struct PlanRow {
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
