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

        setupCurrentStep()
        broadcastState()
        audioCueManager.announceWorkoutStart(workout.name)

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
        guard currentStepIndex < flattenedSteps.count - 1 else {
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
        timer?.invalidate()
        timer = nil
        phase = .ended
        stateVersion += 1
        broadcastState()

        if reason == .completed {
            audioCueManager.announceWorkoutComplete()
        }

        endBackgroundTask()

        // Cleanup after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.reset()
        }
    }

    func reset() {
        phase = .idle
        workout = nil
        flattenedSteps = []
        currentStepIndex = 0
        remainingSeconds = 0
        elapsedSeconds = 0
        stateVersion += 1
    }

    // MARK: - Timer Management

    private func setupCurrentStep() {
        timer?.invalidate()
        timer = nil

        guard let step = currentStep else { return }

        // Announce step
        audioCueManager.announceStep(step.label, roundInfo: step.roundInfo)

        // Setup timer for timed steps
        if let seconds = step.timerSeconds {
            remainingSeconds = seconds
            if phase == .running {
                startTimer()
            }
        } else {
            remainingSeconds = 0
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

    private func broadcastState() {
        let state = buildCurrentState()

        // Send to Watch
        WatchConnectivityManager.shared.sendState(state)

        // Update Live Activity (AMA-85)
        // LiveActivityManager.shared.update(state)
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

        // ACK the command
        let ack = CommandAck(commandId: commandId, status: .success, errorCode: nil)
        WatchConnectivityManager.shared.sendAck(ack)
    }

    func handleRemoteCommand(_ commandString: String, commandId: String) {
        guard let command = RemoteCommand(rawValue: commandString) else {
            let ack = CommandAck(commandId: commandId, status: .error, errorCode: "unknown_command")
            WatchConnectivityManager.shared.sendAck(ack)
            return
        }
        handleRemoteCommand(command, commandId: commandId)
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
