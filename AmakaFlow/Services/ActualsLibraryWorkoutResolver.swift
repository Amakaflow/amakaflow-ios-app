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
        let fromBlocks: [Block] = parsed.blocks.compactMap { block in
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
        let fromIntervals = blocksFromIntervalsJSON(data["intervals"]) ?? []

        // Prefer real names. Empty / all-"Timed Work" blocks are common when the
        // Library row is intervals-only (`name` + `target: null` on each step).
        let mapped: [Block]
        if hasRealExerciseNames(fromBlocks) {
            mapped = fromBlocks
        } else if hasRealExerciseNames(fromIntervals) {
            mapped = fromIntervals
        } else {
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

    private static func hasRealExerciseNames(_ blocks: [Block]) -> Bool {
        let names = blocks.flatMap(\.exercises).map(\.name)
        guard !names.isEmpty else { return false }
        return !names.allSatisfy(isPlaceholderName)
    }

    /// Incoming / workout_data often stores structure as intervals (repeat of timed steps)
    /// with names on `name` and `target: null`.
    private static func blocksFromIntervalsJSON(_ raw: Any?) -> [Block]? {
        let intervals = decodeIntervalsSkippingUnknown(raw)
        guard !intervals.isEmpty else { return nil }
        let blocks = Workout.blocksFromLegacyIntervals(intervals)
        return blocks.isEmpty ? nil : blocks
    }

    /// Decode interval arrays element-by-element so unknown kinds do not fail
    /// the whole structure. Flat `round_start` markers (mapper/incoming) become
    /// a `.repeat` so fill-in / Strava keep the round count.
    private static func decodeIntervalsSkippingUnknown(_ raw: Any?) -> [WorkoutInterval] {
        guard let items = raw as? [Any] else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var intervals: [WorkoutInterval] = []
        var pendingRoundBody: [WorkoutInterval]?
        var pendingRounds = 1

        func flushRound() {
            guard let body = pendingRoundBody, !body.isEmpty else {
                pendingRoundBody = nil
                return
            }
            intervals.append(.repeat(reps: max(1, pendingRounds), intervals: body))
            pendingRoundBody = nil
            pendingRounds = 1
        }

        for item in items {
            guard let dict = item as? [String: Any] else { continue }
            let kind = (dict["kind"] as? String)?.lowercased() ?? ""
            if kind == "round_start" || kind == "roundstart" {
                flushRound()
                pendingRounds = dict["rounds"] as? Int ?? dict["reps"] as? Int ?? 1
                pendingRoundBody = []
                continue
            }
            if kind == "repeat" {
                flushRound()
                let reps = dict["reps"] as? Int ?? dict["rounds"] as? Int ?? 1
                let kids = decodeIntervalsSkippingUnknown(dict["intervals"])
                if !kids.isEmpty {
                    intervals.append(.repeat(reps: max(1, reps), intervals: kids))
                }
                continue
            }
            guard JSONSerialization.isValidJSONObject(dict),
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let interval = try? decoder.decode(WorkoutInterval.self, from: data) else {
                continue
            }
            if pendingRoundBody != nil {
                pendingRoundBody?.append(interval)
            } else {
                intervals.append(interval)
            }
        }
        flushRound()
        return intervals
    }
}
