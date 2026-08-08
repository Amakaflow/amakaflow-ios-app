//
//  WatchItemCopy.swift
//  AmakaFlow
//
//  AMA-2386 / AMA-2388: user-facing copy for the watch item sheet.
//

import Foundation

enum WatchItemCopy {
    static let sectionLabel = "WATCH READINESS — RESHAPE, THEN REPLACE"

    static let onWatchNow = "ON THE WATCH NOW"
    static let onWatchUpdated = "ON THE WATCH NOW · UPDATED JUST NOW"
    static let removeFromWatch = "Remove from watch"
    static let fromYourLibrary = "FROM YOUR LIBRARY"
    static let notLinked = "NOT LINKED TO A LIBRARY WORKOUT"
    static let openWorkoutSuffix = " — open workout ›"
    static let editedChip = "EDITED"
    static let stepsOverlayClose = "Close"
    static let stepsWatermark =
        "DELIVERED COPY · READ-ONLY — EDITS BELOW DON'T CHANGE THIS UNTIL YOU REPLACE"

    static let ctaIdle = "No changes yet"
    static let ctaUpdating = "Updating on watch…"
    static let ctaUpToDate = "Up to date ✓"

    static let toastPending = "Updating on watch…"
    static let toastReplaced = "Replaced ✓"
    static let toastQueueUpdated = "Queue updated ✓"
    static let toastSavedSub = "REPLACE ON WATCH TO UPDATE THE DELIVERED COPY"
    static let done = "Done"

    static func toastSaved(kind: EnrichmentSequenceKind) -> String {
        kind == .mobility ? "Sequence saved" : "Cooldown saved"
    }

    static let toastWarmupsSaved = "Warm-ups saved"

    /// Idle — no pending edits.
    static let applyNoteIdle =
        "Edits save to this workout — replacing sends them to the watch."
    /// Draft differs from delivered.
    static let applyNotePending =
        "Saved here — the watch still has the old copy until you replace. Same slot, nothing extra."
    /// After confirmed replace.
    static let applyNoteReplaced = "The watch has this exact copy."

    static let mobilityTitle = "Mobility prep"
    static let warmupsTitle = "Warm-up sets"
    static let restTitle = "Rest between sets"
    static let cooldownTitle = "Cooldown"

    static let garminWarmupsUnused = "NOT USED FOR EMOM"
    static let garminRestLap = "LAP TO ADVANCE"

    static func seeSteps(count: Int) -> String {
        let unit = count == 1 ? "step" : "steps"
        return "See the \(count) \(unit)"
    }

    static func stepsOverlayTitle(count: Int) -> String {
        let unit = count == 1 ? "step" : "steps"
        return "On the watch — \(count) \(unit)"
    }

    /// Uppercase ON THE WATCH pill (`1 STEP` / `9 STEPS`).
    static func stepsPill(count: Int) -> String {
        let normalized = max(count, 1)
        let unit = normalized == 1 ? "STEP" : "STEPS"
        return "\(normalized) \(unit)"
    }

    static func libraryRowTitle(workoutName: String) -> String {
        "\(workoutName)\(openWorkoutSuffix)"
    }

    static func replaceCTA(changeCount: Int) -> String {
        guard changeCount > 0 else { return ctaIdle }
        let unit = changeCount == 1 ? "change" : "changes"
        return "Replace on watch · \(changeCount) \(unit)"
    }

    static func applyNote(hasChanges: Bool, isUpToDate: Bool) -> String {
        if isUpToDate { return applyNoteReplaced }
        if hasChanges { return applyNotePending }
        return applyNoteIdle
    }

    static func toastSuccess(isApple: Bool) -> String {
        isApple ? toastReplaced : toastQueueUpdated
    }
}
