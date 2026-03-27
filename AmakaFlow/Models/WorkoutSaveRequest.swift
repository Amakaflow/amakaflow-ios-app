//
//  WorkoutSaveRequest.swift
//  AmakaFlow
//
//  Request model for POST /workouts/save
//

import Foundation

/// Represents a single interval in a workout save request
struct WorkoutSaveInterval: Codable {
    var type: String  // "reps", "time", "warmup", "cooldown", "distance", "rest"
    var name: String?
    var sets: Int?
    var reps: Int?
    var seconds: Int?
    var meters: Int?
    var restSeconds: Int?
    var load: String?
    var target: String?
}

/// Request body for POST /workouts/save
struct WorkoutSaveRequest: Codable {
    var name: String
    var sport: String
    var intervals: [WorkoutSaveInterval]

    /// Convert from existing Workout model for edit mode
    static func from(workout: Workout) -> WorkoutSaveRequest {
        WorkoutSaveRequest(
            name: workout.name,
            sport: workout.sport.rawValue,
            intervals: workout.intervals.map { interval in
                switch interval {
                case .warmup(let seconds, let target):
                    return WorkoutSaveInterval(type: "warmup", seconds: seconds, target: target)
                case .cooldown(let seconds, let target):
                    return WorkoutSaveInterval(type: "cooldown", seconds: seconds, target: target)
                case .time(let seconds, let target):
                    return WorkoutSaveInterval(type: "time", seconds: seconds, target: target)
                case .reps(let sets, let reps, let name, let load, let restSec, _):
                    return WorkoutSaveInterval(type: "reps", name: name, sets: sets, reps: reps, restSeconds: restSec, load: load)
                case .distance(let meters, let target):
                    return WorkoutSaveInterval(type: "distance", meters: meters, target: target)
                case .rest(let seconds):
                    return WorkoutSaveInterval(type: "rest", seconds: seconds)
                case .repeat(_, _):
                    // Flatten repeat groups for now — Phase 1 doesn't support nested editing
                    return WorkoutSaveInterval(type: "rest")
                }
            }
        )
    }
}
