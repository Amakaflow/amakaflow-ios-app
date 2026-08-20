//
//  EditorV2Command.swift
//  AmakaFlow
//
//  AMA-2438 P0 — typed command door + transactional apply (spec D1).
//

import Foundation

enum EditorCommand: Equatable, Sendable {
    case addExercises(names: [String], into: String?)
    case removeExercise(String)
    case replaceExercise(String, with: String)
    case setExerciseSets(String, Int?)
    case setExerciseReps(String, Int?)
    case setExerciseRepsRange(String, RepsRange?)
    case setExerciseDuration(String, Int?)
    case setExerciseDistance(String, Int?)
    case setExerciseWeight(String, Double?)
    case setExerciseBodyweight(String, Bool)
    case setExerciseRest(String, Int?)
    case setExerciseCalories(String, Int?)
    case setExerciseOpenGoal(String, Bool)
    case pairSuperset(source: String, target: String)
    case removeFromGroup(String)
    case switchGroupType(String, EditorV2GroupType)
    case updateGroupConfig(String, EditorV2GroupConfig)
    case ungroup(String)
    case deleteGroup(String)
    /// Start over: REPLACES the canvas with a single empty group of `type`,
    /// discarding every exercise, group and row. Destructive by design.
    ///
    /// Only reachable where there is nothing to lose: the empty-state chips and
    /// the explicit "Change workout type?" confirm. Every mid-workout door —
    /// canvas "＋ Add a block" and the picker's quick-block chips — goes through
    /// `beginFormatGroup` instead (AMA-2443 slice 4).
    case addBlock(EditorV2GroupType)
    case move(String, Int)
    case reorder(fromOffsets: IndexSet, toOffset: Int)
    /// Reorder exercises INSIDE one block (mutates `memberIDs`); the block's
    /// own position in `order` is untouched.
    case reorderGroupMembers(key: String, fromOffsets: IndexSet, toOffset: Int)
    case quickAddSoftSection(EnrichmentKind, activities: [EnrichmentActivity], clearingTombstone: Bool)
    case removeSoftSection(EditorV2GroupType, EnrichmentKind)
    case addSet(String)
    /// AMA-2443 slice 4 — APPEND a new empty format group and pin it, without
    /// touching existing rows. Generalizes the superset "＋ Another superset"
    /// flow to every format type. The pin move happens inside `apply()`, so a
    /// single undo restores both the pin and the appended group.
    ///
    /// The new group is legal while empty because it is `formatGroupKey`
    /// (invariant I2 exempts the pin); if the user abandons it and pins
    /// something else, `pruneEmptyGroupsD2()` removes it on the next normalize.
    case beginFormatGroup(type: EditorV2GroupType, preferredName: String?)
    case addWarmupSets(exerciseID: String, rows: [WarmupSetRow], clearingTombstone: Bool)
    case removeWarmupSets(exerciseID: String)
}

// `updatePrescription` (whole-object replace) was REMOVED (AMA-2441): with only
// a stale draft and no baseline it cannot distinguish user edits from concurrent
// changes, so it is clobber-unsafe by construction. Sheet commits go through
// `commitSheetEdit(exerciseID:baseline:sheetDraft:)`; everything else uses the
// field-level commands above.

enum ApplyResult: Equatable {
    case applied
    case rejected(Violation)
}

enum Violation: String, Equatable {
    case exerciseNotFound
    case groupNotFound
    case invalidGroupMembership
    case emptyGroup
    case duplicateIDs
    case unresolvedReferences
    case formatGroupMissing
    case invalidState
}

extension EditorV2Session {
    mutating func apply(_ command: EditorCommand) -> ApplyResult {
        apply(command, recordUndo: true)
    }

    /// The ONE transactional door — copy → applyD2 → normalize → validate →
    /// commit. `recordUndo: false` is for grouped gestures (sheet commit)
    /// whose single group snapshot was already pushed via `beginUndoGroup()`;
    /// there must never be a second copy of this sequence anywhere.
    mutating func apply(_ command: EditorCommand, recordUndo: Bool) -> ApplyResult {
        // Capture pre-state for undo
        let preState = self

        var copy = self
        let result = copy.applyD2(command)

        switch result {
        case .applied:
            copy.normalizeD2()
            let validation = copy.validateD2()
            if validation == .applied {
                // Check if state actually changed
                let stateChanged = copy != preState
                self = copy

                // Push snapshot only if state changed
                if recordUndo && stateChanged {
                    pushUndoSnapshot(EditorV2SessionSnapshot(from: preState))
                }

                return .applied
            } else {
                assertionFailure("Command produced invalid state: \(command)")
                return validation
            }
        case .rejected:
            return result
        }
    }
}
