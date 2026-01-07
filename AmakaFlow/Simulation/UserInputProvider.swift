//
//  UserInputProvider.swift
//  AmakaFlow
//
//  Abstraction for user input during workouts - enables auto-advance in simulation mode.
//  Part of AMA-271: Workout Simulation Mode
//

import Foundation

// MARK: - User Input Provider Protocol

/// Abstraction over user input for workout execution
/// Allows swapping real user taps for simulated auto-advance
@MainActor
protocol UserInputProvider: AnyObject {
    /// Wait for user to tap "next" or advance button
    func waitForNextTap() async

    /// Wait for user to complete reps and return logged count
    /// - Parameter target: Target number of reps
    /// - Returns: Actual reps completed (may vary slightly in simulation)
    func waitForRepsInput(target: Int) async -> Int

    /// Wait for user to tap "ready" after rest
    func waitForReadyTap() async

    /// Check if user should pause (simulation can inject random pauses)
    func shouldPause() -> Bool

    /// Check if user should skip current step
    func shouldSkip() -> Bool

    /// Called when user actually taps next (for real input provider)
    func userDidTapNext()

    /// Called when user completes reps
    func userDidCompleteReps(_ count: Int)

    /// Called when user taps ready
    func userDidTapReady()
}

// MARK: - Real User Input (Production)

/// Production user input - waits for actual user interaction
@MainActor
final class RealUserInput: UserInputProvider {
    private var nextTapContinuation: CheckedContinuation<Void, Never>?
    private var repsContinuation: CheckedContinuation<Int, Never>?
    private var readyContinuation: CheckedContinuation<Void, Never>?

    func waitForNextTap() async {
        await withCheckedContinuation { continuation in
            self.nextTapContinuation = continuation
        }
    }

    func waitForRepsInput(target: Int) async -> Int {
        await withCheckedContinuation { continuation in
            self.repsContinuation = continuation
        }
    }

    func waitForReadyTap() async {
        await withCheckedContinuation { continuation in
            self.readyContinuation = continuation
        }
    }

    func shouldPause() -> Bool {
        // Real users control their own pauses
        false
    }

    func shouldSkip() -> Bool {
        // Real users decide when to skip
        false
    }

    func userDidTapNext() {
        nextTapContinuation?.resume()
        nextTapContinuation = nil
    }

    func userDidCompleteReps(_ count: Int) {
        repsContinuation?.resume(returning: count)
        repsContinuation = nil
    }

    func userDidTapReady() {
        readyContinuation?.resume()
        readyContinuation = nil
    }
}

// MARK: - Simulated User Input

/// Simulated user input - auto-advances with realistic delays based on behavior profile
@MainActor
final class SimulatedUserInput: UserInputProvider {
    private let clock: WorkoutClock
    private let profile: UserBehaviorProfile

    init(clock: WorkoutClock, profile: UserBehaviorProfile) {
        self.clock = clock
        self.profile = profile
    }

    func waitForNextTap() async {
        // Simulate reaction time delay
        let delay = Double.random(in: profile.reactionTime)
        await clock.sleep(for: delay)
    }

    func waitForRepsInput(target: Int) async -> Int {
        // Simulate time to complete reps and tap
        let delay = Double.random(in: profile.reactionTime)
        await clock.sleep(for: delay)

        // Slight variance in logged reps (sometimes user does +/- 1)
        let variance = Int.random(in: -1...1)
        return max(1, target + variance)
    }

    func waitForReadyTap() async {
        // Simulate variable rest time based on profile
        let baseRest = 60.0  // Default rest if not specified
        let multiplier = Double.random(in: profile.restTimeMultiplier)
        let actualRest = baseRest * multiplier
        await clock.sleep(for: actualRest)
    }

    func shouldPause() -> Bool {
        // Randomly decide to pause based on profile probability
        Double.random(in: 0...1) < profile.pauseProbability
    }

    func shouldSkip() -> Bool {
        // Randomly decide to skip based on profile probability
        Double.random(in: 0...1) < profile.skipProbability
    }

    // These are no-ops for simulated input
    func userDidTapNext() {}
    func userDidCompleteReps(_ count: Int) {}
    func userDidTapReady() {}
}
