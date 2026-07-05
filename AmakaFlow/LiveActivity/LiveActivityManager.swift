//
//  LiveActivityManager.swift
//  AmakaFlow
//
//  Starts/updates/ends workout Live Activities. ActivityKit XPC work runs
//  off the main actor (AMA-1324); only currentActivity bookkeeping is
//  main-actor bound (AMA-2273 / Swift 6).
//

@preconcurrency import ActivityKit
import Foundation

/// ActivityKit work runs off the main actor (AMA-1324); only `currentActivity`
/// bookkeeping is main-actor bound so SwiftUI callers stay simple.
nonisolated final class LiveActivityManager {
    static let shared = LiveActivityManager()

    @MainActor private var currentActivity: Activity<WorkoutActivityAttributes>?
    private var startTask: Task<Void, Never>?

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

        let staleDate = initialState.activityStaleDate
        let attributes = WorkoutActivityAttributes(workoutId: workoutId, workoutName: workoutName)
        let content = ActivityContent(state: initialState, staleDate: staleDate)

        print("🔵 Requesting new Live Activity for workout: \(workoutName)")
        print("🔵 Initial state: step=\(initialState.stepName), phase=\(initialState.phase)")

        // AMA-1324: Activity.request() can block the main thread for 2000ms+ via synchronous XPC.
        // Dispatch to background. Teardown and creation run in a SINGLE task to prevent the
        // old-end/new-request race that produced zombie lock-screen activities (issue #308).
        let previousStartTask = startTask
        startTask = Task.detached { [weak self] in
            guard let self else { return }
            await previousStartTask?.value

            let trackedActivity = await self.currentActivity
            let allExisting = Array(Activity<WorkoutActivityAttributes>.activities)
            print("🔵 Existing activities count: \(allExisting.count)")
            for activity in allExisting {
                print("   - Activity ID: \(activity.id), state: \(activity.activityState)")
            }
            await MainActor.run { self.currentActivity = nil }

            if let tracked = trackedActivity {
                print("🔵 Ending tracked activity: \(tracked.id)")
                await tracked.end(nil, dismissalPolicy: .immediate)
            }
            for activity in allExisting where activity.id != trackedActivity?.id {
                print("🔵 Ending orphaned activity: \(activity.id)")
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                await MainActor.run {
                    self.currentActivity = activity
                    print("🟢 Live Activity started successfully! ID: \(activity.id)")
                }
            } catch {
                print("🔴 Failed to start Live Activity: \(error)")
            }
        }
    }

    // MARK: - Update Activity

    func updateActivity(state: WorkoutActivityAttributes.ContentState) {
        let staleDate = state.activityStaleDate
        let content = ActivityContent(state: state, staleDate: staleDate)
        Task { @MainActor in
            guard let activity = self.currentActivity else { return }
            await activity.update(content)
        }
    }

    // MARK: - End Activity

    @MainActor
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
