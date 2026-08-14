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
            .filter({ !$0.isChecked && comesAfter($0, focus: focus) })
            .min(by: setOrder) {
            return makeFocus(for: nextInExercise, exerciseID: current.id)
        }

        for later in entries.suffix(from: exerciseIndex + 1) {
            if let first = later.sets.filter({ !$0.isChecked }).min(by: setOrder) {
                return makeFocus(for: first, exerciseID: later.id)
            }
        }
        return nil
    }

    private static func comesAfter(_ set: SetActual, focus: LogbookWheelFocus) -> Bool {
        if set.index > focus.setIndex { return true }
        // Same index: warmup → working is still "next".
        if set.index == focus.setIndex, focus.isWarmup, !set.isWarmup {
            return true
        }
        return false
    }

    private static func setOrder(_ lhs: SetActual, _ rhs: SetActual) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.isWarmup && !rhs.isWarmup
    }

    private static func makeFocus(for set: SetActual, exerciseID: String) -> LogbookWheelFocus {
        LogbookWheelFocus(
            exerciseID: exerciseID,
            setIndex: set.index,
            isWarmup: set.isWarmup
        )
    }
}
