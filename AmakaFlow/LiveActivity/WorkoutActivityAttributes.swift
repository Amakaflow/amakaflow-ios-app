//
//  WorkoutActivityAttributes.swift
//  AmakaFlow
//
//  ActivityKit attributes for workout Live Activity (Dynamic Island)
//  This is a stub for AMA-85 implementation
//

import Foundation
import ActivityKit

struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic data that changes during the workout
        var stepName: String
        var stepIndex: Int
        var totalSteps: Int
        var remainingSeconds: Int?
        var isPaused: Bool
        var roundInfo: String?
    }

    // Static data that doesn't change during the workout
    var workoutId: String
    var workoutName: String
}

// MARK: - Live Activity Manager (Stub for AMA-85)

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<WorkoutActivityAttributes>?

    private init() {}

    // MARK: - Start Activity

    func startActivity(for workout: Workout) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }

        let attributes = WorkoutActivityAttributes(
            workoutId: workout.id,
            workoutName: workout.name
        )

        let initialState = WorkoutActivityAttributes.ContentState(
            stepName: "",
            stepIndex: 0,
            totalSteps: workout.intervalCount,
            remainingSeconds: nil,
            isPaused: false,
            roundInfo: nil
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            print("Started Live Activity: \(currentActivity?.id ?? "unknown")")
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    // MARK: - Update Activity

    func update(state: WorkoutState) {
        guard let activity = currentActivity else { return }

        let contentState = WorkoutActivityAttributes.ContentState(
            stepName: state.stepName,
            stepIndex: state.stepIndex,
            totalSteps: state.stepCount,
            remainingSeconds: state.remainingMs.map { $0 / 1000 },
            isPaused: state.phase == .paused,
            roundInfo: state.roundInfo
        )

        Task {
            await activity.update(
                ActivityContent(
                    state: contentState,
                    staleDate: Date().addingTimeInterval(60)
                )
            )
        }
    }

    // MARK: - End Activity

    func endActivity(reason: EndReason) {
        guard let activity = currentActivity else { return }

        let finalState = WorkoutActivityAttributes.ContentState(
            stepName: reason == .completed ? "Complete!" : "Ended",
            stepIndex: 0,
            totalSteps: 0,
            remainingSeconds: nil,
            isPaused: false,
            roundInfo: nil
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 5)
            )
            currentActivity = nil
        }
    }
}
