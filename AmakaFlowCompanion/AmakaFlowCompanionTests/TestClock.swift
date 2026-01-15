//
//  TestClock.swift
//  AmakaFlowCompanionTests
//
//  Deterministic clock for testing WorkoutEngine timing behavior.
//  Allows tests to control time progression without real delays.
//
//  Part of AMA-349: Test Infrastructure
//

import Foundation
@testable import AmakaFlowCompanion

/// Test clock that allows deterministic control of time progression
/// Use this in tests to verify timing behavior without real delays.
///
/// Usage:
/// ```swift
/// let clock = TestClock()
/// let engine = WorkoutEngine(clock: clock, ...)
/// engine.start(workout: workout)
///
/// // Advance time by 10 seconds, firing any scheduled callbacks
/// await clock.advance(by: 10)
///
/// XCTAssertEqual(engine.elapsedSeconds, 10)
/// ```
@MainActor
final class TestClock: WorkoutClock {
    // MARK: - State

    /// Current virtual time
    private var virtualTime: Date

    /// Scheduled timer callbacks with their intervals
    private var timerCallback: (@MainActor () -> Void)?
    private var timerInterval: TimeInterval = 0

    /// Track pending async sleeps for coordination
    private var sleepContinuations: [CheckedContinuation<Void, Never>] = []

    // MARK: - Call Tracking

    /// Number of times scheduleTimer was called
    var scheduleTimerCallCount = 0

    /// Number of times invalidateTimer was called
    var invalidateTimerCallCount = 0

    /// Number of times sleep was called
    var sleepCallCount = 0

    /// Total seconds slept
    var totalSleptSeconds: TimeInterval = 0

    // MARK: - WorkoutClock Protocol

    var now: Date {
        virtualTime
    }

    let speedMultiplier: Double = 1.0

    // MARK: - Initialization

    init(startTime: Date = Date()) {
        self.virtualTime = startTime
    }

    // MARK: - Timer Management

    func scheduleTimer(interval: TimeInterval, callback: @escaping @MainActor () -> Void) {
        scheduleTimerCallCount += 1
        timerCallback = callback
        timerInterval = interval
    }

    func invalidateTimer() {
        invalidateTimerCallCount += 1
        timerCallback = nil
        timerInterval = 0
    }

    func sleep(for seconds: TimeInterval) async {
        sleepCallCount += 1
        totalSleptSeconds += seconds

        // Advance virtual time immediately (no real delay in tests)
        virtualTime = virtualTime.addingTimeInterval(seconds)

        // Allow test to optionally block and manually advance
        // For now, we complete immediately
    }

    // MARK: - Test Control

    /// Advance virtual time by the specified number of seconds,
    /// firing any scheduled timer callbacks at the appropriate intervals.
    ///
    /// Example: If timer interval is 1 second and you advance by 10 seconds,
    /// the timer callback will fire 10 times.
    ///
    /// - Parameter seconds: Number of seconds to advance
    func advance(by seconds: TimeInterval) {
        guard seconds > 0 else { return }

        if let callback = timerCallback, timerInterval > 0 {
            // Calculate how many timer ticks should fire
            let ticks = Int(seconds / timerInterval)

            for _ in 0..<ticks {
                virtualTime = virtualTime.addingTimeInterval(timerInterval)
                callback()
            }

            // Handle any remaining fractional time
            let remainder = seconds.truncatingRemainder(dividingBy: timerInterval)
            if remainder > 0 {
                virtualTime = virtualTime.addingTimeInterval(remainder)
            }
        } else {
            // No timer active, just advance time
            virtualTime = virtualTime.addingTimeInterval(seconds)
        }
    }

    /// Advance time by exactly one timer tick and fire the callback
    /// Useful for stepping through timer behavior one tick at a time
    func tick() {
        guard let callback = timerCallback, timerInterval > 0 else { return }

        virtualTime = virtualTime.addingTimeInterval(timerInterval)
        callback()
    }

    /// Reset all state for reuse between tests
    func reset() {
        timerCallback = nil
        timerInterval = 0
        scheduleTimerCallCount = 0
        invalidateTimerCallCount = 0
        sleepCallCount = 0
        totalSleptSeconds = 0
        virtualTime = Date()
        sleepContinuations.removeAll()
    }

    // MARK: - Test Helpers

    /// Whether a timer is currently scheduled
    var hasActiveTimer: Bool {
        timerCallback != nil && timerInterval > 0
    }

    /// The current timer interval, or nil if no timer is active
    var currentTimerInterval: TimeInterval? {
        hasActiveTimer ? timerInterval : nil
    }
}
