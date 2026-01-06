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

    // Rest state
    @Published private(set) var restRemainingSeconds: Int = 0
    @Published private(set) var isManualRest: Bool = false

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
        phase == .running || phase == .paused || phase == .resting
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

    var formattedRestTime: String {
        let minutes = restRemainingSeconds / 60
        let seconds = restRemainingSeconds % 60
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

        // Reset all state for fresh start
        timer?.invalidate()
        timer = nil
        self.workout = workout
        self.flattenedSteps = flattenWatchIntervals(workout.intervals)
        self.currentStepIndex = 0
        self.remainingSeconds = 0
        self.elapsedSeconds = 0
        self.restRemainingSeconds = 0
        self.isManualRest = false
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
        case .idle, .ended, .resting:
            break
        }
    }

    func nextStep() {
        // Check if current step has rest after it
        if let currentStep = currentStep, currentStep.hasRestAfter, phase != .resting {
            enterRestPhase(restSeconds: currentStep.restAfterSeconds)
            return
        }

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

    /// Enter the rest phase between exercises
    private func enterRestPhase(restSeconds: Int?) {
        print("⌚️ Entering rest phase. restSeconds: \(restSeconds ?? -1)")

        timer?.invalidate()
        timer = nil

        phase = .resting

        if let seconds = restSeconds, seconds > 0 {
            // Timed rest
            isManualRest = false
            restRemainingSeconds = seconds
            startRestTimer()
        } else {
            // Manual rest (nil or 0 treated as manual "tap when ready")
            isManualRest = true
            restRemainingSeconds = 0
        }

        playHaptic(.stop)
    }

    private func startRestTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.restTimerTick()
            }
        }
    }

    private func restTimerTick() {
        guard restRemainingSeconds > 0 else {
            completeRest()
            return
        }

        restRemainingSeconds -= 1
        elapsedSeconds += 1

        // Haptic for last 3 seconds
        if restRemainingSeconds <= 3 && restRemainingSeconds > 0 {
            playHaptic(.click)
        }

        // Auto-advance when timer hits 0
        if restRemainingSeconds == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.completeRest()
            }
        }
    }

    /// Complete the rest phase and advance to the next step
    func completeRest() {
        guard phase == .resting else { return }

        print("⌚️ Completing rest, advancing to next step")

        timer?.invalidate()
        timer = nil
        restRemainingSeconds = 0
        isManualRest = false

        // Check if there are more steps
        guard currentStepIndex < flattenedSteps.count - 1 else {
            print("⌚️ No more steps after rest! Ending workout.")
            Task {
                await end(reason: .completed)
            }
            return
        }

        currentStepIndex += 1
        phase = .running
        setupCurrentStep()
        playHaptic(.start)
    }

    /// Skip the current rest period and advance immediately
    func skipRest() {
        guard phase == .resting else { return }
        completeRest()
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
        restRemainingSeconds = 0
        isManualRest = false
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
    let setNumber: Int?      // Current set number (1-based)
    let totalSets: Int?      // Total number of sets
    let hasRestAfter: Bool   // Whether this step has a rest period after it
    let restAfterSeconds: Int?  // Rest duration: nil = manual (tap when ready), 0 = no rest, >0 = timed countdown

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

    /// Formatted rest duration for display
    var formattedRestTime: String? {
        guard let seconds = restAfterSeconds, seconds > 0 else { return nil }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return "\(secs)s"
        }
    }

    /// Display label including set info if applicable
    var displayLabel: String {
        if let setNum = setNumber, let total = totalSets, total > 1 {
            return "\(label) - Set \(setNum) of \(total)"
        }
        return label
    }
}

// MARK: - Interval Flattening for Watch

func flattenWatchIntervals(_ intervals: [WorkoutInterval]) -> [WatchFlattenedInterval] {
    var result: [WatchFlattenedInterval] = []
    var counter = 0

    print("⌚️ flattenWatchIntervals: Processing \(intervals.count) intervals")

    func flatten(_ items: [WorkoutInterval], roundContext: String? = nil) {
        for interval in items {
            switch interval {
            case .repeat(let repeatCount, let subIntervals):
                print("⌚️ Processing repeat: \(repeatCount)x with \(subIntervals.count) sub-intervals")

                // Check if this is a "sets-style" repeat (single reps interval inside)
                let isSetsStyleRepeat = subIntervals.count == 1 && {
                    if case .reps = subIntervals[0] { return true }
                    return false
                }()

                if isSetsStyleRepeat, case .reps(_, let reps, let name, let load, let restSec, _) = subIntervals[0] {
                    // Handle sets-style repeat directly - create exercise steps with rest info
                    for i in 1...repeatCount {
                        counter += 1

                        // All sets have rest after them (for transition between sets or to next exercise)
                        // restSec: nil = manual, 0 = no rest, >0 = timed
                        let hasRest = restSec != 0  // Has rest unless explicitly 0

                        result.append(WatchFlattenedInterval(
                            interval: subIntervals[0],
                            index: counter,
                            label: name,
                            details: watchDetailsForSet(reps: reps, load: load, setNum: i, totalSets: repeatCount),
                            roundInfo: "Set \(i) of \(repeatCount)",
                            timerSeconds: nil, // Reps are not timed
                            stepType: .reps,
                            targetReps: reps,
                            setNumber: i,
                            totalSets: repeatCount,
                            hasRestAfter: hasRest,
                            restAfterSeconds: restSec
                        ))
                    }
                } else {
                    // Regular repeat - process sub-intervals for each round
                    for i in 1...repeatCount {
                        let roundContext = "Round \(i) of \(repeatCount)"
                        flatten(subIntervals, roundContext: roundContext)
                    }
                }

            case .reps(let sets, let reps, let name, let load, let restSec, _):
                print("⌚️ Processing reps: \(name), sets=\(sets ?? -1), reps=\(reps), restSec=\(restSec ?? -999)")
                let totalSets = sets ?? 1

                for setNum in 1...totalSets {
                    counter += 1

                    // Has rest after all sets except the last one (within a direct .reps block)
                    // restSec: nil = manual, 0 = no rest, >0 = timed
                    let hasRest = setNum < totalSets && restSec != 0

                    result.append(WatchFlattenedInterval(
                        interval: interval,
                        index: counter,
                        label: name,
                        details: watchDetailsForSet(reps: reps, load: load, setNum: setNum, totalSets: totalSets),
                        roundInfo: roundContext,
                        timerSeconds: nil, // Reps are not timed
                        stepType: .reps,
                        targetReps: reps,
                        setNumber: setNum,
                        totalSets: totalSets,
                        hasRestAfter: hasRest,
                        restAfterSeconds: hasRest ? restSec : nil
                    ))
                }

            default:
                counter += 1
                // Cooldown shouldn't have rest after (it ends the workout)
                // All other steps (warmup, time, distance) get manual rest after
                let isCooldown: Bool = {
                    if case .cooldown = interval { return true }
                    return false
                }()

                result.append(WatchFlattenedInterval(
                    interval: interval,
                    index: counter,
                    label: watchIntervalLabel(interval),
                    details: watchIntervalDetails(interval),
                    roundInfo: roundContext,
                    timerSeconds: watchIntervalTimer(interval),
                    stepType: watchIntervalStepType(interval),
                    targetReps: watchIntervalTargetReps(interval),
                    setNumber: nil,
                    totalSets: nil,
                    hasRestAfter: !isCooldown,  // All steps except cooldown have rest
                    restAfterSeconds: isCooldown ? nil : nil  // nil = manual rest
                ))
            }
        }
    }

    flatten(intervals)
    print("⌚️ flattenWatchIntervals: Created \(result.count) flattened steps")
    for (i, step) in result.enumerated() {
        print("⌚️   Step \(i+1): \(step.label), hasRest=\(step.hasRestAfter), restSec=\(step.restAfterSeconds ?? -1), set=\(step.setNumber ?? 0)/\(step.totalSets ?? 0)")
    }
    return result
}

/// Helper to create details string for a specific set (Watch version)
private func watchDetailsForSet(reps: Int, load: String?, setNum: Int, totalSets: Int) -> String {
    var parts: [String] = ["\(reps) reps"]
    if let load = load {
        parts.append(load)
    }
    if totalSets > 1 {
        parts.append("Set \(setNum)/\(totalSets)")
    }
    return parts.joined(separator: " | ")
}

private func watchIntervalLabel(_ interval: WorkoutInterval) -> String {
    switch interval {
    case .warmup:
        return "Warm Up"
    case .cooldown:
        return "Cool Down"
    case .time(_, let target):
        return target ?? "Work"
    case .reps(_, _, let name, _, _, _):
        return name
    case .distance(let meters, let target):
        return target ?? "\(WorkoutHelpers.formatDistance(meters: meters))"
    case .repeat:
        return "Repeat"
    case .rest:
        return "Rest"
    }
}

private func watchIntervalDetails(_ interval: WorkoutInterval) -> String {
    switch interval {
    case .warmup(let seconds, _),
         .cooldown(let seconds, _),
         .time(let seconds, _):
        return formatWatchSeconds(seconds)
    case .reps(_, let reps, _, let load, _, _):
        var parts: [String] = ["\(reps) reps"]
        if let load = load {
            parts.append(load)
        }
        return parts.joined(separator: " | ")
    case .distance(let meters, _):
        return WorkoutHelpers.formatDistance(meters: meters)
    case .repeat(let reps, _):
        return "\(reps)x"
    case .rest(let seconds):
        if let secs = seconds {
            return formatWatchSeconds(secs)
        } else {
            return "Tap when ready"
        }
    }
}

private func watchIntervalTimer(_ interval: WorkoutInterval) -> Int? {
    switch interval {
    case .warmup(let seconds, _),
         .cooldown(let seconds, _),
         .time(let seconds, _):
        return seconds
    case .reps(_, _, _, _, let restSec, _):
        return restSec
    case .distance, .repeat:
        return nil
    case .rest(let seconds):
        return seconds
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
    case .rest:
        return .rest
    }
}

private func watchIntervalTargetReps(_ interval: WorkoutInterval) -> Int? {
    switch interval {
    case .reps(_, let reps, _, _, _, _):
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
