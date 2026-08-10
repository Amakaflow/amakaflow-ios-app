//
//  ActualsLibraryWorkoutResolver.swift
//  AmakaFlow
//
//  AMA-2396: Library match must use block-rich detail (real exercise names),
//  not interval-only `/workouts/incoming` payloads that collapse to "Timed Work".
//

import Foundation

enum ActualsLibraryWorkoutResolver {
    /// Placeholder names produced when timed/distance intervals lack a target.
    static let placeholderNames: Set<String> = [
        "timed work",
        "distance",
        "exercise",
        "work",
        "timed",
        "timed interval",
        "warm up",
        "cool down"
    ]

    static func looksPlaceholder(_ workout: Workout) -> Bool {
        let names = workout.blocks.flatMap(\.exercises).map(\.name)
        guard !names.isEmpty else { return true }
        return names.allSatisfy { isPlaceholderName($0) }
    }

    static func isPlaceholderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return placeholderNames.contains(trimmed.lowercased())
    }

    /// Prefer local detail cache, then GET `/workouts/{id}` blocks JSON.
    @MainActor
    static func resolveDetail(
        for base: Workout,
        api: APIServiceProviding = APIService.shared
    ) async -> Workout {
        let enriched = WorkoutLibraryDetailStore.enrich(base)
        if !looksPlaceholder(enriched) {
            return enriched
        }

        do {
            let blocksJSON = try await api.fetchWorkoutBlocksJSON(workoutId: base.id)
            if let detailed = workout(fromBlocksJSON: blocksJSON, base: base) {
                _ = WorkoutLibraryDetailStore.save(detailed)
                return detailed
            }
        } catch {
            // Keep enriched/incoming fallback — match still works, structure may be thin.
        }
        return enriched
    }

    /// Resolve by id from a local map (match picker), then fetch detail if needed.
    @MainActor
    static func resolveDetail(
        workoutID: String,
        title: String,
        local: [String: Workout],
        api: APIServiceProviding = APIService.shared
    ) async -> Workout? {
        if let localWorkout = local[workoutID] {
            return await resolveDetail(for: localWorkout, api: api)
        }
        // No local row — still try the detail endpoint.
        let stub = Workout(
            id: workoutID,
            name: title,
            sport: .other,
            duration: 0,
            blocks: [],
            source: .manual
        )
        let resolved = await resolveDetail(for: stub, api: api)
        return looksPlaceholder(resolved) && resolved.blocks.isEmpty ? nil : resolved
    }

    static func workout(fromBlocksJSON data: [String: Any], base: Workout) -> Workout? {
        let parsed = WorkoutEnrichmentBlocksJSON.parse(data)
        guard !parsed.blocks.isEmpty else { return nil }

        let mapped: [Block] = parsed.blocks.compactMap { block in
            let exercises = block.exercises.map { $0.toExercise() }
            guard !exercises.isEmpty else { return nil }
            return Block(
                label: block.label,
                structure: WorkoutLibraryDetailStore.blockStructure(from: block.type),
                rounds: max(1, block.rounds),
                exercises: exercises,
                restBetweenSeconds: block.restSec
            )
        }
        guard !mapped.isEmpty else { return nil }
        // Reject if we still only have placeholders — better to keep incoming.
        let names = mapped.flatMap(\.exercises).map(\.name)
        if !names.isEmpty, names.allSatisfy(isPlaceholderName) {
            return nil
        }

        let title = (data["title"] as? String)
            ?? (data["name"] as? String)
            ?? base.name
        let sportRaw = (data["sport"] as? String)
            ?? (data["workout_type"] as? String)
            ?? base.sport.rawValue

        return Workout(
            id: base.id,
            name: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? base.name
                : title,
            sport: WorkoutSport.parse(sportRaw),
            duration: base.duration,
            blocks: mapped,
            description: (data["description"] as? String) ?? base.description,
            source: base.source,
            sourceUrl: base.sourceUrl,
            creatorName: base.creatorName,
            createdAt: base.createdAt,
            sportPersisted: base.sportPersisted
        )
    }
}
