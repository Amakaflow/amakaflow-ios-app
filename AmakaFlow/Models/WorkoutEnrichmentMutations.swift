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
}
