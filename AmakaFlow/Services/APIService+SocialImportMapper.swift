//
//  APIService+SocialImportMapper.swift
//  AmakaFlow
//
//  AMA-2285 / AMA-2305 — mapper save body + provenance exercise encoding.
//

import Foundation

extension APIService {
    /// POST /workouts/save body for mapper-api (`workout_data` + `sources` + `device`).
    static func mapperSaveBody(from request: WorkoutSaveRequest, source: String) throws -> [String: Any] {
        let blockPayload: [[String: Any]]
        if let blocks = request.blocks, !blocks.isEmpty {
            blockPayload = blocks.map(mapperBlockObject(from:))
        } else {
            let exercises = request.intervals.compactMap { provenanceExercise(from: $0) }
            guard !exercises.isEmpty else {
                throw APIError.serverErrorWithBody(
                    422,
                    "Add at least one exercise before saving — import didn't extract a usable list."
                )
            }
            blockPayload = [["label": "Main", "exercises": exercises]]
        }

        var workoutData: [String: Any] = [
            "title": request.name,
            "workout_type": request.sport,
            "blocks": blockPayload
        ]
        if let description = request.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            workoutData["description"] = description
        }
        var metadata: [String: Any] = [:]
        if let sourceUrl = request.sourceUrl {
            metadata["source_url"] = sourceUrl
        }
        if let creator = request.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines), !creator.isEmpty {
            metadata["creator"] = creator
        }
        // Persist under metadata — WorkoutData forbids a top-level key (AMA-2334 gap).
        // `nil` = leave server tombstones alone; `[]` = clear them after a re-opt-in.
        if let tombstones = request.enrichmentTombstones {
            metadata["enrichment_tombstones"] = try EnrichmentTombstone.metadataPayload(tombstones)
        }
        if !metadata.isEmpty {
            workoutData["metadata"] = metadata
        }
        var body: [String: Any] = [
            "workout_data": workoutData,
            "sources": [source],
            "device": "ios",
            "title": request.name
        ]
        if let workoutId = request.workoutId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workoutId.isEmpty {
            body["workout_id"] = workoutId
        }
        return body
    }

    /// ADR-017 + AMA-2336 declared fields on each block for mapper persistence.
    static func mapperBlockObject(from block: SocialImportBlock) -> [String: Any] {
        var object: [String: Any] = [
            "exercises": block.exercises.map { provenanceExercise(from: $0) }
        ]
        if let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            object["label"] = label
        }
        if block.rounds > 1 {
            object["rounds"] = block.rounds
        }
        if let type = block.type?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty {
            object["type"] = type
        }
        if let restOpen = block.restOpen {
            object["rest_open"] = restOpen
            if !restOpen, let restSec = block.restSec, restSec > 0 {
                object["rest_sec"] = restSec
            }
        } else if let restSec = block.restSec, restSec > 0 {
            object["rest_sec"] = restSec
        }
        if let structureSource = block.structureSource?.trimmingCharacters(in: .whitespacesAndNewlines),
           !structureSource.isEmpty {
            object["structure_source"] = structureSource
        }
        if let enrichmentKind = block.enrichmentKind?.trimmingCharacters(in: .whitespacesAndNewlines),
           !enrichmentKind.isEmpty {
            object["enrichment_kind"] = enrichmentKind
        }
        if let provenance = block.fieldProvenance, !provenance.isEmpty {
            object["field_provenance"] = provenance
        }
        return object
    }

    static func provenanceExercise(from exercise: SocialImportExercise) -> [String: Any] {
        var object: [String: Any] = ["name": exercise.name]
        if let seconds = exercise.seconds, seconds > 0 {
            object["duration_sec"] = seconds
        } else if let meters = exercise.distanceMeters, meters > 0 {
            object["distance_m"] = meters
        } else {
            if let sets = exercise.sets { object["sets"] = sets }
            if let range = exercise.repsRange?.trimmingCharacters(in: .whitespacesAndNewlines), !range.isEmpty {
                object["reps_range"] = range
            }
            if let reps = exercise.reps { object["reps"] = reps }
        }
        if let loadText = exercise.load?.trimmingCharacters(in: .whitespacesAndNewlines), !loadText.isEmpty {
            let parsed = Workout.resolveLegacyLoadAndInstruction(from: loadText)
            if let parsedLoad = parsed.load, parsedLoad.value > 0 {
                object["weight"] = parsedLoad.value
                object["weight_unit"] = parsedLoad.unit
            } else {
                object["notes"] = loadText
            }
        } else if let notes = exercise.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !notes.isEmpty,
                  !Exercise.looksLikeMuscleFocus(notes) {
            object["notes"] = notes
        }
        if let focus = exercise.focus?.trimmingCharacters(in: .whitespacesAndNewlines), !focus.isEmpty {
            object["muscle_group"] = focus
        }
        if let provenance = exercise.fieldProvenance, !provenance.isEmpty {
            object["field_provenance"] = provenance
        }
        applyEnrichmentFields(from: exercise, to: &object)
        return object
    }

    /// AMA-2336 declared enrichment fields — identity, warm-up sets, rest intent.
    static func applyEnrichmentFields(from exercise: SocialImportExercise, to object: inout [String: Any]) {
        if let exerciseId = exercise.exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !exerciseId.isEmpty {
            object["exercise_id"] = exerciseId
        }
        if let warmupSets = exercise.warmupSets, !warmupSets.isEmpty {
            object["warmup_sets"] = warmupSets.map(warmupSetObject(from:))
        }
        if let restOpen = exercise.restOpen {
            object["rest_open"] = restOpen
            if !restOpen, let restSeconds = exercise.restSeconds, restSeconds > 0 {
                object["rest_sec"] = restSeconds
            }
        } else if let restSeconds = exercise.restSeconds, restSeconds > 0 {
            object["rest_sec"] = restSeconds
        }
        if let structureSource = exercise.structureSource?.trimmingCharacters(in: .whitespacesAndNewlines),
           !structureSource.isEmpty {
            object["structure_source"] = structureSource
        }
    }

    /// Declared `warmup_sets` row — sibling of `sets`, never an underscore key (AMA-2336).
    static func warmupSetObject(from row: WarmupSetRow) -> [String: Any] {
        var object: [String: Any] = [
            "reps": row.reps,
            "structure_source": row.structureSource.rawValue
        ]
        if let weight = row.weight {
            object["weight"] = weight
        }
        return object
    }

    static func provenanceExercise(from interval: WorkoutSaveInterval) -> [String: Any]? {
        switch interval.type {
        case "reps":
            let name = (interval.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var exercise: [String: Any] = [
                "name": name,
                "sets": interval.sets ?? 3,
                "reps": interval.reps ?? 10
            ]
            if let load = interval.load?.trimmingCharacters(in: .whitespacesAndNewlines), !load.isEmpty {
                exercise["notes"] = load
            }
            return exercise
        case "time", "warmup", "cooldown":
            let name = (interval.target ?? interval.name ?? "Exercise")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var exercise: [String: Any] = ["name": name]
            if let seconds = interval.seconds { exercise["duration_sec"] = seconds }
            return exercise
        case "distance":
            let name = (interval.target ?? interval.name ?? "Exercise")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var exercise: [String: Any] = ["name": name, "reps": "\(interval.meters ?? 0)m"]
            return exercise
        case "rest":
            return nil
        default:
            return nil
        }
    }

    static func synthesizedProvenanceWorkout(
        from request: WorkoutSaveRequest,
        source: String,
        responseData: Data
    ) -> Workout {
        let object = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]
        let workoutId = (object?["workout_id"] as? String)
            ?? (object?["id"] as? String)
            ?? UUID().uuidString

        if let blocks = request.blocks, !blocks.isEmpty {
            let mappedBlocks = blocks.map { block in
                Block(
                    label: block.label,
                    structure: .straight,
                    rounds: max(1, block.rounds),
                    exercises: block.exercises.map { $0.toExercise() }
                )
            }
            return Workout(
                id: workoutId,
                name: request.name,
                sport: WorkoutSport(rawValue: request.sport) ?? .strength,
                duration: 0,
                blocks: mappedBlocks,
                description: request.description,
                source: WorkoutSource(rawValue: source) ?? .other,
                sourceUrl: request.sourceUrl,
                creatorName: request.creatorName
            )
        }

        let intervals: [WorkoutInterval] = request.intervals.compactMap { interval in
            switch interval.type {
            case "time":
                return .time(seconds: interval.seconds ?? 60, target: interval.target ?? interval.name)
            case "reps":
                return .reps(
                    sets: interval.sets,
                    reps: interval.reps ?? 10,
                    name: interval.name ?? "Exercise",
                    load: interval.load,
                    restSec: interval.restSeconds,
                    followAlongUrl: nil
                )
            case "warmup":
                return .warmup(seconds: interval.seconds ?? 60, target: interval.target)
            case "cooldown":
                return .cooldown(seconds: interval.seconds ?? 60, target: interval.target)
            case "distance":
                return .distance(meters: interval.meters ?? 0, target: interval.target)
            case "rest":
                return .rest(seconds: interval.seconds)
            default:
                return nil
            }
        }
        return Workout(
            id: workoutId,
            name: request.name,
            sport: WorkoutSport(rawValue: request.sport) ?? .strength,
            duration: 0,
            intervals: intervals,
            description: request.description,
            source: WorkoutSource(rawValue: source) ?? .other,
            sourceUrl: request.sourceUrl,
            creatorName: request.creatorName
        )
    }
}
