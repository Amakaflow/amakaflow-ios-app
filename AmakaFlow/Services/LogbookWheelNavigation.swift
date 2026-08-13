//
//  LogbookWheelNavigation.swift
//  AmakaFlow
//
//  AMA-2426: "Next set ›" chaining — next unchecked set, then next exercise, stop at last.
//

import Foundation

enum LogbookWheelNavigation {
    /// Advance from the current focus to the next unchecked set.
    /// Same exercise first; then later exercises; nil when nothing left.
    static func nextUnchecked(
        after focus: LogbookWheelFocus,
        in entries: [LogbookExerciseEntry]
    ) -> LogbookWheelFocus? {
        guard let exerciseIndex = entries.firstIndex(where: { $0.id == focus.exerciseID }) else {
            return nil
        }

        let current = entries[exerciseIndex]
        if let nextInExercise = current.sets
            .filter({ !$0.isChecked && $0.index > focus.setIndex })
            .sorted(by: { $0.index < $1.index })
            .first {
            return LogbookWheelFocus(exerciseID: current.id, setIndex: nextInExercise.index)
        }

        // Also consider unchecked sets at or before focus that were skipped? Ticket:
        // "advances to next unchecked set" — forward only within exercise, then next exercises.
        for later in entries.suffix(from: exerciseIndex + 1) {
            if let first = later.sets.filter({ !$0.isChecked }).sorted(by: { $0.index < $1.index }).first {
                return LogbookWheelFocus(exerciseID: later.id, setIndex: first.index)
            }
        }
        return nil
    }
}
