//
//  StravaOAuthCallbackTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2391: deep-link callback parsing + sync → Today card mapping.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class StravaOAuthCallbackTests: XCTestCase {

    func testSuccessCallbackFromFrontendURLShape() {
        let url = URL(string: "amakaflow://strava/connected?provider=strava&status=success")!
        XCTAssertEqual(StravaOAuthCallback.outcome(from: url), .success)
    }

    func testSuccessCallbackTripleSlashShape() {
        let url = URL(string: "amakaflow:///connected?status=success")!
        XCTAssertEqual(StravaOAuthCallback.outcome(from: url), .success)
    }

    func testErrorCallbackMapsToFailed() {
        let url = URL(string: "amakaflow://strava/connected?status=error&error=access_denied")!
        XCTAssertEqual(StravaOAuthCallback.outcome(from: url), .failed)
    }

    func testWrongSchemeFails() {
        let url = URL(string: "https://example.com/connected?status=success")!
        XCTAssertEqual(StravaOAuthCallback.outcome(from: url), .failed)
    }

    func testCardsPreferTodayActivities() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let today = formatter.string(from: Date())
        let yesterday = formatter.string(from: Date().addingTimeInterval(-86_400))

        let activities = [
            StravaCompletedActivityDTO(
                stravaId: 1,
                name: "Old run",
                type: "Run",
                distanceKm: 5,
                durationMin: 30,
                startDate: yesterday,
                description: ""
            ),
            StravaCompletedActivityDTO(
                stravaId: 2,
                name: "Today ride",
                type: "Ride",
                distanceKm: 20,
                durationMin: 55,
                startDate: today,
                description: ""
            )
        ]

        let cards = ActualsTodayDemoFeed.cards(from: activities)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].id, "strava_2")
        XCTAssertEqual(cards[0].title, "Today ride")
        XCTAssertEqual(cards[0].kind, .unmapped)
        XCTAssertEqual(cards[0].sourceProvider, .strava)
    }
}
