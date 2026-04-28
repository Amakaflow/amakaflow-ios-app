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
    @State private var showingSuggestWorkout = false
    @StateObject private var suggestWorkoutViewModel = SuggestWorkoutViewModel()
    @StateObject private var nutritionViewModel = NutritionViewModel()
    @State private var showingProteinTracker = false
    @State private var showingWaterTracker = false
    @State private var savedProgress: SavedWorkoutProgress?
    @State private var xpData: XPData?
    @State private var showLevelUp = false
    @State private var levelUpLevel: Int = 0
    @State private var levelUpName: String = ""

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
                    header

                    // Simulation mode indicator (AMA-271)
                    #if DEBUG
                    if simulationSettings.isEnabled {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.2.fill")
                                .font(.system(size: 14))
                            Text("Simulation Mode: \(simulationSettings.speedDisplayString)")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text("Settings \u{2192} Version \u{00D7} 7")
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

                    readinessCard

                    todaysWorkoutHero

                    // Nutrition Dashboard Card (AMA-1290)
                    if nutritionViewModel.settings.isEnabled {
                        NutritionDashboardCard(viewModel: nutritionViewModel)
                            .onTapGesture {
                                showingProteinTracker = true
                            }
                    }

                    // Suggest Workout button (AMA-1265)
                    SuggestWorkoutButton {
                        suggestWorkoutViewModel.requestSuggestion()
                        showingSuggestWorkout = true
                    }

                    // XP progress bar (AMA-1285)
                    if let xp = xpData {
                        XPBarView(
                            xpTotal: xp.xpTotal,
                            currentLevel: xp.currentLevel,
                            levelName: xp.levelName,
                            xpToNextLevel: xp.xpToNextLevel,
                            xpToday: xp.xpToday,
                            dailyCap: xp.dailyCap
                        )
                    }

                    // Quick action buttons
                    HStack(spacing: Theme.Spacing.md) {
                        quickStartButton
                        voiceWorkoutButton
                    }

                    // Rest Day Button (AMA-1286)
                    RestDayButton {
                        // TODO: call POST /gamification/rest-day
                    }

                    weekGlanceCard
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
            .sheet(isPresented: $showingProteinTracker) {
                ProteinTrackerView(viewModel: nutritionViewModel)
            }
            .sheet(isPresented: $showingWaterTracker) {
                WaterTrackerView(viewModel: nutritionViewModel)
            }
            .sheet(isPresented: $nutritionViewModel.showOnboarding) {
                NutritionOnboardingView(viewModel: nutritionViewModel)
            }
            .sheet(isPresented: $showingSuggestWorkout) {
                SuggestWorkoutView(viewModel: suggestWorkoutViewModel)
            }
            .sheet(isPresented: $showingVoiceWorkout) {
                VoiceWorkoutView()
            }
            .onAppear {
                // Load saved workout progress on background to avoid blocking main thread (AMA-1075)
                Task {
                    let progress = await Task.detached(priority: .utility) {
                        SavedWorkoutProgress.load()
                    }.value
                    await MainActor.run {
                        savedProgress = progress
                    }
                }
                // Nutrition refresh (AMA-1290)
                nutritionViewModel.checkOnboardingNeeded()
                if nutritionViewModel.settings.isEnabled {
                    Task {
                        await nutritionViewModel.refreshNutrition()
                    }
                }
                // Fetch XP data (AMA-1285)
                Task {
                    do {
                        xpData = try await APIService.shared.fetchXP()
                    } catch {
                        print("[HomeView] Failed to fetch XP: \(error)")
                    }
                }
            }
            .overlay {
                // Level-up celebration overlay (AMA-1285)
                if showLevelUp {
                    LevelUpCelebrationView(
                        newLevel: levelUpLevel,
                        levelName: levelUpName,
                        onDismiss: { showLevelUp = false }
                    )
                }
            }
            .overlay(alignment: .top) {
                // Invisible marker for Maestro E2E tests (container views
                // don't expose accessibilityIdentifier on iOS 26)
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("home_screen")
            }
        }
    }

    // MARK: - Weekly Progress Helper

    private var weeklyMotivationalText: String {
        let completed = historyViewModel.weeklySummary.workoutCount
        let target = max(1, completed + 1) // TODO: use actual weekly_target from API
        let remaining = max(0, target - completed)
        if completed >= target {
            return "Target hit! \(completed) of \(target) \u{2014} crushing it!"
        } else if remaining == 1 {
            return "\(completed) of \(target) \u{2014} one more to go!"
        } else if completed == 0 {
            return "0 of \(target) \u{2014} let\u{2019}s get started this week!"
        } else {
            return "\(completed) of \(target) \u{2014} \(remaining) more to go!"
        }
    }

    // MARK: - Resume Workout Banner

    private func resumeWorkoutBanner(progress: SavedWorkoutProgress) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue Workout")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(progress.workoutName)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Step \(progress.currentStepIndex + 1)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    Text(formatElapsedTime(progress.elapsedSeconds))
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textPrimary)
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
                    .foregroundColor(Theme.Colors.surface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.textPrimary)
                    .clipShape(Capsule())
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
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Color.clear)
                    .overlay(Capsule().stroke(Theme.Colors.borderMedium, lineWidth: 1))
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundSubtle)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
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
            print("Saved workout no longer available, clearing progress")
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
        HStack {
            AFLabel(text: today.formatted(.dateTime.weekday(.abbreviated)).uppercased() + " · " + today.formatted(.dateTime.month(.abbreviated).day()).uppercased())
            Spacer()
            Image(systemName: "bolt.fill")
                .font(.system(size: 18))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var readinessScore: Int { 78 }

    private var readinessCard: some View {
        AFCard(padding: 16) {
            HStack(spacing: Theme.Spacing.md) {
                AFReadinessRing(value: readinessScore)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.Ready.color(for: readinessScore))
                            .frame(width: 8, height: 8)
                            .shadow(color: Theme.Ready.color(for: readinessScore).opacity(0.4), radius: 4)
                        Text(Theme.Ready.label(for: readinessScore))
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    Text("HRV +8 vs baseline. Sleep 7h 42m. Go as planned.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(2)

                    HStack(spacing: 3) {
                        Text("Detail")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.top, 2)
                }
                Spacer()
            }
        }
    }

    private var todaysWorkoutHero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AFLabel(text: "Today")

            AFCard(padding: 0) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: primaryWorkoutIcon)
                                        .font(.system(size: 16))
                                    AFLabel(text: primaryWorkoutType)
                                }
                                .foregroundColor(Theme.Colors.textPrimary)

                                Text(primaryWorkout?.name ?? "4×8 min @ threshold")
                                    .font(Theme.Typography.title2)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                Text(primaryWorkoutSubtitle)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            Spacer()
                            AFChip(text: primaryWorkoutZone)
                        }

                        HStack(spacing: 0) {
                            heroStat(label: "Duration", value: primaryWorkout?.formattedDuration ?? "64m")
                            heroStat(label: "TSS", value: "78")
                            heroStat(label: "Intensity", value: "0.87")
                        }
                        .padding(.top, 10)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Theme.Colors.borderLight).frame(height: 1)
                        }
                    }
                    .padding(16)

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            if let workout = primaryWorkout { selectedWorkout = workout }
                        } label: {
                            Text("Details")
                        }
                        .buttonStyle(AFGhostButtonStyle())

                        Button {
                            if let workout = primaryWorkout {
                                startWorkoutWithDeviceCheck(workout)
                            } else {
                                showingQuickStart = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Start workout")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(AFPrimaryButtonStyle())
                    }
                    .padding(12)
                    .background(Theme.Colors.backgroundSubtle)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.Colors.borderLight).frame(height: 1)
                    }
                }
            }
        }
    }

    private func heroStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AFLabel(text: label)
            Text(value)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryWorkout: Workout? {
        todaysWorkouts.first ?? viewModel.upcomingWorkouts.first?.workout
    }

    private var primaryWorkoutIcon: String {
        switch primaryWorkout?.sport ?? .running {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.yoga"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "heart.fill"
        case .other: return "flag.fill"
        }
    }

    private var primaryWorkoutType: String {
        (primaryWorkout?.sport.rawValue ?? "threshold run").uppercased()
    }

    private var primaryWorkoutSubtitle: String {
        guard let workout = primaryWorkout else { return "64 min · Z3–Z4 · 10.2 km" }
        let steps = workout.intervalCount == 1 ? "1 step" : "\(workout.intervalCount) steps"
        return "\(workout.formattedDuration) · \(workout.sport.rawValue.capitalized) · \(steps)"
    }

    private var primaryWorkoutZone: String { primaryWorkout?.sport == .running ? "Zone 3–4" : "Ready" }

    private var weekGlanceCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AFLabel(text: "This Week")
            AFCard(padding: 14) {
                VStack(spacing: 12) {
                    HStack {
                        Text(weeklyMotivationalText)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Text("\(min(100, Int(Double(historyViewModel.weeklySummary.workoutCount) / Double(max(1, historyViewModel.weeklySummary.workoutCount + 2)) * 100)))%")
                            .font(Theme.Typography.mono)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.Colors.inputBackground)
                            Capsule()
                                .fill(Theme.Colors.textPrimary)
                                .frame(width: proxy.size.width * 0.67)
                        }
                    }
                    .frame(height: 3)

                    HStack {
                        ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { index, day in
                            VStack(spacing: 5) {
                                AFLabel(text: day)
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                                    .fill(index == 3 ? Theme.Colors.textPrimary : (index < 3 ? Theme.Colors.accentBackground : Color.clear))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                                            .stroke(Theme.Colors.borderLight, lineWidth: index > 3 ? 1 : 0)
                                    )
                                    .frame(width: 24, height: 24)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .task {
                await historyViewModel.loadCompletions()
            }
        }
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
            .foregroundColor(Theme.Colors.surface)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(Theme.Colors.textPrimary)
            .clipShape(Capsule())
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
            .foregroundColor(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(Color.clear)
            .overlay(Capsule().stroke(Theme.Colors.borderMedium, lineWidth: 1))
        }
        .accessibilityIdentifier("voice_workout_button")
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
