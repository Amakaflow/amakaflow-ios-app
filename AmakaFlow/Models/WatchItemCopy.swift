//
//  WatchItemCopy.swift
//  AmakaFlow
//
//  AMA-2386: user-facing copy for the watch item sheet (edit readiness & replace).
//

import Foundation

enum WatchItemCopy {
    static let sectionLabel = "WATCH READINESS — RESHAPE, THEN REPLACE"

    static let seeSteps = "See steps ›"
    static let removeFromWatch = "Remove from watch"
    static let openWorkout = "Open workout ›"

    static let ctaIdle = "No changes yet"
    static let ctaUpdating = "Updating on watch…"

    static let toastPending = "Updating on watch…"
    static let toastReplaced = "Replaced ✓"
    static let toastQueueUpdated = "Queue updated ✓"

    static let appleReplaceNote =
        "Replaces the scheduled copy — same slot, same time. The Workout app never sees the old version again."
    static let garminReplaceNote =
        "Swaps the queued file. Already downloaded? The watch copy updates on its next widget sync."

    static let mobilityTitle = "Mobility prep"
    static let warmupsTitle = "Warm-up sets"
    static let restTitle = "Rest between sets"
    static let cooldownTitle = "Cooldown"

    static let garminWarmupsUnused = "NOT USED FOR EMOM"
    static let garminRestLap = "LAP TO ADVANCE"

    static func replaceCTA(changeCount: Int) -> String {
        guard changeCount > 0 else { return ctaIdle }
        let unit = changeCount == 1 ? "change" : "changes"
        return "Replace on watch · \(changeCount) \(unit)"
    }

    static func replaceNote(isApple: Bool) -> String {
        isApple ? appleReplaceNote : garminReplaceNote
    }

    static func toastSuccess(isApple: Bool) -> String {
        isApple ? toastReplaced : toastQueueUpdated
    }
}
