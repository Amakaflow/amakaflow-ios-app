//
//  WatchItemCopyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2386 / AMA-2388: copy-lock for watch item sheet.
//

import XCTest
@testable import AmakaFlowCompanion

final class WatchItemCopyTests: XCTestCase {
    func testIdleAndLitCTA() {
        XCTAssertEqual(WatchItemCopy.replaceCTA(changeCount: 0), "No changes yet")
        XCTAssertEqual(WatchItemCopy.replaceCTA(changeCount: 1), "Replace on watch · 1 change")
        XCTAssertEqual(WatchItemCopy.replaceCTA(changeCount: 2), "Replace on watch · 2 changes")
    }

    func testApplyNotes() {
        XCTAssertTrue(WatchItemCopy.applyNote(hasChanges: false, isUpToDate: false).contains("Edits save"))
        XCTAssertTrue(WatchItemCopy.applyNote(hasChanges: true, isUpToDate: false).contains("Saved here"))
        XCTAssertTrue(WatchItemCopy.applyNote(hasChanges: false, isUpToDate: true).contains("exact copy"))
    }

    func testToastStrings() {
        XCTAssertEqual(WatchItemCopy.toastPending, "Updating on watch…")
        XCTAssertEqual(WatchItemCopy.toastSuccess(isApple: true), "Replaced ✓")
        XCTAssertEqual(WatchItemCopy.toastSuccess(isApple: false), "Queue updated ✓")
        XCTAssertEqual(WatchItemCopy.ctaUpToDate, "Up to date ✓")
    }

    func testSeeStepsAndLibrary() {
        XCTAssertEqual(WatchItemCopy.seeSteps(count: 9), "See the 9 steps")
        XCTAssertEqual(
            WatchItemCopy.libraryRowTitle(workoutName: "Full Body"),
            "Full Body — open workout ›"
        )
        XCTAssertEqual(WatchItemCopy.notLinked, "NOT LINKED TO A LIBRARY WORKOUT")
    }

    func testSaveToasts() {
        XCTAssertEqual(WatchItemCopy.toastSaved(kind: .mobility), "Sequence saved")
        XCTAssertEqual(WatchItemCopy.toastSaved(kind: .cooldown), "Cooldown saved")
        XCTAssertEqual(WatchItemCopy.toastWarmupsSaved, "Warm-ups saved")
        XCTAssertTrue(WatchItemCopy.toastSavedSub.contains("REPLACE ON WATCH"))
    }

    func testSectionLabel() {
        XCTAssertEqual(
            WatchItemCopy.sectionLabel,
            "WATCH READINESS — RESHAPE, THEN REPLACE"
        )
    }
}
