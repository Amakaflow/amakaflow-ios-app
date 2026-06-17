//
//  WeeklyProgressRingTests.swift
//  AmakaFlowCompanionTests
//
//  Issue #304: weekly-target math was duplicated and drifted — text used `completed + 1`
//  while the ring used `completed + 2`, making 100% mathematically unreachable.
//  WeeklyProgressRing now owns both computations as static helpers so callers
//  cannot supply inconsistent values.
//

import XCTest

@testable import AmakaFlowCompanion

final class WeeklyProgressRingTests: XCTestCase {

    // MARK: - ringPercentage

    func testRingPercentageIsRatioOfCompletedToTarget() {
        XCTAssertEqual(WeeklyProgressRing.ringPercentage(completed: 2, target: 4), 0.5, accuracy: 0.001)
    }

    func testRingPercentageIsExactlyOneWhenCompleted() {
        XCTAssertEqual(WeeklyProgressRing.ringPercentage(completed: 3, target: 3), 1.0, accuracy: 0.001)
    }

    func testRingPercentageCapsAtOneWhenOverCompleted() {
        XCTAssertEqual(WeeklyProgressRing.ringPercentage(completed: 5, target: 3), 1.0, accuracy: 0.001)
    }

    func testRingPercentageIsZeroWhenTargetIsZero() {
        XCTAssertEqual(WeeklyProgressRing.ringPercentage(completed: 0, target: 0), 0.0, accuracy: 0.001)
    }

    func testRingPercentageIsZeroWhenNothingCompleted() {
        XCTAssertEqual(WeeklyProgressRing.ringPercentage(completed: 0, target: 5), 0.0, accuracy: 0.001)
    }

    // MARK: - motivationalText

    func testMotivationalTextWhenTargetHit() {
        let text = WeeklyProgressRing.motivationalText(completed: 3, target: 3)
        XCTAssertTrue(text.contains("Target hit!"), "Expected target-hit message, got: \(text)")
        XCTAssertTrue(text.contains("3 of 3"), "Expected '3 of 3' in: \(text)")
    }

    func testMotivationalTextOneRemaining() {
        let text = WeeklyProgressRing.motivationalText(completed: 2, target: 3)
        XCTAssertTrue(text.contains("one more to go"), "Expected 'one more to go' in: \(text)")
    }

    func testMotivationalTextMultipleRemaining() {
        let text = WeeklyProgressRing.motivationalText(completed: 1, target: 4)
        XCTAssertTrue(text.contains("3 more to go"), "Expected '3 more to go' in: \(text)")
    }

    func testMotivationalTextWhenOverCompleted() {
        let text = WeeklyProgressRing.motivationalText(completed: 5, target: 3)
        XCTAssertTrue(text.contains("Target hit!"), "Expected target-hit message for over-completion, got: \(text)")
    }

    func testMotivationalTextWhenTargetIsZero() {
        let text = WeeklyProgressRing.motivationalText(completed: 0, target: 0)
        XCTAssertFalse(text.isEmpty, "Expected non-empty fallback message")
    }
}
