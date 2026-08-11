//
//  FixtureEnrichment.swift
//  AmakaFlow
//
//  AMA-2408 — local enrich + WorkoutKit compose for UITEST_USE_FIXTURES dogfood.
//  Mirrors mapper behavior closely enough to validate opt-in ramps in sim.
//

#if DEBUG
import Foundation

enum FixtureEnrichment {
    static func blocksJSON(from workout: Workout) -> [String: Any] {
        let blocks: [[String: Any]] = workout.blocks.map { block in
            var dict: [String: Any] = [
                "structure": block.structure.rawValue,
                "type": block.structure == .straight ? "sets" : block.structure.rawValue,
                "rounds": block.rounds,
                "exercises": block.exercises.map { fixtureExerciseDict(from: $0) }
            ]
            if let label = block.label { dict["label"] = label }
            if let rest = block.restBetweenSeconds { dict["rest_between_sec"] = rest }
            return dict
        }
        return [
            "title": workout.name,
            "blocks": blocks
        ]
    }

    static func applySessionWarmup(
        into blocksJSON: [String: Any],
        prefs: SessionWarmupPrefs
    ) -> [String: Any] {
        var blocks = (blocksJSON["blocks"] as? [[String: Any]]) ?? []
        let already = blocks.contains {
            ($0["type"] as? String)?.lowercased() == "warmup"
                || ($0["enrichment_kind"] as? String) == "session_warmup"
        }
        guard !already else { return blocksJSON }
        let activities = prefs.activities.isEmpty
            ? [EnrichmentActivityPref(name: "Jump Rope", durationSec: 120,
                                      goal: try? ActivityGoal(kind: .time, value: 120))]
            : prefs.activities
        return withInsertedBlock(
            blocksJSON,
            at: 0,
            block: softEnrichmentBlock(
                type: "warmup",
                enrichmentKind: "session_warmup",
                label: "Warm-up",
                activities: activities
            )
        )
    }

    static func applyCooldown(
        into blocksJSON: [String: Any],
        prefs: CooldownPrefs
    ) -> [String: Any] {
        var blocks = (blocksJSON["blocks"] as? [[String: Any]]) ?? []
        let already = blocks.contains {
            ($0["type"] as? String)?.lowercased() == "cooldown"
                || ($0["enrichment_kind"] as? String) == "cooldown"
        }
        guard !already else { return blocksJSON }
        // Empty saved cooldown stays empty — do not inject default stretches.
        guard !prefs.activities.isEmpty else { return blocksJSON }
        return withAppendedBlock(
            blocksJSON,
            block: softEnrichmentBlock(
                type: "cooldown",
                enrichmentKind: "cooldown",
                label: "Cool-down",
                activities: prefs.activities
            )
        )
    }

    static func applyBetweenSetRest(
        into blocksJSON: [String: Any],
        prefs: BetweenSetRestPrefs
    ) -> [String: Any] {
        guard var blocks = blocksJSON["blocks"] as? [[String: Any]] else { return blocksJSON }
        for index in blocks.indices {
            let type = (blocks[index]["type"] as? String)?.lowercased() ?? ""
            if type == "warmup" || type == "cooldown" { continue }
            if prefs.restOpen {
                blocks[index]["rest_open"] = true
                blocks[index].removeValue(forKey: "rest_between_sec")
            } else if let sec = prefs.restSec {
                blocks[index]["rest_between_sec"] = sec
                blocks[index].removeValue(forKey: "rest_open")
            }
        }
        var out = blocksJSON
        out["blocks"] = blocks
        return out
    }

    static func applyExerciseWarmupSets(
        into blocksJSON: [String: Any],
        prefs: ExerciseWarmupSetsPrefs
    ) -> [String: Any] {
        guard var blocks = blocksJSON["blocks"] as? [[String: Any]] else { return blocksJSON }
        let excluded = Set(prefs.excludeExerciseKeys.map(ExerciseKeyNormalizer.normalize))
        let byKey: [String: PerExerciseRamp] = Dictionary(
            uniqueKeysWithValues: (prefs.perExercise ?? []).map {
                (ExerciseKeyNormalizer.normalize($0.exerciseRef), $0)
            }
        )

        for blockIndex in blocks.indices {
            let type = (blocks[blockIndex]["type"] as? String)?.lowercased() ?? ""
            if type == "warmup" || type == "cooldown" { continue }
            guard var exercises = blocks[blockIndex]["exercises"] as? [[String: Any]] else { continue }
            for exerciseIndex in exercises.indices {
                stampWarmupSets(
                    onto: &exercises[exerciseIndex],
                    byKey: byKey,
                    excluded: excluded
                )
            }
            blocks[blockIndex]["exercises"] = exercises
        }
        var out = blocksJSON
        out["blocks"] = blocks
        return out
    }

    static func workoutKitPlanJSON(from blocksJSON: [String: Any], restMode: String) -> Data {
        let restInterval = fixtureRestInterval(restMode: restMode)
        var intervals: [[String: Any]] = []
        let blocks = (blocksJSON["blocks"] as? [[String: Any]]) ?? []
        for block in blocks {
            appendBlockIntervals(
                from: block,
                restMode: restMode,
                restInterval: restInterval,
                into: &intervals
            )
        }

        let title = (blocksJSON["title"] as? String) ?? "Fixture"
        let payload: [String: Any] = [
            "title": title,
            "sportType": "traditionalStrengthTraining",
            "composition": "custom",
            "composition_effective": "custom",
            "routing_reason": "strength_sets",
            "intervals": intervals
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]))
            ?? Data("{}".utf8)
    }
}

// MARK: - File-private helpers (keep FixtureEnrichment under SwiftLint type_body_length)

private func fixtureExerciseDict(from exercise: Exercise) -> [String: Any] {
    var dict: [String: Any] = ["name": exercise.name]
    if let sets = exercise.sets { dict["sets"] = sets }
    if let reps = exercise.reps {
        if let asInt = Int(reps) { dict["reps"] = asInt } else { dict["reps"] = reps }
    }
    if let rest = exercise.restSeconds { dict["rest_sec"] = rest }
    return dict
}

private func softEnrichmentBlock(
    type: String,
    enrichmentKind: String,
    label: String,
    activities: [EnrichmentActivityPref]
) -> [String: Any] {
    let exercises: [[String: Any]] = activities.map { activity in
        var row: [String: Any] = ["name": activity.name]
        if let goal = activity.goal {
            row["goal"] = ["kind": goal.kind.rawValue, "value": goal.value as Any]
        }
        if let seconds = activity.durationSec { row["duration_sec"] = seconds }
        return row
    }
    return [
        "type": type,
        "enrichment_kind": enrichmentKind,
        "label": label,
        "exercises": exercises
    ]
}

private func withInsertedBlock(
    _ blocksJSON: [String: Any],
    at index: Int,
    block: [String: Any]
) -> [String: Any] {
    var blocks = (blocksJSON["blocks"] as? [[String: Any]]) ?? []
    blocks.insert(block, at: index)
    var out = blocksJSON
    out["blocks"] = blocks
    return out
}

private func withAppendedBlock(
    _ blocksJSON: [String: Any],
    block: [String: Any]
) -> [String: Any] {
    var blocks = (blocksJSON["blocks"] as? [[String: Any]]) ?? []
    blocks.append(block)
    var out = blocksJSON
    out["blocks"] = blocks
    return out
}

private func stampWarmupSets(
    onto exercise: inout [String: Any],
    byKey: [String: PerExerciseRamp],
    excluded: Set<String>
) {
    let name = exercise["name"] as? String ?? ""
    let key = ExerciseKeyNormalizer.normalize(name)
    guard let ramp = byKey[key], ramp.enabled, !ramp.sets.isEmpty else {
        if excluded.contains(key) {
            exercise.removeValue(forKey: "warmup_sets")
        }
        return
    }
    // Intensity notes stay off the wire (AMA-2408) — reps only.
    exercise["warmup_sets"] = ramp.sets.compactMap(fixtureWarmupRow(from:))
}

private func fixtureWarmupRow(from set: RampSet) -> [String: Any]? {
    switch set.kind {
    case .reps:
        return [
            "kind": "reps",
            "reps": set.value ?? 1,
            "structure_source": "enrichment_default"
        ]
    case .time:
        return [
            "kind": "time",
            "value": set.value ?? 30,
            "duration_sec": set.value ?? 30,
            "structure_source": "enrichment_default"
        ]
    case .cals:
        return [
            "kind": "cals",
            "value": set.value ?? 15,
            "structure_source": "enrichment_default"
        ]
    case .open:
        return [
            "kind": "open",
            "structure_source": "enrichment_default"
        ]
    }
}

private func fixtureRestInterval(restMode: String) -> [String: Any]? {
    switch restMode {
    case "timed":
        return ["kind": "rest", "seconds": 60]
    case "omit":
        return nil
    default:
        return ["kind": "rest"]
    }
}

private func appendBlockIntervals(
    from block: [String: Any],
    restMode: String,
    restInterval: [String: Any]?,
    into intervals: inout [[String: Any]]
) {
    let type = (block["type"] as? String)?.lowercased()
        ?? (block["structure"] as? String)?.lowercased()
        ?? "sets"
    let exercises = (block["exercises"] as? [[String: Any]]) ?? []
    if type == "warmup" || (block["enrichment_kind"] as? String) == "session_warmup" {
        for exercise in exercises {
            intervals.append(fixtureSoftStep(from: exercise, fallbackName: "Warm-up"))
        }
        return
    }
    if type == "cooldown" || (block["enrichment_kind"] as? String) == "cooldown" {
        for exercise in exercises {
            intervals.append(fixtureSoftStep(from: exercise, fallbackName: "Cool-down"))
        }
        return
    }

    let rest = FixtureRestContext(
        blockRestOpen: block["rest_open"] as? Bool ?? false,
        blockRestSec: block["rest_between_sec"] as? Int,
        restMode: restMode,
        restInterval: restInterval
    )
    for exercise in exercises {
        appendExerciseIntervals(from: exercise, rest: rest, into: &intervals)
    }
}

private struct FixtureRestContext {
    let blockRestOpen: Bool
    let blockRestSec: Int?
    let restMode: String
    let restInterval: [String: Any]?
}

private func appendExerciseIntervals(
    from exercise: [String: Any],
    rest: FixtureRestContext,
    into intervals: inout [[String: Any]]
) {
    let name = (exercise["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        .fixtureNilIfEmpty ?? "Exercise"
    let warmupSets = (exercise["warmup_sets"] as? [[String: Any]]) ?? []
    if !warmupSets.isEmpty {
        var warmupSteps: [[String: Any]] = []
        for warmup in warmupSets {
            warmupSteps.append(fixtureWarmupStep(name: name, warmup: warmup))
            if let chip = fixtureRestChip(exercise: exercise, rest: rest) {
                warmupSteps.append(chip)
            }
        }
        intervals.append([
            "kind": "repeat",
            "reps": 1,
            "intervals": warmupSteps
        ])
    }

    let sets = max((exercise["sets"] as? Int) ?? 1, 1)
    let reps = fixtureIntReps(from: exercise["reps"]) ?? 10
    var workSteps: [[String: Any]] = [
        ["kind": "reps", "reps": reps, "name": name]
    ]
    if let chip = fixtureRestChip(exercise: exercise, rest: rest) {
        workSteps.append(chip)
    }
    intervals.append([
        "kind": "repeat",
        "reps": sets,
        "intervals": workSteps
    ])
}

private func fixtureSoftStep(from exercise: [String: Any], fallbackName: String) -> [String: Any] {
    let name = (exercise["name"] as? String)?.fixtureNilIfEmpty ?? fallbackName
    if let seconds = exercise["duration_sec"] as? Int {
        return ["kind": "work", "name": name, "seconds": seconds]
    }
    if let goal = exercise["goal"] as? [String: Any],
       (goal["kind"] as? String) == "time",
       let value = goal["value"] as? Int {
        return ["kind": "work", "name": name, "seconds": value]
    }
    return ["kind": "work", "name": name]
}

private func fixtureWarmupStep(name: String, warmup: [String: Any]) -> [String: Any] {
    let kind = (warmup["kind"] as? String) ?? "reps"
    let labelPrefix = "Warm-up · \(name)"
    switch kind {
    case "time":
        let seconds = (warmup["duration_sec"] as? Int)
            ?? (warmup["value"] as? Int)
            ?? 30
        return ["kind": "work", "name": "\(labelPrefix) · \(seconds)", "seconds": seconds]
    case "cals":
        let cals = (warmup["value"] as? Int) ?? 15
        return ["kind": "cals", "cals": cals, "name": "\(labelPrefix) · \(cals)"]
    case "open":
        return ["kind": "reps", "reps": 1, "name": labelPrefix]
    default:
        let reps = (warmup["reps"] as? Int) ?? (warmup["value"] as? Int) ?? 1
        // Trailing digit so preview coerce / banding shows the real reps.
        return ["kind": "reps", "reps": reps, "name": "\(labelPrefix) · \(reps)"]
    }
}

private func fixtureRestChip(
    exercise: [String: Any],
    rest: FixtureRestContext
) -> [String: Any]? {
    if rest.restMode == "omit" { return nil }
    if let open = exercise["rest_open"] as? Bool, open {
        return ["kind": "rest"]
    }
    if let sec = exercise["rest_sec"] as? Int, sec > 0 {
        return ["kind": "rest", "seconds": sec]
    }
    if rest.blockRestOpen { return ["kind": "rest"] }
    if let sec = rest.blockRestSec, sec > 0 {
        return ["kind": "rest", "seconds": sec]
    }
    return rest.restInterval
}

private func fixtureIntReps(from value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let str = value as? String { return Int(str) }
    return nil
}

private extension String {
    var fixtureNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
