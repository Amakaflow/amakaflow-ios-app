//
//  MotionStaggerTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2443 slice 6 — 55ms/row list entrance and its cap.
//

import XCTest
@testable import AmakaFlowCompanion

final class MotionStaggerTests: XCTestCase {

    /// `screens-exsearch.jsx` header: "stagger 55ms/row", ".delay(i*0.055)".
    func testStaggerMatchesTheRigsFiftyFiveMillisecondsPerRow() {
        XCTAssertEqual(MotionTokens.rowStagger, 0.055, accuracy: 1e-9)
        XCTAssertEqual(MotionTokens.staggerDelay(index: 0) ?? -1, 0.0, accuracy: 1e-9)
        XCTAssertEqual(MotionTokens.staggerDelay(index: 1) ?? -1, 0.055, accuracy: 1e-9)
        XCTAssertEqual(MotionTokens.staggerDelay(index: 4) ?? -1, 0.220, accuracy: 1e-9)
    }

    /// Rows past the cap must return nil, not zero. Nil turns the reveal off;
    /// zero would still animate, which is the mid-scroll entrance we are avoiding.
    func testRowsPastTheCapDoNotAnimateAtAll() {
        XCTAssertNotNil(MotionTokens.staggerDelay(index: MotionTokens.maxStaggeredRows - 1))
        XCTAssertNil(MotionTokens.staggerDelay(index: MotionTokens.maxStaggeredRows))
        XCTAssertNil(MotionTokens.staggerDelay(index: 60))
    }

    func testNegativeIndexDoesNotAnimate() {
        XCTAssertNil(MotionTokens.staggerDelay(index: -1))
    }

    /// The whole staggered run stays inside one "slow" beat, so the last visible
    /// row is not still arriving after the sheet has settled.
    func testTheFullStaggeredRunFitsWithinTheSlowToken() {
        let last = MotionTokens.staggerDelay(index: MotionTokens.maxStaggeredRows - 1) ?? .infinity
        XCTAssertLessThanOrEqual(last, MotionTokens.slow)
    }

    /// The rig's three durations, pinned so a later edit cannot drift them.
    func testDurationTokensMatchTheMotionRig() {
        XCTAssertEqual(MotionTokens.fast, 0.160, accuracy: 1e-9)
        XCTAssertEqual(MotionTokens.base, 0.280, accuracy: 1e-9)
        XCTAssertEqual(MotionTokens.slow, 0.420, accuracy: 1e-9)
    }
}
