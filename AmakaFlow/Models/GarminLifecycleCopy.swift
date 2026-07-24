//
//  GarminLifecycleCopy.swift
//  AmakaFlow
//
//  AMA-2317: dogfood copy for the Garmin lifecycle — what a push applies,
//  how long a pairing lasts, and what Delete/Remove actually removes.
//
//  Pure strings so the semantics can be unit-tested without a view.
//

import Foundation

enum GarminLifecycleCopy {
    // MARK: - Push prefs visibility (dogfood item 1)

    /// Start sheet line showing the display prefs that this push will send.
    static func startSheetPrefsNote(prefs: GarminWatchDisplayPrefs, hasConfigured: Bool) -> String {
        hasConfigured
            ? "Watch display: \(prefs.summaryLine)"
            : "Watch display (defaults): \(prefs.summaryLine)"
    }

    /// Hint under the Start sheet prefs note — only nags when rest is still timed.
    static func startSheetPrefsHint(prefs: GarminWatchDisplayPrefs, hasConfigured: Bool) -> String? {
        guard prefs.restMode == .timed else { return nil }
        return hasConfigured
            ? "Rest counts down. Tap to switch to Lap if you don't want a timer."
            : "You haven't chosen yet — rest will count down \(prefs.defaultRestSec)s when the workout doesn't prescribe one."
    }

    static let startSheetPrefsAction = "Change"

    // MARK: - Handoff (dogfood item 2)

    static let handoffQueueing = "Queueing for Garmin…"

    /// Shown between a successful push and the CIQ open request, so the
    /// app-switch/watch wake never reads as a crash.
    static let handoffOpeningGarmin = "Sent to Garmin — opening Garmin Connect to hand off…"

    /// Re-shown when the screen comes back after a suspend, an app switch, or a
    /// relaunch — the status the user was looking at must not vanish.
    static let handoffRestoredPrefix = "Last Garmin push:"

    static func handoffRestored(message: String) -> String {
        "\(handoffRestoredPrefix) \(message)"
    }

    /// Next steps card under the status line after a successful push.
    static let handoffNextSteps = """
    AmakaFlow may switch to Garmin Connect while the watch downloads. \
    That's the handoff, not a crash — come back here any time and this status will still be waiting.
    """

    // MARK: - Pairing lifecycle (dogfood item 3)

    static let pairSheetTitle = "Add Garmin"

    static let pairSheetSubtitle = "Enter the code shown on your Garmin watch"

    /// The single most-asked dogfood question: is the code one-time?
    static let pairCodeLifecycle = """
    The 6-digit code is one-time. Once it's accepted this iPhone stays paired \
    until you remove the watch here — you won't be asked for a new code each push.
    """

    /// Caption on a paired device row.
    static let pairedLifecycleCaption = "Paired · stays paired until you remove it"

    /// Devices empty state — tells the user where a code comes from.
    static let notPairedLifecycleCaption = "Not paired — open the AmakaFlow widget on your watch to get a 6-digit code."

    /// Codes expire before they're used, pairings don't.
    static let pairCodeExpired = "Codes expire after a few minutes. If yours is rejected, open the widget again for a fresh one."

    /// Settings hosts the Garmin Connect Mobile device link, which is a
    /// different thing from the Connect IQ pairing that Start → Garmin uses.
    static let settingsPairingDistinction = """
    This links Garmin Connect Mobile for activity sync. Start → Garmin uses the \
    Connect IQ pairing in Profile → Devices, which stays paired until you remove it.
    """

    // MARK: - Delete / remove semantics (dogfood item 4)

    static let removeDeviceTitle = "Remove this device?"

    static let removeDeviceMessage = """
    This unpairs the watch from AmakaFlow only. Workouts already downloaded stay on the watch \
    under Strength Workouts until you delete them there. You'll need a new 6-digit code to pair again.
    """

    static let deleteWorkoutTitle = "Delete from Library?"

    /// Workouts can already be sitting on the watch; deleting here won't touch them.
    static func deleteWorkoutMessage(name: String, isWorkout: Bool) -> String {
        let base = "“\(name)” will be removed from AmakaFlow. You can import it again later."
        guard isWorkout else { return base }
        return base + " Copies already sent to Garmin stay on the watch under Strength Workouts until you delete them there."
    }

    /// Devices screen footer covering both "unpair" and "delete on watch".
    static let deviceScopeNote = """
    Removing a device here only unpairs it. To free watch storage, delete old AmakaFlow \
    workouts on the watch itself under Strength Workouts.
    """
}
