//
//  HomeView.swift
//  AmakaFlow
//
//  Home screen showing today's workouts and quick actions
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @StateObject private var historyViewModel = ActivityHistoryViewModel()
    @ObservedObject private var simulationSettings = SimulationSettings.shared
    @AppStorage("devicePreference") private var devicePreference: DevicePreference = .appleWatchPhone
    @State private var showingQuickStart = false
    @State private var selectedWorkout: Workout?
    @State private var showingWorkoutPlayer = false
    @State private var showingDeviceSheet = false
    @State private var pendingQuickStartWorkout: Workout?
    @State private var waitingForWatchWorkout: Workout?
    @State private var showingVoiceWorkout = false
    @State private var savedProgress: SavedWorkoutProgress?

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

                    // Simulation mode indicator (AMA-271)
                    #if DEBUG
                    if simulationSettings.isEnabled {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.2.fill")
                                .font(.system(size: 14))
                            Text("Simulation Mode: \(simulationSettings.speedDisplayString)")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text("Settings → Version × 7")
                                .font(.system(size: 11))
                                .foregroundColor(.black.opacity(0.6))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.yellow)
                        .cornerRadius(8)
                    }
                    #endif

                    // Resume Workout banner (if saved progress exists)
                    if let progress = savedProgress {
                        resumeWorkoutBanner(progress: progress)
                    }

                    // Quick action buttons
                    HStack(spacing: Theme.Spacing.md) {
                        // Quick Start button
                        quickStartButton

                        // Voice Workout button (AMA-5)
                        voiceWorkoutButton
                    }

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
            .sheet(isPresented: $showingDeviceSheet) {
                if let workout = pendingQuickStartWorkout {
                    PreWorkoutDeviceSheet(
                        workout: workout,
                        appleWatchConnected: WatchConnectivityManager.shared.isWatchReachable,
                        garminConnected: false,
                        amazfitConnected: false,
                        onSelectDevice: { device in
                            devicePreference = device
                            showingDeviceSheet = false
                            WorkoutEngine.shared.start(workout: workout)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingWorkoutPlayer = true
                            }
                        },
                        onClose: {
                            showingDeviceSheet = false
                            pendingQuickStartWorkout = nil
                        },
                        onChangeSettings: {
                            showingDeviceSheet = false
                            pendingQuickStartWorkout = nil
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .fullScreenCover(item: $waitingForWatchWorkout) { workout in
                WaitingForWatchView(
                    workout: workout,
                    onWatchConnected: {
                        waitingForWatchWorkout = nil
                        WorkoutEngine.shared.start(workout: workout)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingWorkoutPlayer = true
                        }
                    },
                    onCancel: {
                        waitingForWatchWorkout = nil
                    },
                    onUsePhoneInstead: {
                        waitingForWatchWorkout = nil
                        devicePreference = .phoneOnly
                        WorkoutEngine.shared.start(workout: workout)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingWorkoutPlayer = true
                        }
                    }
                )
            }
            .sheet(isPresented: $showingVoiceWorkout) {
                VoiceWorkoutView()
            }
            .onAppear {
                // Check for saved workout progress
                savedProgress = SavedWorkoutProgress.load()
            }
        }
    }

    // MARK: - Resume Workout Banner

    private func resumeWorkoutBanner(progress: SavedWorkoutProgress) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue Workout")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)

                    Text(progress.workoutName)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Step \(progress.currentStepIndex + 1)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(.white.opacity(0.8))

                    Text(formatElapsedTime(progress.elapsedSeconds))
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(.white)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                // Resume button
                Button {
                    resumeSavedWorkout(progress)
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.accentOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Color.white)
                    .cornerRadius(Theme.CornerRadius.md)
                }

                // Discard button
                Button {
                    SavedWorkoutProgress.clear()
                    savedProgress = nil
                } label: {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Discard")
                    }
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(Theme.CornerRadius.md)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accentOrange)
        .cornerRadius(Theme.CornerRadius.lg)
    }

    private func formatElapsedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d elapsed", minutes, secs)
    }

    private func resumeSavedWorkout(_ progress: SavedWorkoutProgress) {
        // Find the workout by ID in incoming or upcoming workouts
        let workout = viewModel.incomingWorkouts.first { $0.id == progress.workoutId }
            ?? viewModel.upcomingWorkouts.first { $0.workout.id == progress.workoutId }?.workout

        guard let workout = workout else {
            // Workout no longer available, clear progress
            print("🏋️ Saved workout no longer available, clearing progress")
            SavedWorkoutProgress.clear()
            savedProgress = nil
            return
        }

        // Resume the workout
        WorkoutEngine.shared.resume(workout: workout, fromProgress: progress)
        savedProgress = nil // Clear local state since WorkoutEngine.resume clears the saved progress

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showingWorkoutPlayer = true
        }
    }

    // MARK: - Device Check & Start

    /// Start workout, respecting device preference
    /// If Apple Watch is preferred but not reachable, show waiting screen
    /// For other unavailable devices, show device selection sheet
    private func startWorkoutWithDeviceCheck(_ workout: Workout) {
        let isPreferredDeviceAvailable: Bool

        switch devicePreference {
        case .appleWatchPhone, .appleWatchOnly:
            isPreferredDeviceAvailable = WatchConnectivityManager.shared.isWatchReachable
        case .phoneOnly:
            isPreferredDeviceAvailable = true
        case .garminPhone:
            // TODO: Check Garmin connectivity when available
            isPreferredDeviceAvailable = false
        case .amazfitPhone:
            // TODO: Check Amazfit connectivity when available
            isPreferredDeviceAvailable = false
        }

        if isPreferredDeviceAvailable {
            // Use saved preference directly
            WorkoutEngine.shared.start(workout: workout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingWorkoutPlayer = true
            }
        } else if devicePreference == .appleWatchPhone || devicePreference == .appleWatchOnly {
            // Apple Watch preferred but not reachable - show waiting screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                waitingForWatchWorkout = workout
            }
        } else {
            // Other device types - show device selection sheet
            pendingQuickStartWorkout = workout
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingDeviceSheet = true
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
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                Text("Quick Start")
                    .font(Theme.Typography.caption)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(Theme.Colors.accentBlue)
            .cornerRadius(Theme.CornerRadius.lg)
        }
    }

    // MARK: - Voice Workout Button (AMA-5)

    private var voiceWorkoutButton: some View {
        Button {
            showingVoiceWorkout = true
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                Text("Log Workout")
                    .font(Theme.Typography.caption)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(Theme.Colors.accentGreen)
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

            Text("Add a workout from the web, or log one you've completed")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Voice log button (AMA-5)
            Button {
                showingVoiceWorkout = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "mic.fill")
                    Text("Log with Voice")
                }
                .font(Theme.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(Theme.Colors.accentGreen)
            }
            .padding(.top, Theme.Spacing.sm)
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
        let summary = historyViewModel.weeklySummary

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.accentGreen)

                Text("This Week")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            if historyViewModel.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Theme.Spacing.md) {
                    StatItem(value: "\(summary.workoutCount)", label: "Workouts")
                    StatItem(value: summary.formattedDuration, label: "Time")
                    StatItem(value: summary.formattedCalories, label: "Calories")
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
        .task {
            await historyViewModel.loadCompletions()
        }
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
                                // Delay to allow sheet to fully dismiss before presenting next screen
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    startWorkoutWithDeviceCheck(workout)
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
