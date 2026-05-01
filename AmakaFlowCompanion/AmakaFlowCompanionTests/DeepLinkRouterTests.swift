//
//  DeepLinkRouterTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1640: Tests for AmakaFlowCompanionApp.resolveAppSurfaceDeepLink
//  — the pure URL → (Notification.Name, userInfo) routing logic.
//

import XCTest
@testable import AmakaFlowCompanion

final class DeepLinkRouterTests: XCTestCase {

    // MARK: - Custom-scheme surface routing

    func test_customScheme_calendar_routesAndExtractsDate() {
        let url = URL(string: "amakaflow://calendar/2026-05-10")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToCalendar)
        XCTAssertEqual(result?.userInfo?["date"] as? String, "2026-05-10")
    }

    func test_customScheme_workout_routesAndExtractsId() {
        let url = URL(string: "amakaflow://workout/abc123")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToWorkout)
        XCTAssertEqual(result?.userInfo?["workoutId"] as? String, "abc123")
    }

    func test_customScheme_workouts_aliasRoutesToWorkout() {
        let url = URL(string: "amakaflow://workouts")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToWorkout)
    }

    func test_customScheme_coach_routesAndExtractsThreadId() {
        let url = URL(string: "amakaflow://coach/thread-42")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToCoach)
        XCTAssertEqual(result?.userInfo?["threadId"] as? String, "thread-42")
    }

    func test_customScheme_sync_routes_noPayload() {
        let url = URL(string: "amakaflow://sync")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToSync)
        XCTAssertNil(result?.userInfo, "No path tail or query items → userInfo should be nil")
    }

    func test_customScheme_nutrition_routes() {
        let url = URL(string: "amakaflow://nutrition")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToNutrition)
    }

    // MARK: - Universal-link surface routing

    func test_universalLink_appSubdomain_routesSync() {
        let url = URL(string: "https://app.amakaflow.com/sync")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToSync)
    }

    func test_universalLink_apexDomain_routesCoach() {
        let url = URL(string: "https://amakaflow.com/coach/thread-99")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToCoach)
        XCTAssertEqual(result?.userInfo?["threadId"] as? String, "thread-99")
    }

    func test_universalLink_httpScheme_alsoRoutes() {
        let url = URL(string: "http://amakaflow.com/calendar")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToCalendar)
    }

    // MARK: - Marketing / unknown rejection (no hijacking)

    func test_universalLink_marketingPricingPath_doesNotHijack() {
        let url = URL(string: "https://amakaflow.com/pricing")!
        XCTAssertNil(AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url),
                     "Marketing paths must not fire any deep-link notification")
    }

    func test_universalLink_marketingAboutPath_doesNotHijack() {
        let url = URL(string: "https://amakaflow.com/about")!
        XCTAssertNil(AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url))
    }

    func test_universalLink_unknownDomain_doesNotRoute() {
        let url = URL(string: "https://example.com/calendar")!
        XCTAssertNil(AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url))
    }

    func test_unknownScheme_doesNotRoute() {
        // E.g. Garmin Connect IQ callback that should be handled elsewhere.
        let url = URL(string: "garmin-ciq://device/abc")!
        XCTAssertNil(AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url))
    }

    func test_customScheme_unknownSurface_doesNotRoute() {
        let url = URL(string: "amakaflow://unknown")!
        XCTAssertNil(AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url))
    }

    // MARK: - Query items

    func test_queryItems_forwardedAsUserInfo() {
        let url = URL(string: "amakaflow://workout?source=push&campaign=apr")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.name, .deepLinkToWorkout)
        XCTAssertEqual(result?.userInfo?["source"] as? String, "push")
        XCTAssertEqual(result?.userInfo?["campaign"] as? String, "apr")
    }

    func test_queryItems_combineWithPathTail() {
        let url = URL(string: "amakaflow://workout/abc123?source=push")!
        let result = AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)
        XCTAssertEqual(result?.userInfo?["workoutId"] as? String, "abc123")
        XCTAssertEqual(result?.userInfo?["source"] as? String, "push")
    }

    // MARK: - Routable surfaces allow-list

    func test_routableSurfaces_areExactlyTheSupportedSet() {
        XCTAssertEqual(AmakaFlowCompanionApp.routableSurfaces,
                       ["calendar", "workout", "workouts", "sync", "coach", "nutrition"])
    }

    // MARK: - Case insensitivity

    func test_customScheme_uppercaseSurface_matches() {
        // url.host is already lowercased by URL, but be explicit.
        let url = URL(string: "amakaflow://Calendar")!
        XCTAssertEqual(AmakaFlowCompanionApp.resolveAppSurfaceDeepLink(url)?.name, .deepLinkToCalendar)
    }
}
