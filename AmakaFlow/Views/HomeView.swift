//
//  HomeView.swift
//  AmakaFlow
//
//  Home screen showing today's workouts and quick actions
//

import SwiftUI

enum HomeBannerKind {
    case replan(title: String, body: String)
    case redFlag(body: String)
    case lowConfidence(body: String)
}

struct HomeView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @StateObject private var homeViewModel = HomeViewModel()
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
    @State private var homeBannerKind: HomeBannerKind?
    @State private var showingPlanReveal = false
    @State private var planRevealReady = false
    @State private var planRevealReadyTask: Task<Void, Never>?
    @State private var showingPlanAdoptedAlert = false
    @State private var showingWeeklyReview = false
    @State private var showingAgentInbox = false
    @State private var showingProgramWizard = false
    @State private var showingReadinessDetail = false

    private var today: Date { Date() }

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

                    homeStateContent
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 100) // Space for tab bar
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                if homeViewModel.state == .content {
                    await historyViewModel.loadCompletions()
                }
            }
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
            .sheet(isPresented: $showingProgramWizard) {
                if FeatureFlags.programWizardEnabled {
                    ProgramWizardView()
                }
            }
            .sheet(isPresented: $showingReadinessDetail) {
                ReadinessDetailView()
            }
            .sheet(isPresented: $showingPlanReveal) {
                PlanRevealView(
                    isReady: planRevealReady,
                    onConfirm: {
                        // AMA-1631: Adopt the plan + give user visible feedback.
                        // Refresh workouts so the next view of Workouts/Home reflects
                        // the new schedule, then show a confirmation alert before
                        // dismissing the sheet.
                        // AMA-1644: Task body runs on MainActor (HomeView body is
                        // already MainActor-isolated and WorkoutsViewModel is
                        // @MainActor) — the explicit @MainActor on Task makes that
                        // explicit and removes the need for a redundant
                        // MainActor.run hop after the await.
                        // AMA-1645: stagger the sheet dismiss and the alert
                        // present by 0.35s. SwiftUI presentation transitions
                        // aren't atomic; flipping both flags in the same
                        // MainActor tick can drop the alert on iOS 16 when
                        // it shares a NavigationStack with the dismissing
                        // sheet. The delay is invisible on iOS 17+ (which
                        // handles the chained presentation cleanly) but
                        // prevents the race on the lowest supported target.
                        Task { @MainActor in
                            await viewModel.refreshWorkouts()
                            showingPlanReveal = false
                            do {
                                try await Task.sleep(for: .milliseconds(350))
                            } catch {
                                // Task cancelled (e.g. user manually dismissed
                                // the sheet mid-sleep) — bail without showing
                                // the alert.
                                return
                            }
                            showingPlanAdoptedAlert = true
                        }
                    },
                    onSkip: {
                        // AMA-1623: explicit Skip path so the user is never trapped
                        // (especially during the loading state if it stalls).
                        showingPlanReveal = false
                    }
                )
                .presentationDragIndicator(.visible)
                .onAppear {
                    // AMA-1644: cancellable Task instead of fire-and-forget
                    // asyncAfter, so tapping Skip during the 2s loading window
                    // doesn't fire planRevealReady = true on a hidden view.
                    planRevealReady = false
                    planRevealReadyTask?.cancel()
                    planRevealReadyTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        planRevealReady = true
                    }
                }
                .onDisappear {
                    planRevealReadyTask?.cancel()
                    planRevealReadyTask = nil
                }
            }
            .alert("Plan adopted", isPresented: $showingPlanAdoptedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your 4-week block is now on your calendar. Open the Workouts tab to see the schedule.")
            }
            .sheet(isPresented: $showingWeeklyReview) {
                WeeklyReviewView { showingWeeklyReview = false }
            }
            .sheet(isPresented: $showingAgentInbox) {
                AgentInboxView { showingAgentInbox = false }
            }
            .onAppear {
                refreshHomeScreenState()
                Task { await homeViewModel.loadReadiness() }
                // Load saved workout progress on background to avoid blocking main thread (AMA-1075)
                Task {
                    let progress = await Task.detached(priority: .utility) {
                        SavedWorkoutProgress.load()
                    }.value
                    await MainActor.run {
                        savedProgress = progress
                    }
                }
                // Nutrition refresh (AMA-1290) + AMA-1636: re-read settings from
                // UserDefaults so a toggle in NutritionSettingsView reflects on
                // Home without requiring an app relaunch.
                nutritionViewModel.reloadSettings()
                nutritionViewModel.checkOnboardingNeeded()
                if nutritionViewModel.settings.isEnabled {
                    Task {
                        await nutritionViewModel.refreshNutrition()
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _, _ in refreshHomeScreenState() }
            .onChange(of: viewModel.hasLoadedWorkouts) { _, _ in refreshHomeScreenState() }
            .onChange(of: viewModel.ctaError) { _, _ in refreshHomeScreenState() }
            .onChange(of: viewModel.incomingWorkouts) { _, _ in refreshHomeScreenState() }
            .onChange(of: viewModel.upcomingWorkouts) { _, _ in refreshHomeScreenState() }
            .onChange(of: viewModel.activeBlock) { _, _ in refreshHomeScreenState() }
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


    // MARK: - Home State

    @ViewBuilder
    private var homeStateContent: some View {
        switch homeViewModel.state {
        case .loading:
            homeLoadingState
        case .content:
            populatedHomeContent
        case .empty:
            homeEmptyState
        case .error(let ctaError):
            homeErrorState(ctaError)
        }
    }

    @ViewBuilder
    private var populatedHomeContent: some View {
        if let progress = savedProgress {
            resumeWorkoutBanner(progress: progress)
        }

        if let homeBannerKind {
            homeBanner(homeBannerKind)
        }

        homeMetricsGrid
        homeProgramCard

        if let workout = primaryWorkout {
            Button {
                startWorkoutWithDeviceCheck(workout)
            } label: {
                HStack(spacing: 6) {
                    Text("Start workout")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .lg))
            .padding(.top, Theme.Spacing.sm)
            .accessibilityIdentifier("ama1842.start.button")
        }

        homeWeekStripSection
        homeSummaryMetricsRow
        homeRecoveryCard

        #if DEBUG
        homeBannerDebugControls
        #endif
    }

    private var homeLoadingState: some View {
        AFCard(padding: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .tint(Theme.Colors.accentGreen)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Loading your training")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Checking for your plan and today’s workout.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("af_home_loading")
    }

    private var homeEmptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                AFLabel(text: "Program / Empty State")
                Text("Start with a path")
                    .font(Theme.Typography.largeTitle)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("af_home_empty_state")
                Text("No active plan or workout is scheduled for today. Choose how AmakaFlow should get you moving.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
            }

            VStack(spacing: Theme.Spacing.sm) {
                if FeatureFlags.programWizardEnabled {
                    Button {
                        showingProgramWizard = true
                    } label: {
                        emptyStateOptionLabel(
                            icon: "sparkles",
                            title: "Build me a plan",
                            subtitle: "Create a structured block around your goals.",
                            isPrimary: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Build me a plan")
                    .accessibilityIdentifier("af_home_empty_build_plan")
                }

                Button {
                    suggestWorkoutViewModel.requestSuggestion()
                    showingSuggestWorkout = true
                } label: {
                    emptyStateOptionLabel(
                        icon: "bolt.heart",
                        title: "Just today’s workout",
                        subtitle: "Get one coach-generated session for now.",
                        isPrimary: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Just today’s workout")
                .accessibilityIdentifier("af_home_empty_just_today")

                Button {
                    NotificationCenter.default.post(name: .deepLinkToCoach, object: nil)
                } label: {
                    emptyStateOptionLabel(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Coach picks for me",
                        subtitle: "Open the coach and let them choose the next step.",
                        isPrimary: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Coach picks for me")
                .accessibilityIdentifier("af_home_empty_coach_picks")
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
    }

    private func emptyStateOptionLabel(icon: String, title: String, subtitle: String, isPrimary: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.bodyBold)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(isPrimary ? Color.black.opacity(0.72) : Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isPrimary ? Color.black.opacity(0.72) : Theme.Colors.textTertiary)
        }
        .foregroundColor(isPrimary ? Color.black : Theme.Colors.textPrimary)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPrimary ? Theme.Colors.accentGreen : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                .stroke(isPrimary ? Color.clear : Theme.Colors.borderMedium, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
    }

    private func homeErrorState(_ ctaError: CTAError) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ErrorToast(
                actionTitle: "Couldn't load Home",
                error: ctaError,
                onRetry: ctaError.isRetryable ? {
                    Task { await viewModel.refreshWorkouts() }
                } : nil,
                onReport: {
                    homeViewModel.reportError()
                },
                onDismiss: nil
            )

            Text("We couldn’t verify whether you have a plan or a workout today.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityIdentifier("af_home_error_state")
    }

    private func refreshHomeScreenState() {
        homeViewModel.update(from: viewModel)
    }

    // MARK: - Agent Visibility Banners

    private func homeBanner(_ kind: HomeBannerKind) -> some View {
        let spec = bannerSpec(for: kind)
        return AFCard(padding: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: spec.icon)
                    .font(Theme.Typography.title2)
                    .foregroundColor(spec.color)
                    .frame(width: Theme.Spacing.lg, alignment: .center)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(spec.label)
                        .font(Theme.Typography.label)
                        .tracking(0.8)
                        .foregroundColor(spec.color)
                    Text(spec.title)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(spec.body)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(Theme.Spacing.xs)

                    if case .replan = kind {
                        HStack(spacing: Theme.Spacing.sm) {
                            Button("Approve") { homeBannerKind = nil }
                                .buttonStyle(AFPrimaryButtonStyle())
                            Button("Edit") { }
                                .buttonStyle(AFGhostButtonStyle())
                        }
                        .padding(.top, Theme.Spacing.sm)
                    }

                    if case .redFlag = kind {
                        Button("Safe to continue") { homeBannerKind = nil }
                            .buttonStyle(AFGhostButtonStyle())
                            .padding(.top, Theme.Spacing.sm)
                    }
                }

                Spacer()

                Button {
                    homeBannerKind = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .background(spec.color.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(spec.color.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }

    private struct BannerSpec {
        let icon: String
        let label: String
        let title: String
        let body: String
        let color: Color
    }

    private func bannerSpec(for kind: HomeBannerKind) -> BannerSpec {
        switch kind {
        case .replan(let title, let body):
            return BannerSpec(icon: "arrow.triangle.2.circlepath", label: "REPLAN PENDING", title: title, body: body, color: Theme.Colors.readyModerate)
        case .redFlag(let body):
            return BannerSpec(icon: "flag.fill", label: "RED FLAG", title: "Rest day recommended.", body: body, color: Theme.Colors.accentRed)
        case .lowConfidence(let body):
            return BannerSpec(icon: "info.circle.fill", label: "LOW CONFIDENCE", title: "Readiness is estimated today.", body: body, color: Theme.Colors.accentBlue)
        }
    }

    #if DEBUG
    private var homeBannerDebugControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AFLabel(text: "Agent banner debug")
            HStack(spacing: Theme.Spacing.sm) {
                Button("Replan") {
                    homeBannerKind = .replan(
                        title: "Coach moved today’s hard run to Friday.",
                        body: "Your recovery dipped overnight. Approve the safer sequence or edit the change."
                    )
                }
                .buttonStyle(AFGhostButtonStyle())

                Button("Red flag") {
                    homeBannerKind = .redFlag(body: "Stacked fatigue and calf symptoms make intensity risky today. The coach replaced training with mobility and a walk.")
                }
                .buttonStyle(AFGhostButtonStyle())

                Button("Low conf") {
                    homeBannerKind = .lowConfidence(body: "Garmin sleep did not sync. Connect your watch or train by feel; the coach will update when data lands.")
                }
                .buttonStyle(AFGhostButtonStyle())
            }
            Button("Hide banner") { homeBannerKind = nil }
                .buttonStyle(AFGhostButtonStyle())
        }
    }
    #endif

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

    // MARK: - Design refresh populated Home (screens-main.jsx)

    private var homeMetricsGrid: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                showingReadinessDetail = true
            } label: {
                homeMetricCard(
                    label: "READINESS",
                    value: homeViewModel.readinessScore.map { "\($0)" } ?? "—",
                    unit: homeViewModel.readinessScore == nil ? nil : "%",
                    footer: homeViewModel.readinessScore.map { Theme.Ready.label(for: $0) } ?? "No data",
                    readinessDot: homeViewModel.readinessScore
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_readiness_card")

            homeMetricCard(
                label: "TODAY'S LOAD",
                value: homeViewModel.todayAcuteLoad.map { String(format: "%.0f", $0) } ?? "—",
                unit: homeViewModel.todayAcuteLoad == nil ? nil : "tss",
                footer: nil,
                readinessDot: nil,
                loadMarkerPosition: homeViewModel.todayAcuteLoad.map { min(max($0 / 100.0, 0.08), 0.92) }
            )
        }
    }

    private func homeMetricCard(
        label: String,
        value: String,
        unit: String?,
        footer: String?,
        readinessDot: Int?,
        loadMarkerPosition: Double? = nil
    ) -> some View {
        AFCard(padding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                AFLabel(text: label)
                    .font(Theme.Typography.label)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 30, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.Colors.textPrimary)
                    if let unit {
                        Text(unit)
                            .font(Theme.Typography.mono)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .padding(.top, 6)

                if let footer {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(readinessDot.map { Theme.Ready.color(for: $0) } ?? Theme.Colors.borderMedium)
                            .frame(width: 6, height: 6)
                        Text(footer)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(.top, 8)
                }

                if let loadMarkerPosition {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Theme.Colors.readyHigh, Theme.Colors.readyModerate, Theme.Colors.readyLow],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 6)
                            Rectangle()
                                .fill(Theme.Colors.textPrimary)
                                .frame(width: 2, height: 6)
                                .offset(x: loadMarkerPosition * max(proxy.size.width - 2, 0))
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 12)

                    HStack {
                        Text("EASY")
                        Spacer()
                        Text("HARD")
                    }
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var homeProgramCard: some View {
        Button {
            NotificationCenter.default.post(name: .deepLinkToWorkout, object: nil)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    AFLabel(text: programCardEyebrow)
                    Text(programCardTitle)
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(programCardSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Theme.Colors.readyHigh.opacity(0.35),
                        Theme.Colors.readyHigh.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                    .stroke(Theme.Colors.readyHigh.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_home_program_card")
        .padding(.top, Theme.Spacing.sm)
    }

    private var programCardEyebrow: String {
        if viewModel.activeBlock != nil { return "CURRENT PROGRAM" }
        if primaryWorkout != nil { return "TODAY'S SESSION" }
        return "TRAINING PLAN"
    }

    private var programCardTitle: String {
        if let block = viewModel.activeBlock {
            return block.name
        }
        if let workout = primaryWorkout {
            return workout.name
        }
        return "No active plan"
    }

    private var programCardSubtitle: String {
        if let block = viewModel.activeBlock {
            return "Block \(block.index) of \(block.total) · \(block.scheduledWorkouts.count) sessions scheduled"
        }
        if let workout = primaryWorkout {
            return "\(workout.formattedDuration) · \(workout.sport.rawValue.capitalized) · \(workout.intervalCount) steps"
        }
        return "Open Workouts to view your schedule."
    }

    private var homeWeekStripSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                AFLabel(text: "THIS WEEK")
                Spacer()
                Button("See all") {
                    NotificationCenter.default.post(name: .deepLinkToWorkout, object: nil)
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .accessibilityIdentifier("af_home_week_see_all")
            }

            HStack(spacing: 4) {
                ForEach(homeWeekDays) { day in
                    homeWeekStripCell(day)
                }
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func homeWeekStripCell(_ day: HomeWeekDayItem) -> some View {
        Button {
            if day.isToday, let workout = day.workout {
                selectedWorkout = workout
            }
        } label: {
            VStack(spacing: 4) {
                AFLabel(text: day.weekdayLabel)
                    .font(Theme.Typography.label)
                Text("\(day.dayNumber)")
                    .font(Theme.Typography.mono)
                    .foregroundColor(Theme.Colors.textPrimary)
                RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                    .fill(day.isToday ? Color.clear : Theme.Colors.chipBackground)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: day.systemIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(day.isToday ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    }
                Text(day.valueLabel)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(day.isToday ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .fill(day.isToday ? Theme.Colors.readyHigh.opacity(0.40) : Theme.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .stroke(day.isToday ? Theme.Colors.readyHigh : Theme.Colors.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!day.isToday || day.workout == nil)
        .accessibilityIdentifier(day.isToday ? "af_home_week_today" : "af_home_week_\(day.weekdayLabel.lowercased())")
    }

    private var homeSummaryMetricsRow: some View {
        let summary = historyViewModel.weeklySummary
        return HStack(spacing: 0) {
            homeSummaryMetric(label: "STRESS", value: summary.totalCalories > 0 ? summary.formattedCalories : "—")
            homeSummaryMetric(label: "DIST", value: summary.totalDistanceMeters > 0 ? summary.formattedDistance : "—")
            homeSummaryMetric(label: "DUR", value: summary.workoutCount > 0 ? summary.formattedDuration : "—")
            homeSummaryMetric(label: "ELEV", value: "—")
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(Theme.Colors.backgroundSubtle)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
        .padding(.top, Theme.Spacing.md)
        .accessibilityIdentifier("af_home_summary_metrics")
    }

    private func homeSummaryMetric(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            AFLabel(text: label)
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private var homeRecoveryCard: some View {
        Button {
            showingReadinessDetail = true
        } label: {
            AFCard(padding: 12) {
                HStack(spacing: Theme.Spacing.md) {
                    AFReadinessRing(value: homeViewModel.readinessScore ?? 0, size: 42, stroke: 4)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            AFLabel(text: "RECOVERY")
                            Text("·")
                                .foregroundColor(Theme.Colors.textSecondary)
                            Text(homeViewModel.readinessScore.map { Theme.Ready.label(for: $0) } ?? "No data")
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                        Text(recoveryDetailLine)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.md)
        .accessibilityIdentifier("af_home_recovery_card")
    }

    private var recoveryDetailLine: String {
        if homeViewModel.readinessScore != nil {
            return "Tap for HRV, sleep, and training-load detail."
        }
        return "Connect a wearable or complete workouts to unlock recovery guidance."
    }

    private var homeWeekDays: [HomeWeekDayItem] {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return []
        }

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? today
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let dayNumber = calendar.component(.day, from: date)
            let weekdayLabel = date.formatted(.dateTime.weekday(.narrow)).uppercased()

            let dayCompletions = historyViewModel.completions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
            let scheduled = viewModel.upcomingWorkouts.first { scheduled in
                guard let scheduledDate = scheduled.scheduledDate else { return false }
                return calendar.isDate(scheduledDate, inSameDayAs: date)
            }

            let workout = isToday ? (primaryWorkout ?? scheduled?.workout) : scheduled?.workout

            let valueLabel: String
            if let completion = dayCompletions.first {
                let minutes = completion.durationSeconds / 60
                valueLabel = minutes >= 60 ? "\(minutes / 60)h\(minutes % 60)" : "\(minutes)m"
            } else if scheduled != nil {
                valueLabel = "plan"
            } else if dayCompletions.isEmpty && calendar.compare(date, to: today, toGranularity: .day) == .orderedAscending {
                valueLabel = "rest"
            } else {
                valueLabel = isToday && primaryWorkout != nil ? "today" : "—"
            }

            return HomeWeekDayItem(
                id: offset,
                weekdayLabel: weekdayLabel,
                dayNumber: dayNumber,
                isToday: isToday,
                systemIcon: iconForWeekDay(completion: dayCompletions.first, workout: workout ?? scheduled?.workout),
                valueLabel: valueLabel,
                workout: isToday ? primaryWorkout : scheduled?.workout
            )
        }
    }

    private func iconForWeekDay(completion: WorkoutCompletion?, workout: Workout?) -> String {
        if completion != nil { return "checkmark" }
        guard let sport = workout?.sport else { return "heart" }
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Color.clear.frame(width: 28, height: 28)

            Spacer()

            VStack(spacing: 2) {
                Text("Today")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("af_home_today_title")
                AFLabel(text: today.formatted(.dateTime.weekday(.abbreviated)).uppercased() + " · " + today.formatted(.dateTime.month(.abbreviated).day()).uppercased())
            }

            Spacer()

            Button {
                NotificationCenter.default.post(name: .deepLinkToSync, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("af_home_settings")
        }
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var primaryWorkout: Workout? {
        todaysWorkouts.first ?? viewModel.upcomingWorkouts.first?.workout
    }

    private var todaysWorkouts: [Workout] {
        viewModel.incomingWorkouts
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
                    if viewModel.incomingWorkouts.isEmpty {
                        // AMA-1629: actionable empty state when the user has no
                        // upcoming sessions. Without this the sheet rendered as
                        // an unhelpful blank — user dead-ended.
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "tray")
                                .font(.system(size: 36))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .padding(.top, Theme.Spacing.xl)

                            Text("No upcoming workouts")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)

                            Text("Generate one with the Coach or import from a source.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.xl)

                            Button {
                                showingQuickStart = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    suggestWorkoutViewModel.requestSuggestion()
                                    showingSuggestWorkout = true
                                }
                            } label: {
                                Text("Suggest a Workout")
                                    .font(Theme.Typography.bodyBold)
                            }
                            .buttonStyle(AFPrimaryButtonStyle())
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.top, Theme.Spacing.md)
                            .accessibilityIdentifier("quick_start_empty_suggest")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Spacing.xl)
                    } else {
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
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Quick Start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showingQuickStart = false
                    }
                    .accessibilityIdentifier("quick_start_cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Home Week Strip

private struct HomeWeekDayItem: Identifiable {
    let id: Int
    let weekdayLabel: String
    let dayNumber: Int
    let isToday: Bool
    let systemIcon: String
    let valueLabel: String
    let workout: Workout?
}

// MARK: - Preview

#Preview {
    HomeView()
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}
