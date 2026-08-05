//
//  WorkoutEnrichmentMutations.swift
//  AmakaFlow
//
//  Presence reads + caller-owned tombstone / identity mutations (AMA-2336 / AMA-2363).
//

import Foundation

// MARK: - Presence + tombstone reads

/// Presence is tested by **type**, never by provenance (spec invariant 1).
enum WorkoutEnrichmentPresence {
    static func hasWarmupBlock(in blocks: [SocialImportBlock]) -> Bool {
        blocks.contains { normalizedType($0) == StructureBlockType.warmup.rawValue }
    }

    static func hasCooldownBlock(in blocks: [SocialImportBlock]) -> Bool {
        blocks.contains { normalizedType($0) == StructureBlockType.cooldown.rawValue }
    }

    static func isTombstoned(
        _ kind: EnrichmentKind,
        exerciseId: String? = nil,
        tombstones: [EnrichmentTombstone]
    ) -> Bool {
        tombstones.contains { tombstone in
            guard tombstone.kind == kind else { return false }
            guard kind == .exerciseWarmupSets else { return tombstone.exerciseId == nil }
            guard let exerciseId, let tombstonedId = tombstone.exerciseId else { return false }
            return tombstonedId == exerciseId
        }
    }

    private static func normalizedType(_ block: SocialImportBlock) -> String {
        block.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

// MARK: - Caller-owned mutations

/// Pure helpers for editor / push callers. Tombstones are written **only** here,
/// never by the enrichment core.
enum WorkoutEnrichmentMutations {
    static let restSecKey = "rest_sec"
    static let restOpenKey = "rest_open"

    /// Stable within-workout identity (`wex_…`) — tombstones key off this, not the name.
    static func mintExerciseId() -> String {
        "wex_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// AMA-2363 — enrich warm-up sets require `exercise_id`; mint before POST /workout/enrich.
    static func mintMissingExerciseIds(in blocksJSON: [String: Any]) -> [String: Any] {
        guard var blocks = blocksJSON["blocks"] as? [[String: Any]] else { return blocksJSON }
        var changed = false
        for blockIndex in blocks.indices {
            guard var exercises = blocks[blockIndex]["exercises"] as? [[String: Any]] else { continue }
            for exerciseIndex in exercises.indices {
                let existing = exercises[exerciseIndex]["exercise_id"] as? String
                if existing?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                    exercises[exerciseIndex]["exercise_id"] = mintExerciseId()
                    changed = true
                }
            }
            blocks[blockIndex]["exercises"] = exercises
        }
        guard changed else { return blocksJSON }
        var out = blocksJSON
        out["blocks"] = blocks
        return out
    }

    /// AMA-2365 — remove enrichment-owned soft sections / rest / warmup_sets so
    /// cancel or a second sync starts clean (never stacks Jump Rope).
    /// Author soft sections without `enrichment_kind` / enrichment provenance stay.
    /// `softActivityNames` also drops orphan name-only blocks left by the
    /// AMA-2364 save-strip bug (Jump Rope with no `type=warmup`).
    static func stripEnrichmentOwned(
        in blocksJSON: [String: Any],
        softActivityNames: Set<String> = []
    ) -> [String: Any] {
        guard let rawBlocks = blocksJSON["blocks"] as? [[String: Any]] else { return blocksJSON }
        let normalizedSoft = Set(softActivityNames.map(ExerciseKeyNormalizer.normalize))
        var blocks: [[String: Any]] = []
        blocks.reserveCapacity(rawBlocks.count)
        for var block in rawBlocks {
            if isEnrichmentSoftSection(block) {
                continue
            }
            if isOrphanSoftActivityBlock(block, softNames: normalizedSoft) {
                continue
            }
            // Strip each rest key only when that key's own provenance is enrichment_default.
            if var prov = block["field_provenance"] as? [String: Any] {
                for key in [restSecKey, restOpenKey]
                where (prov[key] as? String) == ProvSource.enrichmentDefault.rawValue {
                    block.removeValue(forKey: key)
                    prov.removeValue(forKey: key)
                }
                if prov.isEmpty {
                    block.removeValue(forKey: "field_provenance")
                } else {
                    block["field_provenance"] = prov
                }
            }
            if var exercises = block["exercises"] as? [[String: Any]] {
                for index in exercises.indices {
                    exercises[index] = stripEnrichmentWarmupSets(from: exercises[index])
                }
                block["exercises"] = exercises
            }
            blocks.append(block)
        }
        var out = blocksJSON
        out["blocks"] = blocks
        return out
    }

    /// Matches `WorkoutEnrichmentBlocksJSON.parse` (`type` then `structure`).
    private static func resolvedBlockKind(_ block: [String: Any]) -> String {
        let type = (block["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !type.isEmpty { return type.lowercased() }
        return ((block["structure"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            .lowercased()
    }

    /// Name-only soft leftovers (no strength `sets`) that match mobility/cooldown prefs.
    private static func isOrphanSoftActivityBlock(
        _ block: [String: Any],
        softNames: Set<String>
    ) -> Bool {
        guard !softNames.isEmpty else { return false }
        let kind = resolvedBlockKind(block)
        if !kind.isEmpty,
           kind != "straight",
           kind != "sets",
           kind != StructureBlockType.warmup.rawValue,
           kind != StructureBlockType.cooldown.rawValue {
            return false
        }
        guard let exercises = block["exercises"] as? [[String: Any]], !exercises.isEmpty else {
            return false
        }
        for exercise in exercises {
            let name = ExerciseKeyNormalizer.normalize(exercise["name"] as? String ?? "")
            guard softNames.contains(name) else { return false }
            if exercise["sets"] != nil { return false }
            if exercise["warmup_sets"] != nil { return false }
        }
        return true
    }

    private static func isEnrichmentSoftSection(_ block: [String: Any]) -> Bool {
        let kind = (block["enrichment_kind"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if kind == EnrichmentKind.sessionWarmup.rawValue || kind == EnrichmentKind.cooldown.rawValue {
            return true
        }
        let blockKind = resolvedBlockKind(block)
        guard blockKind == StructureBlockType.warmup.rawValue
            || blockKind == StructureBlockType.cooldown.rawValue else {
            return false
        }
        return (block["structure_source"] as? String) == StructureSource.enrichmentDefault.rawValue
    }

    private static func stripEnrichmentWarmupSets(from exercise: [String: Any]) -> [String: Any] {
        guard let rows = exercise["warmup_sets"] as? [[String: Any]], !rows.isEmpty else {
            return exercise
        }
        let allOwned = rows.allSatisfy { row in
            (row["structure_source"] as? String) == StructureSource.enrichmentDefault.rawValue
        }
        guard allOwned else { return exercise }
        var out = exercise
        out.removeValue(forKey: "warmup_sets")
        return out
    }

    static func appendTombstone(
        _ list: inout [EnrichmentTombstone],
        kind: EnrichmentKind,
        exerciseId: String? = nil
    ) {
        let resolvedId = kind == .exerciseWarmupSets ? exerciseId : nil
        // A per-exercise tombstone without an id is rejected by the backend — skip it.
        guard kind != .exerciseWarmupSets || resolvedId != nil else { return }
        let tombstone = EnrichmentTombstone(kind: kind, exerciseId: resolvedId)
        guard !list.contains(tombstone) else { return }
        list.append(tombstone)
    }

    static func clearTombstone(
        _ list: inout [EnrichmentTombstone],
        kind: EnrichmentKind,
        exerciseId: String? = nil
    ) {
        list.removeAll { tombstone in
            WorkoutEnrichmentPresence.isTombstoned(kind, exerciseId: exerciseId, tombstones: [tombstone])
        }
    }

    static func stampRestEnrichmentDefault(fieldProvenance: inout [String: ProvSource]) {
        fieldProvenance[restSecKey] = .enrichmentDefault
        fieldProvenance[restOpenKey] = .enrichmentDefault
    }

    static func stampRestUser(fieldProvenance: inout [String: ProvSource]) {
        fieldProvenance[restSecKey] = .user
        fieldProvenance[restOpenKey] = .user
    }

    /// Reject contradictory rest intent — `rest_open` true with a timed `rest_sec`.
    static func validatedRest(restSec: Int?, restOpen: Bool) throws -> (restSec: Int?, restOpen: Bool) {
        if restOpen, restSec != nil {
            throw WorkoutPreferencesValidationError.restOpenWithRestSec
        }
        return (restSec, restOpen)
    }

    /// AMA-2378 — `ActivityGoal.kind == .open` must carry no `value`; every other
    /// kind requires one (mirrors backend `ActivityGoal.value_rules`).
    static func validatedActivityGoal(kind: ActivityGoalKind, value: Int?) throws -> Int? {
        if kind == .open {
            guard value == nil else {
                throw WorkoutPreferencesValidationError.activityGoalOpenWithValue
            }
            return nil
        }
        guard value != nil else {
            throw WorkoutPreferencesValidationError.activityGoalRequiresValue
        }
        return value
    }

    /// AMA-2378 — `RampSet.kind == .open` must carry no `value`; every other kind
    /// requires one (mirrors backend `RampSet.value_rules`).
    static func validatedRampSet(kind: WarmupSetKind, value: Int?) throws -> Int? {
        if kind == .open {
            guard value == nil else {
                throw WorkoutPreferencesValidationError.rampSetOpenWithValue
            }
            return nil
        }
        guard value != nil else {
            throw WorkoutPreferencesValidationError.rampSetRequiresValue
        }
        return value
    }

    // MARK: - AMA-2378 Task 5 — per-exercise ramp pick/editor helpers

    /// Seed sets for an exercise that has no declared ramp yet, minted the
    /// moment its pick-screen toggle flips ON. Mirrors the global v1 default
    /// (backend `ExerciseWarmupSetsPrefs.defaults` — 8·5 reps) plus intensity
    /// notes matching the design spec example (`LIGHT · ~40%` / `MODERATE · ~60%`)
    /// so a freshly-seeded ramp reads the same as the backend's own sample.
    static func defaultRampSets() -> [RampSet] {
        [
            try? RampSet(kind: .reps, value: 8, intensityNote: "LIGHT · ~40%"),
            try? RampSet(kind: .reps, value: 5, intensityNote: "MODERATE · ~60%")
        ].compactMap { $0 }
    }

    /// Seed sequence when standing cooldown prefs have no activities yet
    /// (design `seCooldownInit` — Stretch flow 3:00 → Treadmill open). Kept off
    /// the wire until the enhance-sheet toggle is checked.
    static func defaultCooldownActivities() -> [EnrichmentActivityPref] {
        [
            EnrichmentActivityPref(
                name: "Stretch flow",
                durationSec: 180,
                goal: try? ActivityGoal(kind: .time, value: 180)
            ),
            EnrichmentActivityPref(
                name: "Treadmill",
                goal: try? ActivityGoal(kind: .open, value: nil)
            )
        ]
    }

    /// "Apply this ramp to all selected" — copies `sourceSets` onto every
    /// **enabled** ramp's `sets`, leaving disabled ramps untouched. `RampSet`
    /// and `[RampSet]` are value types, so every returned ramp owns its own
    /// copy of `sourceSets` from the instant this returns: mutating one
    /// exercise's sets afterward can never reach through to another's — the
    /// isolation the design calls for is Swift's copy-on-write, not a runtime
    /// check. Pure + no UI so it is unit-testable on its own (AMA-2378 Task 5).
    static func applyRampSets(
        _ sourceSets: [RampSet],
        toEnabledRampsIn ramps: [PerExerciseRamp]
    ) -> [PerExerciseRamp] {
        ramps.map { ramp in
            guard ramp.enabled else { return ramp }
            var copy = ramp
            copy.sets = sourceSets
            return copy
        }
    }
}
