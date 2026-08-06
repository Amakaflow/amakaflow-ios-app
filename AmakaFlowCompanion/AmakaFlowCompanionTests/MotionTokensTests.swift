//
//  MotionTokensTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2383 — motion token values must match design-handoff/MOTION.md exactly.
//

import XCTest
@testable import AmakaFlowCompanion

final class MotionTokensTests: XCTestCase {

    func testDurationTokensExact() {
        XCTAssertEqual(MotionTokens.fast, 0.160, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.base, 0.280, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.slow, 0.420, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.buildStagger, 0.130, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.wipeDuration, 0.500, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.wipeDelay, 0.120, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.chipDelay, 0.280, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.theatricalCap, 2.0, accuracy: 0.0001)
    }

    func testToastHoldDurationsExact() {
        XCTAssertEqual(MotionTokens.toastHold, 1.800, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.toastHoldWithAction, 4.000, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.toastOut, 0.240, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.toastTopInset, 54, accuracy: 0.1)
    }

    func testCappedStaggerNeverExceedsNominal() {
        XCTAssertEqual(MotionTokens.cappedStagger(beatCount: 1), MotionTokens.buildStagger, accuracy: 0.0001)
        // Large scripts must compress so kick + N*stagger + settle ≤ 2s.
        let large = MotionTokens.cappedStagger(beatCount: 40)
        XCTAssertLessThan(large, MotionTokens.buildStagger)
        XCTAssertGreaterThan(large, 0)
    }

    func testCopyLockVerbsAndToastLines() {
        XCTAssertEqual(BuildRevealScripts.watchVerb, "COMPOSING")
        XCTAssertEqual(BuildRevealScripts.watchCTA, "Schedule on the watch")
        XCTAssertEqual(BuildRevealScripts.importVerb, "PARSING")
        XCTAssertEqual(BuildRevealScripts.aiVerb, "DRAFTING")
        XCTAssertEqual(DDToastCopy.savedToLibrary, "Saved to Library")
        XCTAssertEqual(DDToastCopy.sendingToGarmin, "Sending to Garmin…")
        XCTAssertEqual(DDToastCopy.sentToGarmin, "Sent to Garmin")
        XCTAssertEqual(DDToastCopy.undoAction, "Undo")
        XCTAssertEqual(DDToastCopy.libraryUntouched, "LIBRARY UNTOUCHED")
    }
}
