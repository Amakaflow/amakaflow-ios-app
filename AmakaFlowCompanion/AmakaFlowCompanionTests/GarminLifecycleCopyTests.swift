//
//  GarminLifecycleCopyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2317: the dogfood questions these strings have to answer —
//  "why 60s rest", "is my code one-time", "did Delete touch the watch".
//

import XCTest
@testable import AmakaFlowCompanion

final class GarminLifecycleCopyTests: XCTestCase {

    // MARK: - Push prefs visibility

    func testStartSheetNoteMarksUnconfiguredPrefsAsDefaults() {
        let note = GarminLifecycleCopy.startSheetPrefsNote(prefs: .dogfood, hasConfigured: false)
        XCTAssertTrue(note.contains("defaults"), "Unconfigured prefs must not read as a deliberate choice: \(note)")
        XCTAssertTrue(note.contains(GarminWatchDisplayPrefs.dogfood.summaryLine))
    }

    func testStartSheetNoteDropsDefaultsMarkerOnceConfigured() {
        let note = GarminLifecycleCopy.startSheetPrefsNote(prefs: .dogfood, hasConfigured: true)
        XCTAssertFalse(note.contains("defaults"))
        XCTAssertTrue(note.contains("Watch display:"))
    }

    func testTimedRestWarnsAboutTheCountdown() {
        let hint = GarminLifecycleCopy.startSheetPrefsHint(prefs: .dogfood, hasConfigured: true)
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint?.contains("Lap") == true, "Hint must point at the fix: \(hint ?? "nil")")
    }

    func testUnconfiguredTimedRestNamesTheDefaultDuration() {
        let hint = GarminLifecycleCopy.startSheetPrefsHint(prefs: .dogfood, hasConfigured: false)
        XCTAssertEqual(hint?.contains("60"), true, "The surprise 60s must be stated up front: \(hint ?? "nil")")
    }

    func testLapAndOmitRestNeedNoWarning() {
        for restMode in [GarminRestMode.lap, .omit] {
            let prefs = GarminWatchDisplayPrefs(exerciseEnd: .lap, restMode: restMode, defaultRestSec: 60)
            XCTAssertNil(
                GarminLifecycleCopy.startSheetPrefsHint(prefs: prefs, hasConfigured: true),
                "\(restMode) rest has no countdown to warn about"
            )
        }
    }

    // MARK: - Handoff

    func testHandoffCopyNamesGarminConnectAndDeniesCrash() {
        XCTAssertTrue(GarminLifecycleCopy.handoffOpeningGarmin.contains("Garmin Connect"))
        XCTAssertTrue(GarminLifecycleCopy.handoffNextSteps.lowercased().contains("not a crash"))
    }

    func testRestoredHandoffKeepsTheOriginalMessage() {
        let restored = GarminLifecycleCopy.handoffRestored(message: "Sent to Garmin — open CIQ widget.")
        XCTAssertTrue(restored.hasPrefix(GarminLifecycleCopy.handoffRestoredPrefix))
        XCTAssertTrue(restored.contains("Sent to Garmin"))
    }

    // MARK: - Pairing lifecycle

    func testPairCodeCopySaysOneTimeAndPersistent() {
        let copy = GarminLifecycleCopy.pairCodeLifecycle
        XCTAssertTrue(copy.contains("one-time"))
        XCTAssertTrue(copy.contains("until you remove"))
        XCTAssertFalse(copy.contains("each time"), "Must not imply re-entry per push: \(copy)")
    }

    func testPairedCaptionDoesNotImplyReEntry() {
        XCTAssertTrue(GarminLifecycleCopy.pairedLifecycleCaption.contains("stays paired"))
    }

    func testNotPairedCaptionSaysWhereTheCodeComesFrom() {
        XCTAssertTrue(GarminLifecycleCopy.notPairedLifecycleCaption.contains("widget"))
        XCTAssertTrue(GarminLifecycleCopy.notPairedLifecycleCaption.contains("6-digit"))
    }

    func testSettingsDistinguishesConnectMobileFromConnectIQPairing() {
        let copy = GarminLifecycleCopy.settingsPairingDistinction
        XCTAssertTrue(copy.contains("Garmin Connect Mobile"))
        XCTAssertTrue(copy.contains("Devices"))
    }

    // MARK: - Delete / remove semantics

    func testRemoveDeviceSaysUnpairOnly() {
        let copy = GarminLifecycleCopy.removeDeviceMessage
        XCTAssertTrue(copy.contains("unpairs"))
        XCTAssertTrue(copy.contains("Strength Workouts"), "Must say where watch copies live: \(copy)")
    }

    func testDeletingAWorkoutWarnsWatchCopiesSurvive() {
        let copy = GarminLifecycleCopy.deleteWorkoutMessage(name: "Lower body", isWorkout: true)
        XCTAssertTrue(copy.contains("“Lower body”"))
        XCTAssertTrue(copy.contains("Strength Workouts"))
    }

    func testDeletingKnowledgeSkipsTheGarminCaveat() {
        let copy = GarminLifecycleCopy.deleteWorkoutMessage(name: "Zone two", isWorkout: false)
        XCTAssertFalse(copy.contains("Strength Workouts"), "Articles never reach the watch: \(copy)")
        XCTAssertTrue(copy.contains("import it again later"))
    }

    func testDeviceScopeNotePointsAtWatchSideDeletion() {
        XCTAssertTrue(GarminLifecycleCopy.deviceScopeNote.contains("on the watch itself"))
    }
}
