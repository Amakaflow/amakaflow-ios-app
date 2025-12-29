//
//  StandaloneWorkoutEngine.swift
//  AmakaFlowWatch Watch App
//
//  Workout execution engine for standalone watch workouts with HealthKit integration
//

import Combine
import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

@MainActor
final class StandaloneWorkoutEngine: ObservableObject {
    static let shared = StandaloneWorkoutEngine()

    // MARK: - Published State

    @Published private(set) var phase: WorkoutPhase = .idle
    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var workout: Workout?
    @Published private(set) var elapsedSeconds: Int = 0

    // Health metrics (from HealthKitWorkoutManager)
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0

    // MARK: - Flattened Steps

    private(set) var flattenedSteps: [WatchFlattenedInterval] = []

    var currentStep: WatchFlattenedInterval? {
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

    var isActive: Bool {
        phase == .running || phase == .paused
    }

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

    // MARK: - Private

    private var timer: Timer?
    private let healthManager = HealthKitWorkoutManager.shared
    private var workoutStartDate: Date?
    private var averageHeartRateSamples: [Double] = []

    private init() {
        setupHealthKitBindings()
    }

    // MARK: - HealthKit Integration

    private func setupHealthKitBindings() {
        healthManager.onHeartRateUpdate = { [weak self] hr, calories in
            Task { @MainActor in
                self?.heartRate = hr
                self?.activeCalories = calories
                // Track samples for average calculation
                if hr > 0 {
                    self?.averageHeartRateSamples.append(hr)
                }
            }
        }
    }

    // MARK: - Commands

    func start(workout: Workout) async {
        // End any existing session
        if isActive {
            await end(reason: .userEnded)
        }

        self.workout = workout
        self.flattenedSteps = flattenWatchIntervals(workout.intervals)
        self.currentStepIndex = 0
        self.elapsedSeconds = 0
        self.averageHeartRateSamples = []
        self.workoutStartDate = Date()
        self.phase = .running

        print("⌚️ Starting standalone workout: \(workout.name)")
        print("⌚️ Flattened steps count: \(flattenedSteps.count)")

        // Start HealthKit session
        do {
            try await healthManager.startSession(activityType: hkActivityType(for: workout.sport))
            print("⌚️ HealthKit session started")
        } catch {
            print("⌚️ Failed to start HealthKit session: \(error)")
        }

        setupCurrentStep()
        playHaptic(.start)
    }

    func pause() {
        guard phase == .running else { return }

        phase = .paused
        timer?.invalidate()
        timer = nil
        healthManager.pauseSession()
        playHaptic(.stop)
    }

    func resume() {
        guard phase == .paused else { return }

        phase = .running
        startTimer()
        healthManager.resumeSession()
        playHaptic(.start)
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
            Task {
                await end(reason: .completed)
            }
            return
        }

        currentStepIndex += 1
        setupCurrentStep()
        playHaptic(.click)
    }

    func previousStep() {
        guard currentStepIndex > 0 else { return }

        currentStepIndex -= 1
        setupCurrentStep()
        playHaptic(.click)
    }

    func end(reason: EndReason) async {
        print("⌚️ Ending workout with reason: \(reason)")

        timer?.invalidate()
        timer = nil
        phase = .ended

        // End HealthKit session
        await healthManager.endSession()

        if reason == .completed {
            playHaptic(.success)
        }

        // Send summary to phone
        sendWorkoutSummaryToPhone()
    }

    func reset() {
        phase = .idle
        workout = nil
        flattenedSteps = []
        currentStepIndex = 0
        remainingSeconds = 0
        elapsedSeconds = 0
        heartRate = 0
        activeCalories = 0
        averageHeartRateSamples = []
        workoutStartDate = nil
    }

    // MARK: - Timer Management

    private func setupCurrentStep() {
        timer?.invalidate()
        timer = nil

        guard let step = currentStep else {
            print("⌚️ setupCurrentStep: No current step!")
            return
        }

        print("⌚️ setupCurrentStep: \(step.label), timerSeconds: \(step.timerSeconds ?? -1)")

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

        // Haptic for last 3 seconds
        if remainingSeconds <= 3 && remainingSeconds > 0 {
            playHaptic(.click)
        }

        // Auto-advance when timer hits 0
        if remainingSeconds == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.nextStep()
            }
        }
    }

    // MARK: - Workout Summary

    private func sendWorkoutSummaryToPhone() {
        guard let workout = workout,
              let startDate = workoutStartDate else { return }

        let avgHeartRate: Double? = averageHeartRateSamples.isEmpty ? nil :
            averageHeartRateSamples.reduce(0, +) / Double(averageHeartRateSamples.count)

        let summary = StandaloneWorkoutSummary(
            workoutId: workout.id,
            workoutName: workout.name,
            startDate: startDate,
            endDate: Date(),
            durationSeconds: elapsedSeconds,
            totalCalories: activeCalories,
            averageHeartRate: avgHeartRate,
            completedSteps: currentStepIndex + 1,
            totalSteps: flattenedSteps.count
        )

        // Send via WatchConnectivity
        guard let session = WatchConnectivityBridge.shared.session, session.isReachable else {
            print("⌚️ Phone not reachable, can't send summary")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summary)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            session.sendMessage(
                ["action": "workoutSummary", "summary": dict],
                replyHandler: { reply in
                    print("⌚️ Workout summary sent: \(reply)")
                },
                errorHandler: { error in
                    print("⌚️ Failed to send workout summary: \(error)")
                }
            )
        } catch {
            print("⌚️ Failed to encode workout summary: \(error)")
        }
    }

    // MARK: - Helpers

    private func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    private func hkActivityType(for sport: WorkoutSport) -> HKWorkoutActivityType {
        switch sport {
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .strength:
            return .functionalStrengthTraining
        case .mobility:
            return .yoga
        case .swimming:
            return .swimming
        case .cardio:
            return .mixedCardio
        case .other:
            return .other
        }
    }
}

// MARK: - End Reason

enum EndReason {
    case completed
    case userEnded
}

// MARK: - Workout Summary Model

struct StandaloneWorkoutSummary: Codable {
    let workoutId: String
    let workoutName: String
    let startDate: Date
    let endDate: Date
    let durationSeconds: Int
    let totalCalories: Double
    let averageHeartRate: Double?
    let completedSteps: Int
    let totalSteps: Int
}

// MARK: - Watch Flattened Interval

struct WatchFlattenedInterval: Identifiable {
    let id = UUID()
    let interval: WorkoutInterval
    let index: Int
    let label: String
    let details: String
    let roundInfo: String?
    let timerSeconds: Int?
    let stepType: StepType
    let targetReps: Int?

    var formattedTime: String? {
        guard let seconds = timerSeconds else { return nil }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return "\(secs)s"
        }
    }
}

// MARK: - Interval Flattening for Watch

func flattenWatchIntervals(_ intervals: [WorkoutInterval]) -> [WatchFlattenedInterval] {
    var result: [WatchFlattenedInterval] = []
    var counter = 0

    func flatten(_ items: [WorkoutInterval], roundContext: String? = nil) {
        for interval in items {
            switch interval {
            case .repeat(let reps, let subIntervals):
                for i in 1...reps {
                    flatten(subIntervals, roundContext: "Round \(i) of \(reps)")
                }
            default:
                counter += 1
                result.append(WatchFlattenedInterval(
                    interval: interval,
                    index: counter,
                    label: watchIntervalLabel(interval),
                    details: watchIntervalDetails(interval),
                    roundInfo: roundContext,
                    timerSeconds: watchIntervalTimer(interval),
                    stepType: watchIntervalStepType(interval),
                    targetReps: watchIntervalTargetReps(interval)
                ))
            }
        }
    }

    flatten(intervals)
    return result
}

private func watchIntervalLabel(_ interval: WorkoutInterval) -> String {
    switch interval {
    case .warmup:
        return "Warm Up"
    case .cooldown:
        return "Cool Down"
    case .time(_, let target):
        return target ?? "Work"
    case .reps(_, let name, _, _, _):
        return name
    case .distance(let meters, let target):
        return target ?? "\(WorkoutHelpers.formatDistance(meters: meters))"
    case .repeat:
        return "Repeat"
    }
}

private func watchIntervalDetails(_ interval: WorkoutInterval) -> String {
    switch interval {
    case .warmup(let seconds, _),
         .cooldown(let seconds, _),
         .time(let seconds, _):
        return formatWatchSeconds(seconds)
    case .reps(let reps, _, let load, _, _):
        var parts: [String] = ["\(reps) reps"]
        if let load = load {
            parts.append(load)
        }
        return parts.joined(separator: " | ")
    case .distance(let meters, _):
        return WorkoutHelpers.formatDistance(meters: meters)
    case .repeat(let reps, _):
        return "\(reps)x"
    }
}

private func watchIntervalTimer(_ interval: WorkoutInterval) -> Int? {
    switch interval {
    case .warmup(let seconds, _),
         .cooldown(let seconds, _),
         .time(let seconds, _):
        return seconds
    case .reps(_, _, _, let restSec, _):
        return restSec
    case .distance, .repeat:
        return nil
    }
}

private func watchIntervalStepType(_ interval: WorkoutInterval) -> StepType {
    switch interval {
    case .warmup, .cooldown, .time:
        return .timed
    case .reps:
        return .reps
    case .distance:
        return .distance
    case .repeat:
        return .timed
    }
}

private func watchIntervalTargetReps(_ interval: WorkoutInterval) -> Int? {
    switch interval {
    case .reps(let reps, _, _, _, _):
        return reps
    default:
        return nil
    }
}

private func formatWatchSeconds(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let secs = seconds % 60
    if minutes > 0 && secs > 0 {
        return "\(minutes)m \(secs)s"
    } else if minutes > 0 {
        return "\(minutes)m"
    } else {
        return "\(secs)s"
    }
}
