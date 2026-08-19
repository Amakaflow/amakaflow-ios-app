//
//  LogbookCopy.swift
//  AmakaFlow
//
//  AMA-2426: user-facing copy for logbook doors + grid.
//

import Foundation

enum LogbookCopy {
    /// Timing-neutral — logbook is used live, beside watch, and after.
    static let modeSelectTitle = "Log your sets"
    static let quickTitle = "Quick — as planned / adjust"
    static let quickSubtitle = "One tap per exercise. Best once the session is done."
    static let setBySetTitle = "Set by set — the logbook"
    static let setBySetSubtitle =
        "Per-set KG × REPS during the workout or after — ghosts, wheels, like a paper notepad."
    static let newBadge = "NEW"

    static let logSessionTitle = "Log sets"
    static let logSessionSubtitle = "During or after — write them set by set"
    static let logPastSessionTitle = "Log sets"
    static let logPastSessionSubtitle = "Open the notepad for this plan — now or later"
    static let logSetsLiveTitle = "Log sets"
    static let logSetsLiveSubtitle = "Phone is tracking — write weights as you go"
    static let logSetsBesideWatchTitle = "Log sets beside watch"
    static let logSetsBesideWatchSubtitle =
        "Watch runs the plan. Phone is the notepad — merges when the session lands."
    static let companionPendingBanner = "COMPANION · PENDING · NOT ON TODAY UNTIL RECONCILE"
    static let liveLoggingBanner = "LIVE · logging on phone"

    static let columnSet = "SET"
    static let columnLast = "LAST TIME"
    static let columnReps = "REPS"

    static let sameAsLast = "Same as last time"
    static let nextSet = "Next set ›"
    static let doneMetric = "Done ›"
    static let addSet = "＋ Add set"
    static let columnTime = "TIME"
    static let columnCal = "CAL"
    static let columnKm = "KM"

    /// AMA-2462 — the distance column names the unit it is actually showing.
    static func distanceColumn(scale: LogbookDistanceScale, unit: DistanceUnit) -> String {
        switch scale {
        case .machineMetres: return "M"
        case .road: return unit == .km ? "KM" : "MI"
        }
    }
    static let columnHr = "HR"
    static let notesPlaceholder = "NOTES"
    static let pickWorkoutTitle = "Pick a workout"
    static let startBlank = "Start blank"
    static let undoTimeoutToast = "Logged without a watch — Undo"
    static let garminFilled = "FROM GARMIN — ALREADY FILLED"

    static let modeQuickAccessibilityID = "af_logbook_mode_quick"
    static let modeSetBySetAccessibilityID = "af_logbook_mode_set_by_set"
    static let logSessionAccessibilityID = "af_add_log_session"
    static let headerLogAccessibilityID = "af_header_log_sets"
    static let logPastAccessibilityID = "af_workout_log_past_session"
    static let logSetsLiveAccessibilityID = "af_player_log_sets"
    static let logSetsBesideWatchAccessibilityID = "af_workout_log_sets_beside_watch"
    static let saveAccessibilityID = "af_logbook_save"
    static let screenAccessibilityID = "af_logbook_screen"

    static func columnWeight(for unit: WeightUnit) -> String {
        WeightUnitMath.unitLabel(unit)
    }

    /// AMA-2462 — a load on a bodyweight movement is ADDED load, and the column
    /// has to say so. "+LB" is what stops a belted chin-up reading as 200 lb.
    static func columnWeight(for unit: WeightUnit, added: Bool) -> String {
        added ? "+\(WeightUnitMath.unitLabel(unit))" : WeightUnitMath.unitLabel(unit)
    }
}
