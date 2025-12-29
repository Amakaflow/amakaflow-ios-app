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

@MainActor
class WorkoutEngine: ObservableObject {
    static let shared = WorkoutEngine()

    // MARK: - Published State

    @Published private(set) var phase: WorkoutPhase = .idle
    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var workout: Workout?
    @Published private(set) var stateVersion: Int = 0
    @Published private(set) var elapsedSeconds: Int = 0

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
        phase == .running || phase == .paused
    }

    // MARK: - Private

    private var timer: Timer?
    private var audioCueManager = AudioCueManager()
    private var cancellables = Set<AnyCancellable>()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var workoutStartTime: Date?

    private init() {
        setupBackgroundHandling()
    }

    // MARK: - Commands

    func start(workout: Workout) {
        // End any existing session
        if isActive {
            end(reason: .userEnded)
        }

        self.workout = workout
        self.flattenedSteps = flattenIntervals(workout.intervals)
        self.currentStepIndex = 0
        self.elapsedSeconds = 0
        self.phase = .running
        self.stateVersion += 1
        self.workoutStartTime = Date()

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

    func pause() {
        guard phase == .running else { return }

        phase = .paused
        timer?.invalidate()
        timer = nil
        stateVersion += 1
        broadcastState()
        audioCueManager.announcePaused()
    }

    func resume() {
        guard phase == .paused else { return }

        phase = .running
        startTimer()
        stateVersion += 1
        broadcastState()
        audioCueManager.announceResumed()
    }

    func togglePlayPause() {
        switch phase {
        case .running:
            pause()
        case .paused:
            resume()
        case .idle, .ended:
            break
        }
    }

    func nextStep() {
        print("🏋️ nextStep() called. currentStepIndex: \(currentStepIndex), flattenedSteps.count: \(flattenedSteps.count)")
        guard currentStepIndex < flattenedSteps.count - 1 else {
            print("🏋️ No more steps! Ending workout.")
            end(reason: .completed)
            return
        }

        currentStepIndex += 1
        setupCurrentStep()
        stateVersion += 1
        broadcastState()
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

        // Capture workout data before resetting state
        let workoutData = (
            id: workout?.id,
            name: workout?.name,
            startTime: workoutStartTime,
            duration: elapsedSeconds
        )

        timer?.invalidate()
        timer = nil
        phase = .ended
        stateVersion += 1
        broadcastState()

        if reason == .completed {
            audioCueManager.announceWorkoutComplete()
        }

        // Post workout completion to API
        postWorkoutCompletion(
            workoutId: workoutData.id,
            workoutName: workoutData.name,
            startedAt: workoutData.startTime,
            durationSeconds: workoutData.duration
        )

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
        timer?.invalidate()
        timer = nil

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
    }

    // MARK: - Workout Completion

    private func postWorkoutCompletion(
        workoutId: String?,
        workoutName: String?,
        startedAt: Date?,
        durationSeconds: Int
    ) {
        guard let workoutId = workoutId,
              let startedAt = startedAt else {
            print("🏋️ Cannot post completion - missing workout ID or start time")
            return
        }

        let endedAt = Date()

        // Get health metrics from connected watch if available
        let avgHeartRate: Int? = nil  // Will be populated when we integrate with HealthKit
        let activeCalories: Int? = {
            let watchCals = WatchConnectivityManager.shared.watchActiveCalories
            return watchCals > 0 ? Int(watchCals) : nil
        }()

        Task {
            do {
                _ = try await WorkoutCompletionService.shared.postPhoneWorkoutCompletion(
                    workoutId: workoutId,
                    workoutName: workoutName ?? "Workout",
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: durationSeconds,
                    avgHeartRate: avgHeartRate,
                    activeCalories: activeCalories
                )
                print("🏋️ Workout completion posted successfully")
            } catch {
                print("🏋️ Failed to post workout completion: \(error)")
                // Error is already logged and queued for retry by WorkoutCompletionService
            }
        }
    }

    // MARK: - Timer Management

    private func setupCurrentStep() {
        timer?.invalidate()
        timer = nil

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
        } else {
            remainingSeconds = 0
            print("🏋️ No timer for this step (reps/distance)")
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timerTick()
            }
        }
        // Make sure timer fires even during scroll
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func timerTick() {
        elapsedSeconds += 1

        guard remainingSeconds > 0 else {
            // For reps-based steps, don't auto-advance
            if currentStep?.stepType == .reps {
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
        let preference = devicePreference

        // Send to appropriate watch based on device preference
        switch preference {
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
