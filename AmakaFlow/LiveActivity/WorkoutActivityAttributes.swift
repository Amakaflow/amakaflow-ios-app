//
//  WorkoutActivityAttributes.swift
//  AmakaFlow
//
//  ActivityKit attributes for workout Live Activity (Dynamic Island)
//

import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    // Static content (doesn't change during activity)
    public struct ContentState: Codable, Hashable {
        var phase: String              // "running", "paused", "ended"
        var stepName: String           // "Squat", "Rest", "Warm Up"
        var stepIndex: Int             // Current step (1-based for display)
        var stepCount: Int             // Total steps
        var remainingSeconds: Int      // Countdown (0 if reps-based)
        var stepType: String           // "timed", "reps", "distance"
        var roundInfo: String?         // "Round 2/4" if in repeat block
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
}

// MARK: - Live Activity Manager

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<WorkoutActivityAttributes>?

    private init() {}

    // MARK: - Start Activity

    func startActivity(
        workoutId: String,
        workoutName: String,
        initialState: WorkoutActivityAttributes.ContentState
    ) {
        // Check if Live Activities are enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("🔴 Live Activities not enabled")
            return
        }

        // End any existing activity first
        Task {
            await endActivity()
        }

        let attributes = WorkoutActivityAttributes(
            workoutId: workoutId,
            workoutName: workoutName
        )

        let content = ActivityContent(
            state: initialState,
            staleDate: nil
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil  // Local updates only
            )
            print("🟢 Live Activity started: \(currentActivity?.id ?? "unknown")")
        } catch {
            print("🔴 Failed to start Live Activity: \(error)")
        }
    }

    // MARK: - Update Activity

    func updateActivity(state: WorkoutActivityAttributes.ContentState) {
        guard let activity = currentActivity else { return }

        let content = ActivityContent(
            state: state,
            staleDate: nil
        )

        Task {
            await activity.update(content)
        }
    }

    // MARK: - End Activity

    func endActivity() async {
        guard let activity = currentActivity else { return }

        let finalState = WorkoutActivityAttributes.ContentState(
            phase: "ended",
            stepName: "Workout Complete",
            stepIndex: 0,
            stepCount: 0,
            remainingSeconds: 0,
            stepType: "reps",
            roundInfo: nil
        )

        let content = ActivityContent(
            state: finalState,
            staleDate: nil
        )

        await activity.end(content, dismissalPolicy: .after(.now + 5))
        currentActivity = nil
        print("🟢 Live Activity ended")
    }
}
