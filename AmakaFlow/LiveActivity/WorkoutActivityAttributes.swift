//
//  WorkoutActivityAttributes.swift
//  AmakaFlow
//
//  ActivityKit attributes for workout Live Activity (Dynamic Island)
//

@preconcurrency import ActivityKit
import Foundation

nonisolated struct WorkoutActivityAttributes: ActivityAttributes, Sendable {
    // Static content (doesn't change during activity)
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var phase: String              // "running", "paused", "ended"
        var stepName: String           // "Squat", "Rest", "Warm Up"
        var stepIndex: Int             // Current step (1-based for display)
        var stepCount: Int             // Total steps
        var remainingSeconds: Int      // Countdown (0 if reps-based); used for paused/reps display
        var stepType: String           // "timed", "reps", "distance"
        var roundInfo: String?         // "Round 2/4" if in repeat block
        var stepDeadline: Date?        // Absolute Date when countdown reaches 0; drives Text(timerInterval:)
    }

    // Fixed for lifetime of activity
    var workoutId: String
    var workoutName: String
}

// MARK: - ContentState Helpers

extension WorkoutActivityAttributes.ContentState {
    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var progressPercent: Double {
        guard stepCount > 0 else { return 0 }
        return Double(stepIndex) / Double(stepCount)
    }

    var isTimedStep: Bool {
        stepType == "timed"
    }

    var isPaused: Bool {
        phase == "paused"
    }

    /// The date after which ActivityKit should dim the Live Activity as stale.
    /// Only set for timed, running steps with a known deadline; nil otherwise keeps the activity fresh.
    nonisolated var activityStaleDate: Date? {
        guard stepType == "timed", phase != "paused", let deadline = stepDeadline else { return nil }
        // 30s buffer: gives the app time to push the next step update before the OS dims the widget.
        return deadline.addingTimeInterval(30)
    }
}
