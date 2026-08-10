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
        XCTAssertEqual(StravaOAuthCallback.outcome(from: url), .success(grantedWrite: false))
    }

    func testSuccessCallbackTripleSlashShape() {
        let url = URL(string: "amakaflow:///connected?status=success")!
        XCTAssertEqual(StravaOAuthCallback.outcome(from: url), .success(grantedWrite: false))
    }

    func testSuccessCallbackWithWriteScope() {
        let url = URL(
            string: "amakaflow://strava/connected?status=success&scope=activity:read_all,activity:write"
        )!
        XCTAssertEqual(StravaOAuthCallback.outcome(from: url), .success(grantedWrite: true))
    }

    func testSuccessCallbackWithSpaceDelimitedWriteScope() {
        let encoded = "activity:read_all%20activity:write"
        let url = URL(string: "amakaflow://strava/connected?status=success&scope=\(encoded)")!
        XCTAssertEqual(StravaOAuthCallback.outcome(from: url), .success(grantedWrite: true))
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

    func testCardsOmitPriorDaysWhenTodayEmpty() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
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
                stravaId: 3,
                name: "Evening Weight Training",
                type: "WeightTraining",
                distanceKm: 0,
                durationMin: 45,
                startDate: yesterday,
                description: ""
            )
        ]

        let cards = ActualsTodayDemoFeed.cards(from: activities)
        XCTAssertTrue(cards.isEmpty, "Today must not backfill prior-day Strava sessions")
    }

    func testApplyLibraryMatchUpdatesLiveStravaCardID() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let today = formatter.string(from: Date())
        let successJSON = """
        {
          "success": true,
          "synced_count": 1,
          "activities": [{
            "strava_id": 2,
            "name": "Today ride",
            "type": "Ride",
            "distance_km": 20,
            "duration_min": 55,
            "start_date": "\(today)",
            "description": ""
          }],
          "message": "ok"
        }
        """.data(using: .utf8)!
        MockURLProtocol.setResponse(statusCode: 200, data: successJSON)

        let client = BFFStravaClient(
            baseURL: "https://mock.test/v1",
            session: MockURLProtocol.mockSession(),
            bearerTokenProvider: { "test-token" },
            userIDProvider: { "user-1" }
        )
        let db = try AppDatabase.makeTestDatabase()
        let feed = ActualsTodayDemoFeed(repository: ActualsRepository(database: db))
        let sync = ActualsSyncProgressStore()
        await feed.activateFromStravaSync(sync: sync, client: client)
        XCTAssertEqual(feed.cards.map(\.id), ["strava_2"])

        feed.applyLibraryMatch(planTitle: "Tempo ride", unmappedCardID: "strava_2")

        XCTAssertEqual(feed.cards.count, 1)
        XCTAssertEqual(feed.cards[0].id, "strava_2")
        XCTAssertEqual(feed.cards[0].title, "Tempo ride")
        XCTAssertEqual(feed.cards[0].kind, .fillInDebt)
        XCTAssertFalse(
            feed.cards.contains(where: { $0.id == "today_demo_unmapped" }),
            "Live Strava match must not create/update the demo fallback card"
        )
    }

    func testLogicalSyncFailureDoesNotActivateFeedOrProgress() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let failureJSON = """
        {"success":false,"synced_count":0,"activities":[],"message":"strava token expired"}
        """.data(using: .utf8)!
        MockURLProtocol.setResponse(statusCode: 200, data: failureJSON)

        let client = BFFStravaClient(
            baseURL: "https://mock.test/v1",
            session: MockURLProtocol.mockSession(),
            bearerTokenProvider: { "test-token" },
            userIDProvider: { "user-1" }
        )
        let db = try AppDatabase.makeTestDatabase()
        let feed = ActualsTodayDemoFeed(repository: ActualsRepository(database: db))
        let sync = ActualsSyncProgressStore()

        await feed.activateFromStravaSync(sync: sync, client: client)

        XCTAssertFalse(feed.isActive, "Logical BFF failure must not activate the Today rail")
        XCTAssertTrue(feed.cards.isEmpty)
        XCTAssertNil(sync.progress, "Logical failure must not start backfill progress")
    }
}
