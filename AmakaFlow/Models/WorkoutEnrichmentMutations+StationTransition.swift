//
//  WorkoutEnrichmentMutations+StationTransition.swift
//  AmakaFlow
//
//  AMA-2423 — station_transition block writes, validation and the
//  multi-station shape test. Split from WorkoutEnrichmentMutations.swift for
//  SwiftLint type_body_length.
//

import Foundation

extension WorkoutEnrichmentMutations {
    /// AMA-2423 — block-level station_transition fields (mirrors `restSecKey`/`restOpenKey`).
    static let transitionSecKey = "transition_sec"
    static let transitionOpenKey = "transition_open"

    /// AMA-2423 — mirrors backend `_MULTI_STATION_TYPES`: circuit / superset /
    /// timed_circuit / timed_round blocks with 2+ exercises are "stations" and
    /// the only shape station_transition ever writes to. Narrower than the
    /// format-owned set (emom/tabata/for-time/amrap stay on between_set_rest).
    private static let multiStationFormatGroupTypes: Set<String> = [
        "circuit", "superset", "timed_circuit", "timed_round"
    ]

    /// AMA-2423 — mirrors backend `_is_multi_station_format_group`. A 1-station
    /// "circuit" behaves like straight sets (Rest between sets, not Transition).
    static func isMultiStationFormatGroup(_ block: [String: Any]) -> Bool {
        guard multiStationFormatGroupTypes.contains(resolvedBlockKind(block)) else { return false }
        let exerciseCount = (block["exercises"] as? [[String: Any]])?.count ?? 0
        return exerciseCount >= 2
    }

    /// AMA-2423 — `SocialImportBlock` overload of `isMultiStationFormatGroup`,
    /// for the push planner's presence checks (which never round-trip through
    /// raw `blocks_json`). Same rule: circuit/superset/timed_circuit/timed_round
    /// with 2+ exercises only.
    static func isMultiStationFormatGroup(_ block: SocialImportBlock) -> Bool {
        let kind = (block.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard multiStationFormatGroupTypes.contains(kind) else { return false }
        return block.exercises.count >= 2
    }

    static func stampTransitionEnrichmentDefault(fieldProvenance: inout [String: ProvSource]) {
        fieldProvenance[transitionSecKey] = .enrichmentDefault
        fieldProvenance[transitionOpenKey] = .enrichmentDefault
    }

    static func stampTransitionUser(fieldProvenance: inout [String: ProvSource]) {
        fieldProvenance[transitionSecKey] = .user
        fieldProvenance[transitionOpenKey] = .user
    }

    /// AMA-2423 — reject contradictory transition intent, mirrors `validatedRest`.
    static func validatedTransition(
        transitionSec: Int?,
        transitionOpen: Bool
    ) throws -> (transitionSec: Int?, transitionOpen: Bool) {
        if transitionOpen, transitionSec != nil {
            throw WorkoutPreferencesValidationError.transitionOpenWithTransitionSec
        }
        return (transitionSec, transitionOpen)
    }

    /// AMA-2423 — write declared station_transition intent onto every
    /// multi-station format-group block and unconditionally clear stale
    /// `rest_open`/`rest_sec` (+ provenance) on that same block, mirroring
    /// backend `_apply_station_transition` / `_clear_stale_rest`. Non-eligible
    /// blocks (straight sets, emom/tabata/for-time/amrap, 1-station "circuit")
    /// pass through untouched — station_transition never writes there.
    static func applyStationTransition(
        in blocksJSON: [String: Any],
        transitionSec: Int?,
        transitionOpen: Bool
    ) -> [String: Any] {
        guard let rawBlocks = blocksJSON["blocks"] as? [[String: Any]] else { return blocksJSON }
        var blocks: [[String: Any]] = []
        blocks.reserveCapacity(rawBlocks.count)
        for var block in rawBlocks {
            guard isMultiStationFormatGroup(block) else {
                blocks.append(block)
                continue
            }
            block[transitionSecKey] = transitionSec.map { $0 as Any } ?? NSNull()
            block[transitionOpenKey] = transitionOpen
            block.removeValue(forKey: restSecKey)
            block.removeValue(forKey: restOpenKey)

            var prov = block["field_provenance"] as? [String: Any] ?? [:]
            prov.removeValue(forKey: restSecKey)
            prov.removeValue(forKey: restOpenKey)
            prov[transitionSecKey] = ProvSource.enrichmentDefault.rawValue
            prov[transitionOpenKey] = ProvSource.enrichmentDefault.rawValue
            block["field_provenance"] = prov

            blocks.append(block)
        }
        var out = blocksJSON
        out["blocks"] = blocks
        return out
    }

    /// AMA-2423 — remove block-level station_transition intent (+ provenance)
    /// so an unchecked Transition offer can opt out, mirroring `clearBlockRestIntent`.
    static func clearBlockTransitionIntent(in blocksJSON: [String: Any]) -> [String: Any] {
        guard let rawBlocks = blocksJSON["blocks"] as? [[String: Any]] else { return blocksJSON }
        var blocks: [[String: Any]] = []
        blocks.reserveCapacity(rawBlocks.count)
        for var block in rawBlocks {
            block.removeValue(forKey: transitionSecKey)
            block.removeValue(forKey: transitionOpenKey)
            if var prov = block["field_provenance"] as? [String: Any] {
                prov.removeValue(forKey: transitionSecKey)
                prov.removeValue(forKey: transitionOpenKey)
                if prov.isEmpty {
                    block.removeValue(forKey: "field_provenance")
                } else {
                    block["field_provenance"] = prov
                }
            }
            blocks.append(block)
        }
        var out = blocksJSON
        out["blocks"] = blocks
        return out
    }
}
