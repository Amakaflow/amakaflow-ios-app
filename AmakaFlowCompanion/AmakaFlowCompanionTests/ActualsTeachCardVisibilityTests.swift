//
//  ActualsTeachCardVisibilityTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: teach card shown only when zero sources ever-connected AND Today empty.
//

import XCTest
@testable import AmakaFlowCompanion

final class ActualsTeachCardVisibilityTests: XCTestCase {

    func testShowsWhenNeverConnectedAndTodayEmpty() {
        XCTAssertTrue(
            ActualsTeachCardVisibility.shouldShow(
                hasEverConnected: false,
                todayEmpty: true
            )
        )
    }

    func testHidesWhenTodayHasSessions() {
        XCTAssertFalse(
            ActualsTeachCardVisibility.shouldShow(
                hasEverConnected: false,
                todayEmpty: false
            )
        )
    }

    func testHidesForeverAfterFirstConnectEvenIfEmptyAndDisconnected() {
        XCTAssertFalse(
            ActualsTeachCardVisibility.shouldShow(
                hasEverConnected: true,
                todayEmpty: true
            )
        )
    }

    func testCopyLocksMatchHandoff() {
        XCTAssertEqual(
            ActualsCopy.teachHeadline,
            "Your finished workouts can land here by themselves"
        )
        XCTAssertEqual(
            ActualsCopy.teachSubhead,
            "Connect Apple Health, Garmin or Strava — sessions show up minutes after you finish, ready to log."
        )
        XCTAssertEqual(ActualsCopy.teachCTA, "Connect a source")
        XCTAssertEqual(ActualsCopy.teachTrustLine, "~30 SECONDS · READ-ONLY · UNPLUG ANYTIME")
        XCTAssertEqual(ActualsCopy.teachManualAlt, "or log a session manually with ＋")
        XCTAssertEqual(ActualsCopy.teachCardAccessibilityID, "af_actuals_teach_card")
    }
}
