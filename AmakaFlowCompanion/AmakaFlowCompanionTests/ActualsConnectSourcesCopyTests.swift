//
//  ActualsConnectSourcesCopyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: locks the Connect Sources screen copy contract (ActualsConnectSourcesView).
//

import XCTest
@testable import AmakaFlowCompanion

final class ActualsConnectSourcesCopyTests: XCTestCase {

    func testTitleMatchesHandoff() {
        XCTAssertEqual(ActualsCopy.connectTitle, "Pull your training in")
    }

    func testSubheadIncludesReadOnlyPromise() {
        XCTAssertTrue(
            ActualsCopy.connectSubhead.contains("Pull is read-only"),
            "Subhead must carry the pull read-only promise: \(ActualsCopy.connectSubhead)"
        )
        XCTAssertTrue(
            ActualsCopy.connectSubhead.localizedCaseInsensitiveContains("write-back"),
            "Subhead must mention optional write-back: \(ActualsCopy.connectSubhead)"
        )
        XCTAssertTrue(
            ActualsCopy.connectSubhead.localizedCaseInsensitiveContains("30 days"),
            "Subhead must state the Strava lookback window: \(ActualsCopy.connectSubhead)"
        )
    }

    func testPerProviderOneLinersMatchHandoff() {
        XCTAssertEqual(
            ActualsCopy.sourceOneLiner(.appleHealth),
            "WORKOUTS FROM YOUR APPLE WATCH · HEART RATE + CALORIES"
        )
        XCTAssertEqual(
            ActualsCopy.sourceOneLiner(.garmin),
            "RUNS + STRENGTH · PULLED AUTOMATICALLY AFTER SYNC"
        )
        XCTAssertEqual(
            ActualsCopy.sourceOneLiner(.strava),
            "LAST 30 DAYS ON CONNECT · THEN NEW SESSIONS AS THEY LAND"
        )
    }

    func testProviderDisplayNames() {
        XCTAssertEqual(ActualsCopy.sourceDisplayName(.appleHealth), "Apple Health")
        XCTAssertEqual(ActualsCopy.sourceDisplayName(.garmin), "Garmin")
        XCTAssertEqual(ActualsCopy.sourceDisplayName(.strava), "Strava")
    }

    func testDedupeFooterExactUppercaseCopy() {
        XCTAssertEqual(
            ActualsCopy.connectDedupeFooter,
            "SAME WORKOUT FROM TWO SOURCES? WE KEEP ONE — WATCH BEATS PHONE, RICHER DATA WINS. NOTHING COUNTS TWICE."
        )
    }

    func testConnectedBadgeAndConnectButtonCopy() {
        XCTAssertEqual(ActualsCopy.connectedBadge, "CONNECTED ✓")
        XCTAssertEqual(ActualsCopy.connectButton, "Connect")
    }

    func testAccessibilityIDsPerProvider() {
        for provider in ActualsSourceProvider.allCases {
            XCTAssertEqual(
                provider.accessibilityRowID,
                "af_actuals_source_row_\(provider.rawValue)"
            )
            XCTAssertEqual(
                provider.accessibilityConnectID,
                "af_actuals_connect_\(provider.rawValue)"
            )
        }
    }

    func testAllThreeProvidersCovered() {
        XCTAssertEqual(
            Set(ActualsSourceProvider.allCases),
            [.appleHealth, .garmin, .strava]
        )
    }
}
