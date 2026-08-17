//
//  EditorV2SheetCommit.swift
//  AmakaFlow
//
//  AMA-2441 — diff-based sheet commit (field-level commands only, no clobber).
//

import Foundation

extension EditorV2Session {
    /// Commit a sheet-edited exercise by diffing the draft against the exercise
    /// as it was WHEN THE SHEET OPENED (`baseline`) and emitting only the fields
    /// the user actually changed, as field-level commands.
    ///
    /// The baseline matters: diffing against the *current* session state would
    /// make any field that changed underneath the open sheet (e.g. a concurrent
    /// add-set) look user-edited, and the stale draft value would clobber it —
    /// the exact bug this seam exists to prevent. If the user and a concurrent
    /// command both touched the same field, the user's value wins for that
    /// field only.
    mutating func commitSheetEdit(
        exerciseID: String,
        baseline: EditorV2Exercise,
        sheetDraft: EditorV2Exercise
    ) {
        guard exercises[exerciseID] != nil else {
            // Exercise was deleted while the sheet was open — nothing to commit.
            return
        }

        let commands = buildFieldCommands(
            exerciseID: exerciseID,
            draft: sheetDraft,
            baseline: baseline
        )

        for command in commands {
            _ = apply(command)
        }
    }

    private func buildFieldCommands(
        exerciseID: String,
        draft: EditorV2Exercise,
        baseline: EditorV2Exercise
    ) -> [EditorCommand] {
        [
            fieldCommand(draft.sets, baseline.sets) { .setExerciseSets(exerciseID, $0) },
            fieldCommand(draft.reps, baseline.reps) { .setExerciseReps(exerciseID, $0) },
            fieldCommand(draft.repsRange, baseline.repsRange) { .setExerciseRepsRange(exerciseID, $0) },
            fieldCommand(draft.durationSeconds, baseline.durationSeconds) { .setExerciseDuration(exerciseID, $0) },
            fieldCommand(draft.distanceMeters, baseline.distanceMeters) { .setExerciseDistance(exerciseID, $0) },
            fieldCommand(draft.weightKg, baseline.weightKg) { .setExerciseWeight(exerciseID, $0) },
            fieldCommand(draft.isBodyweight, baseline.isBodyweight) { .setExerciseBodyweight(exerciseID, $0) },
            fieldCommand(draft.restSeconds, baseline.restSeconds) { .setExerciseRest(exerciseID, $0) },
            fieldCommand(draft.calories, baseline.calories) { .setExerciseCalories(exerciseID, $0) },
            fieldCommand(draft.openGoal, baseline.openGoal) { .setExerciseOpenGoal(exerciseID, $0) }
        ].compactMap { $0 }
    }

    private func fieldCommand<T: Equatable>(
        _ draftValue: T,
        _ baselineValue: T,
        make: (T) -> EditorCommand
    ) -> EditorCommand? {
        draftValue != baselineValue ? make(draftValue) : nil
    }
}
