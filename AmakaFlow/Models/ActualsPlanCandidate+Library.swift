//
//  ActualsPlanCandidate+Library.swift
//  AmakaFlow
//
//  AMA-2396: Map match candidates from the user's real Library (not sample fixtures).
//

import Foundation

extension ActualsPlanCandidate {
    /// Build a map candidate from a Library `Workout`.
    static func fromLibrary(_ workout: Workout) -> ActualsPlanCandidate {
        ActualsPlanCandidate(
            id: workout.id,
            title: workout.name,
            sourceLabel: "MY WORKOUTS",
            scheduledStart: nil,
            durationSeconds: TimeInterval(max(workout.duration, estimatedSeconds(from: workout))),
            distanceMeters: nil,
            type: actualsType(from: workout.sport),
            targetAvgHR: nil
        )
    }

    static func fromLibrary(_ workouts: [Workout]) -> [ActualsPlanCandidate] {
        workouts
            .map(fromLibrary)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func actualsType(from sport: WorkoutSport) -> ActualsWorkoutType {
        switch sport {
        case .running: return .run
        case .cycling: return .ride
        case .strength: return .strength
        case .cardio, .conditioning, .mixed, .mobility, .swimming, .other:
            return .other
        }
    }

    /// When wire `duration` is missing/tiny (the ~1 MIN estimator bug), sum block work.
    private static func estimatedSeconds(from workout: Workout) -> Int {
        if workout.duration >= 5 * 60 { return workout.duration }
        var total = 0
        for block in workout.blocks {
            let rounds = max(1, block.rounds)
            var roundSeconds = 0
            for exercise in block.exercises {
                if let sec = exercise.durationSeconds, sec > 0 {
                    roundSeconds += sec
                } else if let reps = Int(exercise.reps ?? ""), reps > 0 {
                    roundSeconds += reps * 3
                }
            }
            total += rounds * roundSeconds
        }
        return max(workout.duration, total)
    }
}
