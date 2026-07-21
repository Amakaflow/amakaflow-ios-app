//
//  SocialImportDraft+Persistence.swift
//  AmakaFlow
//
//  AMA-2305 — preserve structureSource / type / restSec on Library save.
//  Hard guard: never persist inferred / explicit (unconfirmed) structure.
//

import Foundation

extension SocialImportDraft {
    /// Blocks sent to mapper — keep section labels but refresh exercise rows from the flat list.
    /// Unconfirmed provenance (`inferred` / `explicit`) is flattened to `sets` + `unknown`.
    func blocksForPersistence() -> [SocialImportBlock] {
        let reconciled: [SocialImportBlock]
        if blocks.isEmpty {
            reconciled = [
                SocialImportBlock(
                    label: "Main block",
                    rounds: 1,
                    exercises: exercises,
                    type: "sets",
                    structureSource: "unknown"
                )
            ]
        } else if blocks.count == 1 {
            let block = blocks[0]
            reconciled = [
                SocialImportBlock(
                    label: block.label ?? "Main block",
                    rounds: max(1, block.rounds),
                    exercises: exercises,
                    type: block.type,
                    restSec: block.restSec,
                    structureSource: block.structureSource
                )
            ]
        } else {
            reconciled = reconciledMultiBlocks()
        }
        return reconciled.flatMap(Self.sanitizeUnconfirmedStructure)
    }

    /// ADR-017: inferred/explicit must never reach `/workouts/save` as structured blocks.
    static func sanitizeUnconfirmedStructure(_ block: SocialImportBlock) -> [SocialImportBlock] {
        let source = block.structureSource?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard source == StructureSource.inferred.rawValue
            || source == StructureSource.explicit.rawValue else {
            return [block]
        }
        return block.exercises.map { exercise in
            SocialImportBlock(
                label: nil,
                rounds: 1,
                exercises: [exercise],
                type: "sets",
                restSec: nil,
                structureSource: StructureSource.unknown.rawValue
            )
        }
    }

    /// Reconcile multi-block rows with the flat editable list by exercise id.
    private func reconciledMultiBlocks() -> [SocialImportBlock] {
        let flatByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        var assignedIDs = Set<SocialImportExercise.ID>()
        var reconciled = blocks.map { block -> SocialImportBlock in
            let reconciledExercises = block.exercises.compactMap { flatByID[$0.id] }
            assignedIDs.formUnion(reconciledExercises.map(\.id))
            return SocialImportBlock(
                label: block.label,
                rounds: max(1, block.rounds),
                exercises: reconciledExercises,
                type: block.type,
                restSec: block.restSec,
                structureSource: block.structureSource
            )
        }
        let unassigned = exercises.filter { !assignedIDs.contains($0.id) }
        if !unassigned.isEmpty, let firstIndex = reconciled.indices.first {
            let block = reconciled[firstIndex]
            reconciled[firstIndex] = SocialImportBlock(
                label: block.label,
                rounds: block.rounds,
                exercises: block.exercises + unassigned,
                type: block.type,
                restSec: block.restSec,
                structureSource: block.structureSource
            )
        }
        return reconciled
    }
}
