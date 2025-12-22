//
//  HomeView.swift
//  AmakaFlow
//
//  Home screen showing today's workouts and quick actions
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @State private var showingQuickStart = false
    @State private var selectedWorkout: Workout?
    @State private var showingWorkoutPlayer = false

    private var today: Date { Date() }

    private var dayName: String {
        today.formatted(.dateTime.weekday(.wide))
    }

    private var dateString: String {
        today.formatted(.dateTime.month(.wide).day())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header
                    header
                        .padding(.top, Theme.Spacing.md)

                    // Quick Start button
                    quickStartButton

                    // Today's Workouts
                    todaysWorkoutsSection

                    // Weekly stats
                    weeklyStatsCard
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 100) // Space for tab bar
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
            .sheet(isPresented: $showingQuickStart) {
                quickStartSheet
            }
            .fullScreenCover(isPresented: $showingWorkoutPlayer) {
                WorkoutPlayerView()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(dayName)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Text(dateString)
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Quick Start Button

    private var quickStartButton: some View {
        Button {
            showingQuickStart = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                Text("Quick Start Workout")
                    .font(Theme.Typography.bodyBold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(Theme.Colors.accentBlue)
            .cornerRadius(Theme.CornerRadius.lg)
        }
    }

    // MARK: - Today's Workouts Section

    private var todaysWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Section header
            HStack {
                Text("Today's Workouts")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Text("\(todaysWorkouts.count) \(todaysWorkouts.count == 1 ? "workout" : "workouts")")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                            .stroke(Theme.Colors.borderLight, lineWidth: 1)
                    )
                    .cornerRadius(Theme.CornerRadius.sm)
            }

            // Workouts list or empty state
            if todaysWorkouts.isEmpty {
                emptyWorkoutsState
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(todaysWorkouts) { workout in
                        TodayWorkoutCard(
                            workout: workout,
                            onTap: { selectedWorkout = workout }
                        )
                    }
                }
            }
        }
    }

    private var todaysWorkouts: [Workout] {
        // Filter workouts scheduled for today
        // For now, show all incoming workouts as we don't have scheduling yet
        viewModel.incomingWorkouts
    }

    private var emptyWorkoutsState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.surfaceElevated)
                    .frame(width: 64, height: 64)

                Image(systemName: "calendar")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text("No workouts scheduled")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Add a workout to your calendar to get started")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
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

    // MARK: - Weekly Stats Card

    private var weeklyStatsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.accentGreen)

                Text("This Week")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            HStack(spacing: Theme.Spacing.md) {
                StatItem(value: "5", label: "Workouts")
                StatItem(value: "4.2", label: "Avg Hours")
                StatItem(value: "95%", label: "Completion")
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    // MARK: - Quick Start Sheet

    private var quickStartSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Text("Select a workout to start")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.lg)

                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(viewModel.incomingWorkouts) { workout in
                            Button {
                                showingQuickStart = false
                                WorkoutEngine.shared.start(workout: workout)
                                // Small delay to let sheet dismiss before showing player
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    showingWorkoutPlayer = true
                                }
                            } label: {
                                WorkoutCard(workout: workout, isPrimary: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Quick Start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showingQuickStart = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Today Workout Card

private struct TodayWorkoutCard: View {
    let workout: Workout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                // Time column
                VStack(spacing: Theme.Spacing.xs) {
                    Text("9:00")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(workout.formattedDuration)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(width: 50)

                // Divider
                Rectangle()
                    .fill(Theme.Colors.borderLight)
                    .frame(width: 1)

                // Workout info
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

                    if let description = workout.description {
                        Text(description)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        Text(workout.sport.rawValue.capitalized)
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.surfaceElevated)
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

// MARK: - Stat Item

private struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}
