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
            return
        }
        
        let commands = buildFieldCommands(
            exerciseID: exerciseID,
            draft: sheetDraft,
            current: current
        )
        
        for command in commands {
            _ = apply(command)
        }
    }
    
    private func buildFieldCommands(
        exerciseID: String,
        draft: EditorV2Exercise,
        current: EditorV2Exercise
    ) -> [EditorCommand] {
        [
            fieldCommand(draft.sets, current.sets) { .setExerciseSets(exerciseID, $0) },
            fieldCommand(draft.reps, current.reps) { .setExerciseReps(exerciseID, $0) },
            fieldCommand(draft.repsRange, current.repsRange) { .setExerciseRepsRange(exerciseID, $0) },
            fieldCommand(draft.durationSeconds, current.durationSeconds) { .setExerciseDuration(exerciseID, $0) },
            fieldCommand(draft.distanceMeters, current.distanceMeters) { .setExerciseDistance(exerciseID, $0) },
            fieldCommand(draft.weightKg, current.weightKg) { .setExerciseWeight(exerciseID, $0) },
            fieldCommand(draft.isBodyweight, current.isBodyweight) { .setExerciseBodyweight(exerciseID, $0) },
            fieldCommand(draft.restSeconds, current.restSeconds) { .setExerciseRest(exerciseID, $0) },
            fieldCommand(draft.calories, current.calories) { .setExerciseCalories(exerciseID, $0) },
            fieldCommand(draft.openGoal, current.openGoal) { .setExerciseOpenGoal(exerciseID, $0) }
        ].compactMap { $0 }
    }
    
    private func fieldCommand<T: Equatable>(
        _ draftValue: T,
        _ currentValue: T,
        make: (T) -> EditorCommand
    ) -> EditorCommand? {
        draftValue != currentValue ? make(draftValue) : nil
    }
}
