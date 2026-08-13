//
//  LogbookCopy.swift
//  AmakaFlow
//
//  AMA-2426: user-facing copy for logbook doors + grid.
//

import Foundation

enum LogbookCopy {
    static let modeSelectTitle = "What you actually did"
    static let quickTitle = "Quick — as planned / adjust"
    static let quickSubtitle = "One tap per exercise. The flow you already know."
    static let setBySetTitle = "Set by set — the logbook"
    static let setBySetSubtitle =
        "Per-set detail (KG × REPS), ghosts from last time, wheel entry — like a paper notepad."
    static let newBadge = "NEW"

    static let logSessionTitle = "Log a session"
    static let logSessionSubtitle = "Already trained? Write it down — set by set"
    static let logPastSessionTitle = "Log a past session"
    static let logPastSessionSubtitle = "Fill the logbook from this plan"

    static let columnSet = "SET"
    static let columnLast = "LAST TIME"
    static let columnKg = "KG"
    static let columnReps = "REPS"

    static let sameAsLast = "Same as last time"
    static let nextSet = "Next set ›"
    static let addSet = "＋ Add set"
    static let notesPlaceholder = "NOTES"
    static let pickWorkoutTitle = "Pick a workout"
    static let startBlank = "Start blank"
    static let undoTimeoutToast = "Logged without a watch — Undo"
    static let garminFilled = "FROM GARMIN — ALREADY FILLED"

    static let modeQuickAccessibilityID = "af_logbook_mode_quick"
    static let modeSetBySetAccessibilityID = "af_logbook_mode_set_by_set"
    static let logSessionAccessibilityID = "af_add_log_session"
    static let logPastAccessibilityID = "af_workout_log_past_session"
    static let saveAccessibilityID = "af_logbook_save"
    static let screenAccessibilityID = "af_logbook_screen"

    static func columnWeight(for unit: WeightUnit) -> String {
        WeightUnitMath.unitLabel(unit)
    }
}
