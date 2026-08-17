//
//  EditorV2SheetCommit.swift
//  AmakaFlow
//
//  AMA-2441 — diff-based sheet commit (field-level commands only, no clobber).
//

import Foundation

extension EditorV2Session {
    /// Commit a sheet-edited exercise by diffing against the CURRENT session state
    /// and emitting only changed fields as field-level commands. Never writes the
    /// whole captured object to prevent stale-sheet clobber.
    mutating func commitSheetEdit(exerciseID: String, sheetDraft: EditorV2Exercise) {
        guard let current = exercises[exerciseID] else {
            // Exercise was deleted while sheet was open - nothing to commit
            return
        }
        
        // Diff each field and apply field-level commands for changes only
        
        // Sets
        if sheetDraft.sets != current.sets {
            _ = apply(.setExerciseSets(exerciseID, sheetDraft.sets))
        }
        
        // Reps (mutually exclusive with repsRange)
        if sheetDraft.reps != current.reps {
            _ = apply(.setExerciseReps(exerciseID, sheetDraft.reps))
        }
        
        // Reps range (mutually exclusive with reps)
        if sheetDraft.repsRange != current.repsRange {
            _ = apply(.setExerciseRepsRange(exerciseID, sheetDraft.repsRange))
        }
        
        // Duration
        if sheetDraft.durationSeconds != current.durationSeconds {
            _ = apply(.setExerciseDuration(exerciseID, sheetDraft.durationSeconds))
        }
        
        // Distance
        if sheetDraft.distanceMeters != current.distanceMeters {
            _ = apply(.setExerciseDistance(exerciseID, sheetDraft.distanceMeters))
        }
        
        // Weight (mutually exclusive with isBodyweight)
        if sheetDraft.weightKg != current.weightKg {
            _ = apply(.setExerciseWeight(exerciseID, sheetDraft.weightKg))
        }
        
        // Bodyweight flag (mutually exclusive with weightKg)
        if sheetDraft.isBodyweight != current.isBodyweight {
            _ = apply(.setExerciseBodyweight(exerciseID, sheetDraft.isBodyweight))
        }
        
        // Rest
        if sheetDraft.restSeconds != current.restSeconds {
            _ = apply(.setExerciseRest(exerciseID, sheetDraft.restSeconds))
        }
        
        // Calories
        if sheetDraft.calories != current.calories {
            _ = apply(.setExerciseCalories(exerciseID, sheetDraft.calories))
        }
        
        // Open goal
        if sheetDraft.openGoal != current.openGoal {
            _ = apply(.setExerciseOpenGoal(exerciseID, sheetDraft.openGoal))
        }
    }
}
