//
//  SuggestWorkoutGeneratingCopyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2371: staged-progress copy for the "Generating your workout" screen
//  (spec 2026-08-02 send/enhance flow iOS UI redesign).
//

import XCTest
@testable import AmakaFlowCompanion

final class SuggestWorkoutGeneratingCopyTests: XCTestCase {
    func testStepsCycleThroughFourStages() {
        XCTAssertEqual(SuggestWorkoutGeneratingCopy.steps, [
            "Reading signals",
            "Weighing recovery",
            "Choosing focus",
            "Building blocks"
        ])
    }

    func testFailureFinePrintNeverThreatensACannedFallback() {
        XCTAssertEqual(
            SuggestWorkoutGeneratingCopy.failureFinePrint,
            "If it fails you'll see exactly why — we never swap in a canned workout."
        )
        XCTAssertFalse(SuggestWorkoutGeneratingCopy.failureFinePrint.lowercased().contains("no fallback"))
    }

    func testStepProgressLabelFormatsStepAndTotal() {
        XCTAssertEqual(
            SuggestWorkoutGeneratingCopy.stepProgressLabel(step: 1, total: 4),
            "STEP 1 OF 4 · USUALLY UNDER 20S"
        )
        XCTAssertEqual(
            SuggestWorkoutGeneratingCopy.stepProgressLabel(step: 4, total: 4),
            "STEP 4 OF 4 · USUALLY UNDER 20S"
        )
    }

    func testStepProgressLabelClampsOutOfRangeStep() {
        // A cycling index that wraps past the last step (or starts at 0)
        // must never render "STEP 0 OF 4" or "STEP 5 OF 4".
        XCTAssertEqual(
            SuggestWorkoutGeneratingCopy.stepProgressLabel(step: 0, total: 4),
            "STEP 1 OF 4 · USUALLY UNDER 20S"
        )
        XCTAssertEqual(
            SuggestWorkoutGeneratingCopy.stepProgressLabel(step: 5, total: 4),
            "STEP 4 OF 4 · USUALLY UNDER 20S"
        )
    }
}
