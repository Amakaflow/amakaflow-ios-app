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
    /// When set, mapper updates this workout instead of creating a duplicate.
    var workoutId: String?
    /// AMA-2336 — workout-level enrichment deletes, persisted on `workout_data`.
    var enrichmentTombstones: [EnrichmentTombstone]?
    /// Stable taxonomy identifier selected or matched for this workout.
    var canonicalId: String?
    /// Ownership of the canonical selection (`auto`, `user_pick`, or `preset`).
    var canonicalSource: CanonicalSource?
    /// Distinguishes legacy omission (preserve server values) from editor-owned nulls (clear).
    var canonicalFieldsProvided: Bool = false

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
            blocks: blocksFromWorkout(workout),
            workoutId: workout.id
        )
    }

    private static func formattedLoad(_ load: ExerciseLoad) -> String? {
        if load.value > 0 {
            if load.unit == "bodyweight" { return "bodyweight" }
            let valueText = load.value.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(load.value))
                : String(load.value)
            let unit = load.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            return unit.isEmpty ? valueText : "\(valueText) \(unit)"
        }
        let unit = load.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? nil : unit
    }

    private static func blocksFromWorkout(_ workout: Workout) -> [SocialImportBlock]? {
        guard !workout.blocks.isEmpty else { return nil }
        return workout.blocks.map { block in
            SocialImportBlock(
                label: block.label,
                rounds: max(1, block.rounds),
                exercises: block.exercises.map { socialImportExercise(from: $0) },
                type: persistType(from: block)
            )
        }
    }

    /// AMA-2343 A+D: map Block.structure / rounds display contract → ADR-017 type.
    private static func persistType(from block: Block) -> String? {
        switch block.structure {
        case .circuit:
            return StructureBlockType.circuit.rawValue
        case .superset:
            return StructureBlockType.superset.rawValue
        case .amrap:
            return StructureBlockType.amrap.rawValue
        case .emom:
            return StructureBlockType.emom.rawValue
        case .tabata:
            return StructureBlockType.tabata.rawValue
        case .straight:
            // Library decode often loses type → structure defaults to straight.
            // When Companion shows a circuit (rounds>1, multi-ex), persist circuit.
            guard block.rounds > 1, block.exercises.count >= 2 else { return nil }
            let setsValues = block.exercises.map(\.sets)
            let unsetCount = setsValues.filter { $0 == nil }.count
            guard unsetCount >= 2 else { return nil }
            if setsValues.allSatisfy({ ($0 ?? 0) > 1 }) { return nil }
            return StructureBlockType.circuit.rawValue
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
            load: exercise.load.flatMap { formattedLoad($0) },
            focus: exercise.focus,
            notes: exercise.notes
        )
    }
}
