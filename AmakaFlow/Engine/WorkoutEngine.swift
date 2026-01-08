//
//  WorkoutEngine.swift
//  AmakaFlow
//
//  Core state machine for workout execution
//  Single source of truth for workout state
//

import Foundation
import Combine
import UIKit
import os.log

private let logger = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "WorkoutEngine")

@MainActor
class WorkoutEngine: ObservableObject {
    static let shared = WorkoutEngine()

    // MARK: - Simulation Mode (AMA-271)

    /// Clock abstraction for timing - can be accelerated in simulation mode
    private var clock: WorkoutClock

    /// Whether this engine is running in simulation mode
    @Published private(set) var isSimulation: Bool = false

    /// Health data provider for simulation mode
    private var healthProvider: HealthDataProvider?

    /// Speed multiplier for display (1.0 = real-time)
    var simulationSpeed: Double {
        clock.speedMultiplier
    }

    // MARK: - Published State

    @Published private(set) var phase: WorkoutPhase = .idle
    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var workout: Workout?
    @Published private(set) var stateVersion: Int = 0
    @Published private(set) var elapsedSeconds: Int = 0

    // Rest state
    @Published private(set) var restRemainingSeconds: Int = 0
    @Published private(set) var isManualRest: Bool = false

    // Set weight tracking (AMA-281)
    /// Tracks set weights during workout, keyed by exercise name
    private var exerciseSetEntries: [String: [SetEntry]] = [:]
    /// Tracks exercise index for each exercise name (order encountered)
    private var exerciseIndexMap: [String: Int] = [:]
    private var nextExerciseIndex: Int = 0

    // MARK: - Flattened Steps

    private(set) var flattenedSteps: [FlattenedInterval] = []

    var currentStep: FlattenedInterval? {
        guard currentStepIndex >= 0, currentStepIndex < flattenedSteps.count else { return nil }
        return flattenedSteps[currentStepIndex]
    }

    var totalSteps: Int {
        flattenedSteps.count
    }

    var progress: Double {
        guard !flattenedSteps.isEmpty else { return 0 }
        return Double(currentStepIndex + 1) / Double(flattenedSteps.count)
    }

    var stepProgress: Double {
        guard let step = currentStep, let total = step.timerSeconds, total > 0 else { return 0 }
        return 1.0 - (Double(remainingSeconds) / Double(total))
    }

    var isActive: Bool {
        phase == .running || phase == .paused || phase == .resting
    }

    // MARK: - Private

    private var audioCueManager = AudioCueManager()
    private var cancellables = Set<AnyCancellable>()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var workoutStartTime: Date?
    private var cachedDevicePreference: DevicePreference = .appleWatchPhone // Cached to avoid UserDefaults reads in hot path (AMA-226)

    /// Default init for shared singleton (uses real clock by default, but can switch to simulation)
    private init() {
        self.clock = RealClock()
        self.isSimulation = false
        self.healthProvider = nil
        setupBackgroundHandling()
    }

    /// Configure for simulation mode based on current settings (AMA-271)
    /// Called automatically when starting a workout if simulation is enabled
    private func configureForSimulation() {
        let settings = SimulationSettings.shared
        if settings.isEnabled {
            self.clock = settings.createClock()
            self.healthProvider = settings.createHealthProvider()
            self.isSimulation = true
            print("🎮 [Simulation Mode] Enabled - Speed: \(settings.speed)x, Profile: \(settings.profileName)")
        } else {
            self.clock = RealClock()
            self.healthProvider = nil
            self.isSimulation = false
        }
    }

    // MARK: - Commands

    func start(workout: Workout) {
        // End any existing session
        if isActive {
            end(reason: .userEnded)
        }

        // Configure simulation mode based on current settings (AMA-271)
        configureForSimulation()

        // Clear any saved progress since we're starting fresh
        SavedWorkoutProgress.clear()

        // Reset all state for fresh start
        clock.invalidateTimer()
        self.workout = workout
        self.flattenedSteps = flattenIntervals(workout.intervals)
        self.currentStepIndex = 0
        self.remainingSeconds = 0
        self.elapsedSeconds = 0
        self.restRemainingSeconds = 0
        self.isManualRest = false
        self.phase = .running
        self.stateVersion += 1
        self.workoutStartTime = Date()
        clearSetTracking()  // (AMA-281) Reset weight tracking

        // Cache device preference at start to avoid UserDefaults reads during workout (AMA-226)
        self.cachedDevicePreference = devicePreference

        // Track workout start (AMA-225)
        SentryService.shared.trackWorkoutAction("Started workout", workoutId: workout.id, workoutName: workout.name)

        print("🏋️ Starting workout: \(workout.name)")
        print("🏋️ Intervals count: \(workout.intervals.count)")
        print("🏋️ Flattened steps count: \(flattenedSteps.count)")
        if let first = flattenedSteps.first {
            print("🏋️ First step: \(first.label), timerSeconds: \(first.timerSeconds ?? -1)")
        }

        setupCurrentStep()
        broadcastState()
        audioCueManager.announceWorkoutStart(workout.name)

        // Start Live Activity
        startLiveActivity()

        beginBackgroundTask()
    }

    /// Resume a workout from saved progress
    func resume(workout: Workout, fromProgress progress: SavedWorkoutProgress) {
        // End any existing session
        if isActive {
            end(reason: .userEnded)
        }

        // Clear the saved progress since we're resuming
        SavedWorkoutProgress.clear()

        // Setup workout state
        clock.invalidateTimer()
        self.workout = workout
        self.flattenedSteps = flattenIntervals(workout.intervals)

        // Restore progress
        self.currentStepIndex = min(progress.currentStepIndex, flattenedSteps.count - 1)
        self.elapsedSeconds = progress.elapsedSeconds
        self.remainingSeconds = 0
        self.restRemainingSeconds = 0
        self.isManualRest = false
        self.phase = .running
        self.stateVersion += 1
        self.workoutStartTime = Date().addingTimeInterval(-Double(progress.elapsedSeconds))

        // Cache device preference
        self.cachedDevicePreference = devicePreference

        // Track resume (AMA-225)
        SentryService.shared.trackWorkoutAction("Resumed saved workout", workoutId: workout.id, workoutName: workout.name)

        print("🏋️ Resuming workout: \(workout.name) from step \(currentStepIndex + 1)/\(flattenedSteps.count)")
        print("🏋️ Elapsed time: \(elapsedSeconds)s")

        setupCurrentStep()
        broadcastState()
        audioCueManager.announceStep("Resuming \(workout.name)", roundInfo: nil)

        // Start Live Activity
        startLiveActivity()

        beginBackgroundTask()
    }

    /// Check if there's saved workout progress
    static var hasSavedProgress: Bool {
        SavedWorkoutProgress.load() != nil
    }

    /// Get saved workout progress if available
    static var savedProgress: SavedWorkoutProgress? {
        SavedWorkoutProgress.load()
    }

    func pause() {
        guard phase == .running else { return }

        phase = .paused
        clock.invalidateTimer()
        stateVersion += 1
        broadcastState()
        audioCueManager.announcePaused()

        // Track pause (AMA-225)
        SentryService.shared.trackWorkoutAction("Paused workout", workoutId: workout?.id, workoutName: workout?.name)
    }

    func resume() {
        guard phase == .paused else { return }

        phase = .running
        startTimer()
        stateVersion += 1
        broadcastState()
        audioCueManager.announceResumed()

        // Track resume (AMA-225)
        SentryService.shared.trackWorkoutAction("Resumed workout", workoutId: workout?.id, workoutName: workout?.name)
    }

    func togglePlayPause() {
        switch phase {
        case .running:
            pause()
        case .paused:
            resume()
        case .idle, .ended, .resting:
            break
        }
    }

    func nextStep() {
        print("🏋️ nextStep() called. currentStepIndex: \(currentStepIndex), flattenedSteps.count: \(flattenedSteps.count), phase: \(phase)")

        // Check if current step has rest after it
        if let currentStep = currentStep {
            print("🏋️ Current step: '\(currentStep.label)', hasRestAfter: \(currentStep.hasRestAfter), restAfterSeconds: \(currentStep.restAfterSeconds ?? -1)")
            if currentStep.hasRestAfter && phase != .resting {
                print("🏋️ → Entering rest phase because hasRestAfter=true and phase!=resting")
                enterRestPhase(restSeconds: currentStep.restAfterSeconds)
                return
            } else if !currentStep.hasRestAfter {
                print("🏋️ → Skipping rest because hasRestAfter=false")
            } else if phase == .resting {
                print("🏋️ → Already in resting phase, advancing to next step")
            }
        }

        guard currentStepIndex < flattenedSteps.count - 1 else {
            print("🏋️ No more steps! Ending workout.")
            end(reason: .completed)
            return
        }

        currentStepIndex += 1
        print("🏋️ Advanced to step \(currentStepIndex): \(currentStep?.label ?? "nil")")
        setupCurrentStep()
        stateVersion += 1
        broadcastState()
    }

    /// Enter the rest phase between exercises
    private func enterRestPhase(restSeconds: Int?) {
        print("🏋️ enterRestPhase() called. phase before: \(phase), restSeconds: \(restSeconds ?? -1), isSimulation: \(isSimulation)")

        clock.invalidateTimer()

        phase = .resting
        print("🏋️ enterRestPhase: phase set to .resting")

        if let seconds = restSeconds, seconds > 0 {
            // Timed rest
            isManualRest = false
            restRemainingSeconds = seconds
            startRestTimer()
            print("🏋️ enterRestPhase: Starting timed rest of \(seconds)s")
        } else if isSimulation {
            // In simulation mode, convert manual rest to short timed rest (3s simulated)
            // This allows simulation to auto-advance without user interaction
            isManualRest = false
            restRemainingSeconds = 3
            startRestTimer()
            print("🎮 enterRestPhase: Simulation mode - converting manual rest to 3s timed rest")
        } else {
            // Manual rest (nil or 0 treated as manual "tap when ready")
            isManualRest = true
            restRemainingSeconds = 0
            print("🏋️ enterRestPhase: Manual rest (tap when ready)")
        }

        stateVersion += 1
        broadcastState()
        audioCueManager.announceRest(isManual: isManualRest, seconds: restRemainingSeconds)
        print("🏋️ enterRestPhase: Complete. phase=\(phase), isManualRest=\(isManualRest)")
    }

    private func startRestTimer() {
        clock.invalidateTimer()
        print("🎮 [Rest Timer] Starting with clock speed: \(clock.speedMultiplier)x, restSeconds: \(restRemainingSeconds)")
        clock.scheduleTimer(interval: 1.0) { [weak self] in
            self?.restTimerTick()
        }
    }

    private func restTimerTick() {
        print("🎮 [Rest Timer] Tick - remaining: \(restRemainingSeconds)")
        guard restRemainingSeconds > 0 else {
            // Rest complete, advance to next step
            print("🎮 [Rest Timer] Calling completeRest()")
            completeRest()
            return
        }

        restRemainingSeconds -= 1
        elapsedSeconds += 1
        stateVersion += 1  // Force UI update on every tick

        // Countdown audio for last 3 seconds
        if restRemainingSeconds <= 3 && restRemainingSeconds > 0 {
            audioCueManager.announceCountdown(restRemainingSeconds)
        }

        // Auto-advance when timer hits 0
        if restRemainingSeconds == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.completeRest()
            }
        }

        // Throttled state broadcast
        if elapsedSeconds % 5 == 0 {
            broadcastState()
        }
    }

    /// Complete the rest phase and advance to the next step
    func completeRest() {
        print("🏋️ completeRest() called. phase: \(phase), currentStepIndex: \(currentStepIndex)")
        guard phase == .resting else {
            print("🏋️ completeRest() returning early - phase is not .resting")
            return
        }

        print("🏋️ Completing rest, advancing to next step")

        clock.invalidateTimer()
        restRemainingSeconds = 0
        isManualRest = false

        // Check if there are more steps
        guard currentStepIndex < flattenedSteps.count - 1 else {
            print("🏋️ No more steps after rest! Ending workout.")
            end(reason: .completed)
            return
        }

        currentStepIndex += 1
        phase = .running
        print("🏋️ After completeRest: phase=\(phase), currentStepIndex=\(currentStepIndex), step='\(currentStep?.label ?? "nil")'")
        setupCurrentStep()
        stateVersion += 1
        broadcastState()
    }

    /// Skip the current rest period and advance immediately
    func skipRest() {
        print("🏋️ skipRest() called. phase: \(phase)")
        guard phase == .resting else {
            print("🏋️ skipRest() returning early - phase is not .resting")
            return
        }
        completeRest()
    }

    // MARK: - Set Weight Tracking (AMA-281)

    /// Log weight for the current set and advance to next step
    /// - Parameters:
    ///   - weight: Weight used (nil if skipped)
    ///   - unit: Weight unit ("lbs" or "kg")
    func logSetWeight(weight: Double?, unit: String?) {
        guard let step = currentStep, step.stepType == .reps else {
            print("🏋️ logSetWeight: Not a reps step, ignoring")
            nextStep()
            return
        }

        let exerciseName = step.label
        let setNumber = step.setNumber ?? 1

        // Track exercise index (first time we see this exercise)
        if exerciseIndexMap[exerciseName] == nil {
            exerciseIndexMap[exerciseName] = nextExerciseIndex
            nextExerciseIndex += 1
        }

        // Create set entry
        let entry = SetEntry(
            setNumber: setNumber,
            weight: weight,
            unit: weight != nil ? unit : nil,
            completed: true
        )

        // Add to exercise's set list
        if exerciseSetEntries[exerciseName] == nil {
            exerciseSetEntries[exerciseName] = []
        }
        exerciseSetEntries[exerciseName]?.append(entry)

        print("🏋️ Logged set: \(exerciseName) set \(setNumber) - weight: \(weight ?? 0) \(unit ?? "")")

        // Advance to next step (which may trigger rest phase)
        nextStep()
    }

    /// Build SetLog array for workout completion submission
    func buildSetLogs() -> [SetLog]? {
        guard !exerciseSetEntries.isEmpty else { return nil }

        var logs: [SetLog] = []
        for (exerciseName, entries) in exerciseSetEntries {
            let exerciseIndex = exerciseIndexMap[exerciseName] ?? 0
            let log = SetLog(
                exerciseName: exerciseName,
                exerciseIndex: exerciseIndex,
                sets: entries
            )
            logs.append(log)
        }

        // Sort by exercise index to maintain workout order
        return logs.sorted { $0.exerciseIndex < $1.exerciseIndex }
    }

    /// Clear set tracking data (called on workout start/reset)
    private func clearSetTracking() {
        exerciseSetEntries.removeAll()
        exerciseIndexMap.removeAll()
        nextExerciseIndex = 0
    }

    /// Get the last logged weight for an exercise (for pre-filling subsequent sets)
    /// - Parameter exerciseName: The exercise name to look up
    /// - Returns: Tuple of (weight, unit) if found, nil otherwise
    func getLastWeight(for exerciseName: String) -> (weight: Double, unit: String)? {
        guard let entries = exerciseSetEntries[exerciseName],
              let lastEntry = entries.last(where: { $0.weight != nil }),
              let weight = lastEntry.weight,
              let unit = lastEntry.unit else {
            return nil
        }
        return (weight, unit)
    }

    func previousStep() {
        guard currentStepIndex > 0 else { return }

        currentStepIndex -= 1
        setupCurrentStep()
        stateVersion += 1
        broadcastState()
    }

    func skipToStep(_ index: Int) {
        guard index >= 0, index < flattenedSteps.count else { return }

        currentStepIndex = index
        setupCurrentStep()
        stateVersion += 1
        broadcastState()
    }

    func end(reason: EndReason) {
        print("🏋️ END called with reason: \(reason)")
        print("🏋️ currentStepIndex: \(currentStepIndex), flattenedSteps.count: \(flattenedSteps.count)")
        Thread.callStackSymbols.prefix(10).forEach { print("🏋️ \($0)") }

        // Track workout end (AMA-225)
        let endAction: String
        switch reason {
        case .completed:
            endAction = "Completed workout"
        case .userEnded:
            endAction = "Ended workout (saved)"
        case .discarded:
            endAction = "Discarded workout"
        case .savedForLater:
            endAction = "Saved workout for later"
        case .error:
            endAction = "Ended workout (error)"
        }
        SentryService.shared.trackWorkoutAction(endAction, workoutId: workout?.id, workoutName: workout?.name)

        // Save progress for Resume Later
        if reason == .savedForLater, let workoutId = workout?.id, let workoutName = workout?.name {
            let progress = SavedWorkoutProgress(
                workoutId: workoutId,
                workoutName: workoutName,
                currentStepIndex: currentStepIndex,
                elapsedSeconds: elapsedSeconds,
                savedAt: Date()
            )
            progress.save()
        }

        // Capture workout data before resetting state
        let workoutData = (
            id: workout?.id,
            name: workout?.name,
            startTime: workoutStartTime,
            duration: elapsedSeconds,
            intervals: workout?.intervals,  // (AMA-237) For "Run Again" feature
            setLogs: buildSetLogs()         // (AMA-281) Weight tracking
        )

        clock.invalidateTimer()
        phase = .ended
        stateVersion += 1
        broadcastState()

        if reason == .completed {
            audioCueManager.announceWorkoutComplete()
        }

        // Only post workout completion to API if completed or userEnded (not discarded or saved for later)
        if reason == .completed || reason == .userEnded || reason == .error {
            postWorkoutCompletion(
                workoutId: workoutData.id,
                workoutName: workoutData.name,
                startedAt: workoutData.startTime,
                durationSeconds: workoutData.duration,
                intervals: workoutData.intervals,  // (AMA-237) For "Run Again" feature
                setLogs: workoutData.setLogs       // (AMA-281) Weight tracking
            )
        } else if reason == .discarded {
            print("🏋️ Workout discarded - not posting to API")
        } else if reason == .savedForLater {
            print("🏋️ Workout saved for later - not posting to API")
        }

        // End Live Activity
        Task {
            await LiveActivityManager.shared.endActivity()
        }

        endBackgroundTask()

        // Cleanup after brief delay - but only if still in ended state
        // (a new workout might have started in the meantime)
        let endedVersion = stateVersion
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            // Only reset if no new workout started
            if self.stateVersion == endedVersion && self.phase == .ended {
                self.reset()
            }
        }
    }

    func reset() {
        clock.invalidateTimer()

        // End any active Live Activity
        Task {
            await LiveActivityManager.shared.endActivity()
        }

        phase = .idle
        workout = nil
        flattenedSteps = []
        currentStepIndex = 0
        remainingSeconds = 0
        elapsedSeconds = 0
        stateVersion += 1
        workoutStartTime = nil
        clearSetTracking()  // (AMA-281) Clear weight tracking
    }

    // MARK: - Workout Completion

    private func postWorkoutCompletion(
        workoutId: String?,
        workoutName: String?,
        startedAt: Date?,
        durationSeconds: Int,
        intervals: [WorkoutInterval]?,  // (AMA-237) For "Run Again" feature
        setLogs: [SetLog]?              // (AMA-281) Weight tracking
    ) {
        // Check auth status for logging
        let isPaired = PairingService.shared.isPaired
        #if DEBUG
        let isE2EMode = TestAuthStore.shared.isTestModeEnabled
        let hasAuth = isPaired || isE2EMode
        #else
        let isE2EMode = false
        let hasAuth = isPaired
        #endif

        logger.info("postWorkoutCompletion called")
        logger.info("- workoutId: \(workoutId ?? "nil")")
        logger.info("- workoutName: \(workoutName ?? "nil")")
        logger.info("- startedAt: \(startedAt?.description ?? "nil")")
        logger.info("- durationSeconds: \(durationSeconds)")
        logger.info("- isPaired: \(isPaired), isE2EMode: \(isE2EMode), hasAuth: \(hasAuth)")
        logger.info("- intervals count: \(intervals?.count ?? 0)")

        // Log to DebugLogService for in-app visibility (AMA-271)
        DebugLogService.shared.log(
            "Completion: Starting",
            details: "workout=\(workoutId ?? "nil"), duration=\(durationSeconds)s",
            metadata: ["isPaired": "\(isPaired)", "isE2EMode": "\(isE2EMode)", "hasAuth": "\(hasAuth)"]
        )

        guard let workoutId = workoutId,
              let startedAt = startedAt else {
            print("🏋️ Cannot post completion - missing workout ID or start time")
            DebugLogService.shared.log(
                "Completion: SKIPPED",
                details: "Missing workout ID or start time",
                metadata: ["workoutId": workoutId ?? "nil", "startedAt": startedAt?.description ?? "nil"]
            )
            return
        }

        let endedAt = Date()

        // Get health metrics from connected watch if available
        // In E2E test mode (TEST_AUTH_SECRET set), generate mock data
        let (avgHeartRate, activeCalories) = getHealthMetrics(durationSeconds: durationSeconds)

        Task {
            do {
                let response = try await WorkoutCompletionService.shared.postPhoneWorkoutCompletion(
                    workoutId: workoutId,
                    workoutName: workoutName ?? "Workout",
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: durationSeconds,
                    avgHeartRate: avgHeartRate,
                    activeCalories: activeCalories,
                    workoutStructure: intervals,  // (AMA-240) Include workout structure for "Run Again"
                    isSimulated: isSimulation,    // (AMA-271) Flag simulated workouts
                    setLogs: setLogs              // (AMA-281) Weight tracking
                )
                logger.info("Workout completion posted successfully")
                DebugLogService.shared.log(
                    "Completion: SUCCESS",
                    details: "Posted for workout \(workoutId)",
                    metadata: ["completionId": response?.resolvedCompletionId ?? "nil"]
                )

                // Notify WorkoutsViewModel to remove from incoming/upcoming lists (AMA-237)
                NotificationCenter.default.post(
                    name: .workoutCompleted,
                    object: nil,
                    userInfo: ["workoutId": workoutId]
                )
            } catch {
                logger.error("Failed to post workout completion: \(error.localizedDescription)")
                DebugLogService.shared.logCompletionError(
                    workoutId: workoutId,
                    error: error,
                    context: "WorkoutEngine.postWorkoutCompletion"
                )
                // Error is already logged and queued for retry by WorkoutCompletionService
            }
        }
    }

    /// Get health metrics - uses simulated data in simulation mode, mock data in E2E test mode, otherwise from Watch
    private func getHealthMetrics(durationSeconds: Int) -> (avgHeartRate: Int?, activeCalories: Int?) {
        // Check for simulation mode health provider first (AMA-271)
        if isSimulation, let provider = healthProvider {
            let data = provider.getCollectedData()
            print("🏋️ [Simulation Mode] Using simulated health data: avgHR=\(data.avgHR), calories=\(data.calories)")
            return (data.avgHR, data.calories)
        }

        #if DEBUG
        // Check if running in E2E test mode (via TestAuthStore - supports both env vars and UI bypass)
        if TestAuthStore.shared.isTestModeEnabled {
            // Generate realistic mock health data for E2E tests
            // Average HR varies by workout intensity - use 130-150 bpm range for strength training
            let baseHR = 140
            let hrVariation = Int.random(in: -10...10)
            let mockAvgHR = baseHR + hrVariation

            // Calories burned: approximately 5-7 cal/min for strength training
            let caloriesPerMinute = Double.random(in: 5.0...7.0)
            let durationMinutes = Double(durationSeconds) / 60.0
            let mockCalories = Int(caloriesPerMinute * durationMinutes)

            print("🏋️ [E2E Test Mode] Using mock health data: avgHR=\(mockAvgHR), calories=\(mockCalories)")
            return (mockAvgHR, mockCalories)
        }
        #endif

        // Production mode: get data from connected watch
        let watchCals = WatchConnectivityManager.shared.watchActiveCalories
        let activeCalories: Int? = watchCals > 0 ? Int(watchCals) : nil

        // Try to get heart rate from watch samples
        let hrSamples = WatchConnectivityManager.shared.heartRateSamples
        let avgHeartRate: Int? = hrSamples.isEmpty ? nil : {
            let sum = hrSamples.reduce(0) { $0 + $1.value }
            return sum / hrSamples.count
        }()

        return (avgHeartRate, activeCalories)
    }

    // MARK: - Timer Management

    private func setupCurrentStep() {
        clock.invalidateTimer()

        guard let step = currentStep else {
            print("🏋️ setupCurrentStep: No current step! Index: \(currentStepIndex)")
            return
        }

        print("🏋️ setupCurrentStep: \(step.label), timerSeconds: \(step.timerSeconds ?? -1), stepType: \(step.stepType)")

        // Announce step
        audioCueManager.announceStep(step.label, roundInfo: step.roundInfo)

        // Setup timer for timed steps
        if let seconds = step.timerSeconds {
            remainingSeconds = seconds
            if phase == .running {
                startTimer()
                print("🏋️ Timer started with \(seconds) seconds")
            }
        } else if isSimulation && (step.stepType == .reps || step.stepType == .distance) {
            // In simulation mode, give reps/distance steps a short timer to auto-advance
            remainingSeconds = 5  // 5 seconds simulated time to "complete" the step
            if phase == .running {
                startTimer()
                print("🎮 Simulation mode: Starting 5s timer for \(step.stepType) step")
            }
        } else {
            remainingSeconds = 0
            print("🏋️ No timer for this step (reps/distance)")
        }
    }

    private func startTimer() {
        clock.invalidateTimer()
        print("🎮 [Work Timer] Starting with clock speed: \(clock.speedMultiplier)x, remainingSeconds: \(remainingSeconds)")
        clock.scheduleTimer(interval: 1.0) { [weak self] in
            self?.timerTick()
        }
    }

    private func timerTick() {
        elapsedSeconds += 1
        print("🎮 [Work Timer] Tick - remaining: \(remainingSeconds), elapsed: \(elapsedSeconds)")

        guard remainingSeconds > 0 else {
            // For reps/distance steps, don't auto-advance (unless in simulation mode)
            let stepType = currentStep?.stepType
            if (stepType == .reps || stepType == .distance) && !isSimulation {
                return
            }
            nextStep()
            return
        }

        remainingSeconds -= 1

        // Countdown audio for last 3 seconds
        if remainingSeconds <= 3 && remainingSeconds > 0 {
            audioCueManager.announceCountdown(remainingSeconds)
        }

        // Auto-advance when timer hits 0
        if remainingSeconds == 0 {
            // Small delay before advancing to allow "0" to display
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.nextStep()
            }
        }

        // Throttled state broadcast (every 5 seconds)
        if elapsedSeconds % 5 == 0 {
            broadcastState()
        }
    }

    // MARK: - State Broadcasting

    /// Returns the current device preference from UserDefaults
    private var devicePreference: DevicePreference {
        guard let rawValue = UserDefaults.standard.string(forKey: "devicePreference"),
              let preference = DevicePreference(rawValue: rawValue) else {
            return .appleWatchPhone // Default
        }
        return preference
    }

    private func broadcastState() {
        let state = buildCurrentState()

        // Use cached device preference to avoid UserDefaults reads in hot path (AMA-226)
        switch cachedDevicePreference {
        case .appleWatchPhone, .appleWatchOnly:
            WatchConnectivityManager.shared.sendState(state)
        case .garminPhone:
            GarminConnectManager.shared.sendWorkoutState(state)
        case .phoneOnly, .amazfitPhone:
            // No watch to broadcast to (Amazfit not yet implemented)
            break
        }

        // Update Live Activity
        updateLiveActivity(state)
    }

    /// Explicitly sends current state to Apple Watch (called when watch requests state)
    func sendStateToWatch() {
        guard isActive else { return }
        let state = buildCurrentState()
        WatchConnectivityManager.shared.sendState(state)
    }

    /// Explicitly sends current state to Garmin Watch (called when watch requests state)
    func sendStateToGarmin() {
        guard isActive else { return }
        let state = buildCurrentState()
        GarminConnectManager.shared.sendWorkoutState(state)
    }

    // MARK: - Live Activity Integration

    private func startLiveActivity() {
        guard let workout = workout else { return }

        // Skip Live Activity when Watch is connected and being used for remote control.
        // The Live Activity would mirror to Watch's Smart Stack and show an "Open on iPhone"
        // card, which is confusing when the user is already using the Watch remote control UI (AMA-223).
        if WatchConnectivityManager.shared.isWatchReachable {
            print("🔵 Skipping Live Activity - Watch is connected for remote control")
            return
        }

        let initialState = WorkoutActivityAttributes.ContentState(
            phase: phase.rawValue,
            stepName: currentStep?.label ?? "",
            stepIndex: currentStepIndex + 1,  // 1-based for display
            stepCount: flattenedSteps.count,
            remainingSeconds: currentStep?.timerSeconds ?? 0,
            stepType: currentStep?.stepType.rawValue ?? "reps",
            roundInfo: currentStep?.roundInfo
        )

        LiveActivityManager.shared.startActivity(
            workoutId: workout.id,
            workoutName: workout.name,
            initialState: initialState
        )
    }

    private func updateLiveActivity(_ state: WorkoutState) {
        // End Live Activity if Watch becomes reachable mid-workout (AMA-223)
        if WatchConnectivityManager.shared.isWatchReachable {
            Task {
                await LiveActivityManager.shared.endActivity()
                print("🔵 Ended Live Activity - Watch became reachable")
            }
            return
        }

        let activityState = WorkoutActivityAttributes.ContentState(
            phase: state.phase.rawValue,
            stepName: state.stepName,
            stepIndex: state.stepIndex + 1,  // 1-based for display
            stepCount: state.stepCount,
            remainingSeconds: (state.remainingMs ?? 0) / 1000,
            stepType: state.stepType.rawValue,
            roundInfo: state.roundInfo
        )

        LiveActivityManager.shared.updateActivity(state: activityState)
    }

    private func buildCurrentState() -> WorkoutState {
        WorkoutState(
            stateVersion: stateVersion,
            workoutId: workout?.id ?? "",
            workoutName: workout?.name ?? "",
            phase: phase,
            stepIndex: currentStepIndex,
            stepCount: flattenedSteps.count,
            stepName: currentStep?.label ?? "",
            stepType: currentStep?.stepType ?? .reps,
            remainingMs: remainingSeconds * 1000,
            roundInfo: currentStep?.roundInfo,
            targetReps: currentStep?.targetReps,
            lastCommandAck: nil
        )
    }

    // MARK: - Remote Commands (from Watch)

    func handleRemoteCommand(_ command: RemoteCommand, commandId: String) {
        switch command {
        case .pause:
            pause()
        case .resume:
            resume()
        case .nextStep:
            nextStep()
        case .previousStep:
            previousStep()
        case .skipRest:
            skipRest()
        case .end:
            end(reason: .userEnded)
        }

        // ACK the command to the appropriate watch based on preference
        let ack = CommandAck(commandId: commandId, status: .success, errorCode: nil)
        sendAckToActiveWatch(ack)
    }

    func handleRemoteCommand(_ commandString: String, commandId: String) {
        guard let command = RemoteCommand(rawValue: commandString) else {
            let ack = CommandAck(commandId: commandId, status: .error, errorCode: "unknown_command")
            sendAckToActiveWatch(ack)
            return
        }
        handleRemoteCommand(command, commandId: commandId)
    }

    private func sendAckToActiveWatch(_ ack: CommandAck) {
        let preference = devicePreference
        switch preference {
        case .appleWatchPhone, .appleWatchOnly:
            WatchConnectivityManager.shared.sendAck(ack)
        case .garminPhone:
            GarminConnectManager.shared.sendAck(ack)
        case .phoneOnly, .amazfitPhone:
            break
        }
    }

    // MARK: - Background Handling

    private func setupBackgroundHandling() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.beginBackgroundTask()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.endBackgroundTask()
            }
            .store(in: &cancellables)
    }

    private func beginBackgroundTask() {
        guard isActive else { return }

        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }

        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

// MARK: - Formatted Time Helpers

extension WorkoutEngine {
    var formattedRemainingTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedStepProgress: String {
        "\(currentStepIndex + 1) of \(totalSteps)"
    }
}
