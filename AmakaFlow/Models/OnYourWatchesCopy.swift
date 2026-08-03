//
//  OnYourWatchesCopy.swift
//  AmakaFlow
//
//  AMA-2375: user-facing copy for the watch workout manager.
//

import Foundation

enum OnYourWatchesCopy {
    static let overviewTitle = "On your watches"
    static let overviewSubtitle =
        "What each watch is holding right now — manage it here, not mid-send."
    static let overviewFootnote =
        "Send more from any workout’s Start flow, or straight from Library with the ⋯ menu."

    static let appleTitle = "Apple Watch"
    static let appleNativeHint = "NATIVE WORKOUT APP"
    static let appleCapFootnotePrefix = "APPLE CAPS SCHEDULED WORKOUTS AT"
    static let appleCapFootnoteSuffix = "— NOTHING AUTO-DELETES"
    static let appleOwnership =
        "Removing here clears it from the Workout app — the workout stays in your Library."
    static let appleScheduleCTA = "＋ Schedule from Library"
    static let appleRemoveAll = "Remove all from watch"
    static let appleRemoveAllTitle = "Remove all?"
    static let appleSlotsOf = "OF"
    static let appleSlotsLabel = "SLOTS"
    static let appleCapsShort = "APPLE CAPS SCHEDULED WORKOUTS"

    static func appleRemoveAllBody(count: Int) -> String {
        "Clears all \(count) scheduled workouts from the Workout app on your watch. Your Library keeps every workout — nothing is deleted there. This never happens automatically."
    }

    static func appleRemoveAllConfirm(count: Int) -> String {
        "Remove all \(count)"
    }

    static let garminTitle = "Garmin"
    static let garminViaWidget = "VIA THE AMAKAFLOW WIDGET"
    static let garminIntro =
        "Workouts land in the AmakaFlow widget on the watch — open it there to download. Garmin Connect may open during the handoff; that’s normal."
    static let garminOwnership =
        "Remove clears the queue entry — copies already on the watch clear on its next sync."
    static let garminPushCTA = "＋ Push from Library"
    static let garminSentHint = "SENT · OPEN THE WIDGET TO DOWNLOAD"
    static let garminFix = "Fix"
    static let garminRemove = "Remove"

    static let librarySummaryTitle = "On your watches"
    static let unscheduled = "UNSCHEDULED"
    static let edit = "Edit"
    static let done = "Done"
    static let move = "Move"
    static let cancel = "Cancel"

    static func appleSummaryLine(scheduled: Int, durationLabel: String?, slotsFree: Int) -> String {
        var parts = ["\(scheduled) SCHEDULED"]
        if let durationLabel, !durationLabel.isEmpty {
            parts.append(durationLabel)
        }
        parts.append("\(slotsFree) SLOT\(slotsFree == 1 ? "" : "S") FREE")
        return parts.joined(separator: " · ")
    }

    static func appleOverviewSub(scheduled: Int, nextLabel: String?) -> String {
        var parts = ["\(scheduled) SCHEDULED", appleNativeHint]
        if let nextLabel {
            parts.append("NEXT: \(nextLabel)")
        }
        return parts.joined(separator: " · ")
    }

    static func garminOverviewSub(onWatch: Int, waiting: Int, failed: Int) -> String {
        var parts: [String] = []
        parts.append("\(onWatch) ON WATCH")
        if waiting > 0 { parts.append("\(waiting) WAITING") }
        if failed > 0 { parts.append("\(failed) FAILED") }
        parts.append("VIA AMAKAFLOW WIDGET")
        return parts.joined(separator: " · ")
    }

    static func librarySummary(
        appleScheduled: Int?,
        garminOnWatch: Int?,
        garminFailed: Int?
    ) -> String {
        var parts: [String] = []
        if let appleScheduled {
            parts.append("APPLE · \(appleScheduled) SCHEDULED")
        }
        if let garminOnWatch {
            var g = "GARMIN · \(garminOnWatch) ON WATCH"
            if let garminFailed, garminFailed > 0 {
                g += " · \(garminFailed) FAILED"
            }
            parts.append(g)
        }
        return parts.joined(separator: " · ")
    }
}
