//
//  ActualsTodayCopyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2418: Today empty / scrubber hint must follow linked sources.
//

import XCTest
@testable import AmakaFlowCompanion

final class ActualsTodayCopyTests: XCTestCase {

    func testLinkedEmptyTodayStravaOnlyKeepsLegacyTone() {
        XCTAssertEqual(
            ActualsCopy.linkedEmptyToday(connected: [.strava]),
            ActualsCopy.linkedEmptyToday
        )
    }

    func testLinkedEmptyTodayGarminOnlyNamesGarmin() {
        let copy = ActualsCopy.linkedEmptyToday(connected: [.garmin])
        XCTAssertTrue(copy.contains("Garmin"), copy)
        XCTAssertFalse(copy.contains("Strava"), copy)
    }

    func testLinkedEmptyTodayMultipleListsSources() {
        let copy = ActualsCopy.linkedEmptyToday(connected: [.garmin, .strava])
        XCTAssertTrue(copy.contains("Garmin"), copy)
        XCTAssertTrue(copy.contains("Strava"), copy)
        XCTAssertTrue(copy.hasPrefix("No sessions from"), copy)
    }

    func testHistoryScrubberHintWithNoSources() {
        XCTAssertEqual(
            ActualsCopy.historyScrubberHint(connected: []),
            "SWIPE OR TAP — LAST 30 DAYS · CONNECT A SOURCE TO PULL HISTORY"
        )
    }

    func testHistoryScrubberHintListsOnlyConnectedSources() {
        XCTAssertEqual(
            ActualsCopy.historyScrubberHint(connected: [.garmin]),
            "SWIPE OR TAP — LAST 30 DAYS · PULLED FROM GARMIN ON CONNECT"
        )
        XCTAssertEqual(
            ActualsCopy.historyScrubberHint(connected: [.strava, .garmin]),
            "SWIPE OR TAP — LAST 30 DAYS · PULLED FROM GARMIN + STRAVA ON CONNECT"
        )
    }

    func testDisplayOrderedIsAppleGarminStrava() {
        XCTAssertEqual(
            ActualsCopy.displayOrdered([.strava, .appleHealth, .garmin]),
            [.appleHealth, .garmin, .strava]
        )
    }
}
