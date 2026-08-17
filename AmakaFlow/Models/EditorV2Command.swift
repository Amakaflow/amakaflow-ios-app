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
    /// Deprecated: Use field-level commands (setExerciseSets, setExerciseReps, etc.) instead.
    /// This command is reimplemented as a diff to prevent stale-sheet clobber.
    case updatePrescription(String, EditorV2Exercise)
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
    case addBlock(EditorV2GroupType)
    case move(String, Int)
    case reorder(fromOffsets: IndexSet, toOffset: Int)
    case quickAddSoftSection(EnrichmentKind)
    case removeSoftSection(EditorV2GroupType, EnrichmentKind)
    case addSet(String)
}

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
        var copy = self
        let result = copy.applyD2(command)
        
        switch result {
        case .applied:
            copy.normalizeD2()
            let validation = copy.validateD2()
            if validation == .applied {
                self = copy
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
