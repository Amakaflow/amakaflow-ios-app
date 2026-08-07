//
//  WatchItemCopyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2386: copy-lock for watch item sheet.
//

import XCTest
@testable import AmakaFlowCompanion

final class WatchItemCopyTests: XCTestCase {
    func testIdleAndLitCTA() {
        XCTAssertEqual(WatchItemCopy.replaceCTA(changeCount: 0), "No changes yet")
        XCTAssertEqual(WatchItemCopy.replaceCTA(changeCount: 1), "Replace on watch · 1 change")
        XCTAssertEqual(WatchItemCopy.replaceCTA(changeCount: 2), "Replace on watch · 2 changes")
    }

    func testReplaceNotes() {
        XCTAssertTrue(WatchItemCopy.replaceNote(isApple: true).contains("same slot"))
        XCTAssertTrue(WatchItemCopy.replaceNote(isApple: false).contains("queued file"))
    }

    func testToastStrings() {
        XCTAssertEqual(WatchItemCopy.toastPending, "Updating on watch…")
        XCTAssertEqual(WatchItemCopy.toastSuccess(isApple: true), "Replaced ✓")
        XCTAssertEqual(WatchItemCopy.toastSuccess(isApple: false), "Queue updated ✓")
    }

    func testSectionLabel() {
        XCTAssertEqual(
            WatchItemCopy.sectionLabel,
            "WATCH READINESS — RESHAPE, THEN REPLACE"
        )
    }
}
