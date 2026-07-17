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
    /// Provenance raw value (instagram / tiktok / youtube / manual / …). AMA-2285.
    var source: String?
    /// Optional origin URL for social imports. AMA-2285.
    var sourceUrl: String?
    /// Workout description from post / coach share.
    var description: String?
    /// Creator handle or coach name from post provenance.
    var creatorName: String?
    /// Block structure from social ingest (preserves section labels).
    var blocks: [SocialImportBlock]?

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
            },
            source: workout.source.rawValue,
            sourceUrl: workout.sourceUrl,
            description: workout.description,
            creatorName: workout.creatorName,
            blocks: blocksFromWorkout(workout)
        )
    }

    private static func blocksFromWorkout(_ workout: Workout) -> [SocialImportBlock]? {
        guard !workout.blocks.isEmpty else { return nil }
        return workout.blocks.map { block in
            SocialImportBlock(
                label: block.label,
                rounds: max(1, block.rounds),
                exercises: block.exercises.map { socialImportExercise(from: $0) }
            )
        }
    }

    private static func socialImportExercise(from exercise: Exercise) -> SocialImportExercise {
        let repsText = exercise.reps?.trimmingCharacters(in: .whitespacesAndNewlines)
        let numericReps: Int? = {
            guard let repsText, !repsText.isEmpty else { return nil }
            if let value = Int(repsText) { return value }
            let parsed = BlockToIntervalConverter.parseReps(repsText)
            return parsed > 0 ? parsed : nil
        }()
        let repsRange: String? = {
            guard let repsText, !repsText.isEmpty, Int(repsText) == nil else { return nil }
            return repsText
        }()

        return SocialImportExercise(
            name: exercise.name,
            sets: exercise.sets,
            reps: numericReps,
            repsRange: repsRange,
            seconds: exercise.durationSeconds,
            distanceMeters: exercise.distance.map { Int($0) },
            load: exercise.load.flatMap { load in
                if load.value > 0, !load.unit.isEmpty {
                    return "\(load.value) \(load.unit)"
                }
                return load.unit.isEmpty ? nil : load.unit
            },
            focus: exercise.focus,
            notes: exercise.notes
        )
    }
}
