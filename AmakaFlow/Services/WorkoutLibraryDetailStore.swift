//
//  WorkoutLibraryDetailStore.swift
//  AmakaFlow
//
//  Persists block-rich workout detail locally. Mapper `/workouts/incoming`
//  still returns legacy intervals for playback — we merge cached detail at read time.
//

import Foundation

enum WorkoutLibraryDetailStoreError: Error, Equatable {
    case decodeFailed
    case encodeFailed
}

enum WorkoutLibraryDetailStore {
    private static let defaultsKey = "af_library_workout_detail_cache_v1"

    @discardableResult
    static func save(_ workout: Workout) -> Result<Void, WorkoutLibraryDetailStoreError> {
        guard !workout.blocks.isEmpty else { return .success(()) }
        switch loadAllResult() {
        case .failure(let error):
            return .failure(error)
        case .success(var cache):
            cache[workout.id] = workout
            return persist(cache)
        }
    }

    /// After Editor v2 save: refresh the local detail cache so Library doesn't keep
    /// stale import blocks (mapper `/workouts/incoming` is often interval-only).
    @discardableResult
    static func saveAfterEditor(saved: Workout, request: WorkoutSaveRequest) -> Result<Void, WorkoutLibraryDetailStoreError> {
        save(detailWorkout(saved: saved, request: request))
    }

    /// Build the block-rich workout that Library detail should show after an edit.
    static func detailWorkout(saved: Workout, request: WorkoutSaveRequest) -> Workout {
        let blocks: [Block]
        if let requestBlocks = request.blocks, !requestBlocks.isEmpty {
            blocks = requestBlocks.map { block in
                Block(
                    label: block.label,
                    structure: blockStructure(from: block.type),
                    rounds: max(1, block.rounds),
                    exercises: block.exercises.map { $0.toExercise() },
                    restBetweenSeconds: block.restSec
                )
            }
        } else if !saved.blocks.isEmpty {
            blocks = saved.blocks
        } else {
            blocks = Workout.blocksFromLegacyIntervals(
                request.intervals.compactMap(Self.interval(from:))
            )
        }

        // Duration follows the current edit — do not max against a stale larger save response.
        return Workout(
            id: saved.id,
            name: request.name.isEmpty ? saved.name : request.name,
            sport: WorkoutSport(rawValue: request.sport) ?? saved.sport,
            duration: saved.duration > 0 ? saved.duration : 0,
            blocks: blocks,
            description: request.description ?? saved.description,
            source: WorkoutSource(rawValue: request.source ?? "") ?? saved.source,
            sourceUrl: request.sourceUrl ?? saved.sourceUrl,
            creatorName: request.creatorName ?? saved.creatorName,
            createdAt: saved.createdAt
        )
    }

    /// Prefer cached blocks, description, provenance when the server payload is interval-only.
    static func enrich(_ workout: Workout) -> Workout {
        switch loadAllResult() {
        case .success(let cache):
            return enrich(workout, cache: cache)
        case .failure:
            return workout
        }
    }

    /// Decode the detail cache once and enrich an entire collection.
    static func enrichCollection(_ workouts: [Workout]) -> [Workout] {
        switch loadAllResult() {
        case .success(let cache):
            return workouts.map { enrich($0, cache: cache) }
        case .failure:
            return workouts
        }
    }

    static func enrichFromDraft(_ workout: Workout, draft: SocialImportDraft) -> Workout {
        let preview = draft.toPreviewWorkout()
        return Workout(
            id: workout.id,
            name: preview.name,
            sport: preview.sport,
            duration: max(workout.duration, preview.duration),
            blocks: preview.blocks,
            description: preview.description ?? draft.workoutDescription,
            source: WorkoutSource(rawValue: draft.platform.workoutSourceRawValue) ?? workout.source,
            sourceUrl: draft.sourceURL ?? workout.sourceUrl,
            creatorName: draft.postProvenance?.creator ?? workout.creatorName,
            createdAt: workout.createdAt ?? Date()
        )
    }

    private static func enrich(_ workout: Workout, cache: [String: Workout]) -> Workout {
        guard let cached = cache[workout.id], !cached.blocks.isEmpty else {
            return workout
        }
        // Cache is the block-rich source of truth for interval-only library payloads.
        // Duration stays with the cached blocks so shrinking an edit can take effect.
        return Workout(
            id: workout.id,
            name: workout.name.isEmpty ? cached.name : workout.name,
            sport: workout.sport == .other ? cached.sport : workout.sport,
            duration: cached.duration,
            blocks: cached.blocks,
            description: cached.description ?? workout.description,
            source: resolvedSource(fetched: workout, cached: cached),
            sourceUrl: cached.sourceUrl ?? workout.sourceUrl,
            creatorName: cached.creatorName ?? workout.creatorName,
            createdAt: cached.createdAt ?? workout.createdAt
        )
    }

    /// Map ADR-017 / SocialImport block type strings onto Library `BlockStructure`.
    /// `for-time` has no dedicated `BlockStructure` case yet — closest is circuit (multi-round).
    static func blockStructure(from type: String?) -> BlockStructure {
        switch type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "superset": return .superset
        case "circuit", "rounds", "warmup": return .circuit
        case "for-time", "fortime": return .circuit
        case "amrap": return .amrap
        case "emom": return .emom
        case "tabata": return .tabata
        default: return .straight
        }
    }

    /// Shared `WorkoutSaveInterval` → playback interval mapping (editor + fixtures).
    static func interval(from save: WorkoutSaveInterval) -> WorkoutInterval? {
        switch save.type {
        case "time":
            return .time(seconds: save.seconds ?? 60, target: save.target ?? save.name)
        case "reps":
            return .reps(
                sets: save.sets,
                reps: save.reps ?? 10,
                name: save.name ?? "Exercise",
                load: save.load,
                restSec: save.restSeconds,
                followAlongUrl: nil
            )
        case "warmup":
            return .warmup(seconds: save.seconds ?? 60, target: save.target)
        case "cooldown":
            return .cooldown(seconds: save.seconds ?? 60, target: save.target)
        case "distance":
            return .distance(meters: save.meters ?? 0, target: save.target)
        case "rest":
            return .rest(seconds: save.seconds)
        default:
            return nil
        }
    }

    private static func resolvedSource(fetched: Workout, cached: Workout) -> WorkoutSource {
        switch fetched.source {
        case .amaka, .other, .manual:
            return cached.source == .manual ? fetched.source : cached.source
        default:
            return fetched.source
        }
    }

    private static func loadAllResult() -> Result<[String: Workout], WorkoutLibraryDetailStoreError> {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return .success([:])
        }
        do {
            let decoded = try APIService.makeDecoder().decode([String: Workout].self, from: data)
            return .success(decoded)
        } catch {
            return .failure(.decodeFailed)
        }
    }

    private static func persist(_ cache: [String: Workout]) -> Result<Void, WorkoutLibraryDetailStoreError> {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(cache)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            return .success(())
        } catch {
            return .failure(.encodeFailed)
        }
    }
}
