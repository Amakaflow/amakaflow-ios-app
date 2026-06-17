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
    var activityStaleDate: Date? {
        guard isTimedStep, !isPaused, let deadline = stepDeadline else { return nil }
        // 30s buffer: gives the app time to push the next step update before the OS dims the widget.
        return deadline.addingTimeInterval(30)
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
        let authInfo = ActivityAuthorizationInfo()
        print("🔵 Live Activities authorization:")
        print("   - areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")
        print("   - frequentPushesEnabled: \(authInfo.frequentPushesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            print("🔴 Live Activities NOT enabled - enable in Settings → AmakaFlow → Live Activities")
            return
        }

        // Capture current state before clearing; includes orphans from previous processes.
        let trackedActivity = currentActivity
        let allExisting = Array(Activity<WorkoutActivityAttributes>.activities)
        print("🔵 Existing activities count: \(allExisting.count)")
        for activity in allExisting {
            print("   - Activity ID: \(activity.id), state: \(activity.activityState)")
        }
        currentActivity = nil

        let attributes = WorkoutActivityAttributes(workoutId: workoutId, workoutName: workoutName)
        let content = ActivityContent(
            state: initialState,
            staleDate: initialState.activityStaleDate
        )

        print("🔵 Requesting new Live Activity for workout: \(workoutName)")
        print("🔵 Initial state: step=\(initialState.stepName), phase=\(initialState.phase)")

        // AMA-1324: Activity.request() can block the main thread for 2000ms+ via synchronous XPC.
        // Dispatch to background. Teardown and creation run in a SINGLE task to prevent the
        // old-end/new-request race that produced zombie lock-screen activities (issue #308).
        Task.detached {
            // 1. End the previously tracked activity (serialized — must complete before request).
            if let tracked = trackedActivity {
                print("🔵 Ending tracked activity: \(tracked.id)")
                await tracked.end(nil, dismissalPolicy: .immediate)
            }
            // 2. End any orphaned activities from previous process launches.
            for activity in allExisting where activity.id != trackedActivity?.id {
                print("🔵 Ending orphaned activity: \(activity.id)")
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            // 3. All teardown complete — safe to request new activity.
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil  // Local updates only
                )
                await MainActor.run {
                    self.currentActivity = activity
                    print("🟢 Live Activity started successfully! ID: \(activity.id)")
                }
            } catch {
                await MainActor.run {
                    print("🔴 Failed to start Live Activity: \(error)")
                }
            }
        }
    }

    // MARK: - Update Activity

    func updateActivity(state: WorkoutActivityAttributes.ContentState) {
        guard let activity = currentActivity else { return }

        let content = ActivityContent(
            state: state,
            staleDate: state.activityStaleDate
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
            roundInfo: nil,
            stepDeadline: nil
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
