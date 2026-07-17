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
        return Workout(
            id: workout.id,
            name: cached.name.isEmpty ? workout.name : cached.name,
            sport: workout.sport == .other ? cached.sport : workout.sport,
            duration: max(workout.duration, cached.duration),
            blocks: cached.blocks,
            description: cached.description ?? workout.description,
            source: resolvedSource(fetched: workout, cached: cached),
            sourceUrl: cached.sourceUrl ?? workout.sourceUrl,
            creatorName: cached.creatorName ?? workout.creatorName,
            createdAt: cached.createdAt ?? workout.createdAt
        )
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
