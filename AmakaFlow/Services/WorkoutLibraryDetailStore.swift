//
//  WorkoutLibraryDetailStore.swift
//  AmakaFlow
//
//  Persists block-rich workout detail locally. Mapper `/workouts/incoming`
//  still returns legacy intervals for playback — we merge cached detail at read time.
//

import Foundation

enum WorkoutLibraryDetailStore {
    private static let defaultsKey = "af_library_workout_detail_cache_v1"

    static func save(_ workout: Workout) {
        guard !workout.blocks.isEmpty else { return }
        var cache = loadAll()
        cache[workout.id] = workout
        persist(cache)
    }

    /// Prefer cached blocks, description, provenance when the server payload is interval-only.
    static func enrich(_ workout: Workout) -> Workout {
        guard let cached = loadAll()[workout.id], !cached.blocks.isEmpty else {
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

    private static func resolvedSource(fetched: Workout, cached: Workout) -> WorkoutSource {
        switch fetched.source {
        case .amaka, .other, .manual:
            return cached.source == .manual ? fetched.source : cached.source
        default:
            return fetched.source
        }
    }

    private static func loadAll() -> [String: Workout] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [:] }
        guard let decoded = try? APIService.makeDecoder().decode([String: Workout].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func persist(_ cache: [String: Workout]) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
