//
//  WorkoutClock.swift
//  AmakaFlow
//
//  Clock abstraction for workout timing - enables simulation mode with accelerated time.
//  Part of AMA-271: Workout Simulation Mode
//

import Foundation

// MARK: - Clock Protocol

/// Abstraction over time for workout execution
/// Allows swapping real time for accelerated simulation time
protocol WorkoutClock: AnyObject {
    /// Current timestamp
    var now: Date { get }

    /// Speed multiplier (1.0 = real-time)
    var speedMultiplier: Double { get }

    /// Schedule a repeating timer callback
    /// - Parameters:
    ///   - interval: Base interval in seconds (will be divided by speedMultiplier)
    ///   - callback: Called on each tick (on MainActor)
    func scheduleTimer(interval: TimeInterval, callback: @escaping @MainActor () -> Void)

    /// Invalidate the current timer
    func invalidateTimer()

    /// Sleep for a duration (adjusted by speed multiplier)
    func sleep(for seconds: TimeInterval) async
}

// MARK: - Real Clock (Production)

/// Production clock - uses real system time
@MainActor
final class RealClock: WorkoutClock {
    private var timer: Timer?

    var now: Date { Date() }

    let speedMultiplier: Double = 1.0

    func scheduleTimer(interval: TimeInterval, callback: @escaping @MainActor () -> Void) {
        invalidateTimer()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                callback()
            }
        }

        // Ensure timer fires during scroll
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    func sleep(for seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Accelerated Clock (Simulation)

/// Accelerated clock for simulation mode
/// Time passes faster by the specified multiplier
@MainActor
final class AcceleratedClock: WorkoutClock {
    let speedMultiplier: Double
    private var virtualTime: Date
    private var timerSource: DispatchSourceTimer?

    /// Create an accelerated clock
    /// - Parameters:
    ///   - speedMultiplier: How much faster time should pass (e.g., 10.0 = 10x speed)
    ///   - startTime: Starting timestamp (defaults to now)
    init(speedMultiplier: Double, startTime: Date = Date()) {
        self.speedMultiplier = max(1.0, speedMultiplier) // Minimum 1x speed
        self.virtualTime = startTime
    }

    var now: Date {
        virtualTime
    }

    func scheduleTimer(interval: TimeInterval, callback: @escaping @MainActor () -> Void) {
        invalidateTimer()

        // Divide interval by speed multiplier for faster ticks
        let acceleratedInterval = interval / speedMultiplier

        // Use DispatchSource timer for reliable firing (more robust than Timer)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + acceleratedInterval, repeating: acceleratedInterval)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Advance virtual time by the full interval (not accelerated)
            self.virtualTime = self.virtualTime.addingTimeInterval(interval)
            // Call callback - we're already on main queue
            callback()
        }
        source.resume()
        timerSource = source
    }

    func invalidateTimer() {
        timerSource?.cancel()
        timerSource = nil
    }

    func sleep(for seconds: TimeInterval) async {
        // Sleep for less real time, but advance virtual time fully
        let realSleepTime = seconds / speedMultiplier
        try? await Task.sleep(nanoseconds: UInt64(realSleepTime * 1_000_000_000))
        virtualTime = virtualTime.addingTimeInterval(seconds)
    }
}
