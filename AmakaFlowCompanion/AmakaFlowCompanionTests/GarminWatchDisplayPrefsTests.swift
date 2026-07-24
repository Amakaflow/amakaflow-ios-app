//
//  GarminWatchDisplayPrefsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2316: Garmin watch display prefs persistence + push body encoding.
//

import XCTest
@testable import AmakaFlowCompanion

final class GarminWatchDisplayPrefsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GarminWatchDisplayPrefsStore.resetForTests()
    }

    override func tearDown() {
        GarminWatchDisplayPrefsStore.resetForTests()
        super.tearDown()
    }

    func testDogfoodDefaults() {
        let prefs = GarminWatchDisplayPrefs.dogfood
        XCTAssertEqual(prefs.exerciseEnd, .lap)
        XCTAssertEqual(prefs.restMode, .timed)
        XCTAssertEqual(prefs.defaultRestSec, 60)
        XCTAssertTrue(GarminWatchDisplayPrefsStore.shouldPresentOnboarding)
    }

    func testPersistMarksConfigured() {
        XCTAssertTrue(GarminWatchDisplayPrefsStore.shouldPresentOnboarding)
        var prefs = GarminWatchDisplayPrefs.dogfood
        prefs.restMode = .omit
        GarminWatchDisplayPrefsStore.current = prefs
        XCTAssertFalse(GarminWatchDisplayPrefsStore.shouldPresentOnboarding)
        XCTAssertEqual(GarminWatchDisplayPrefsStore.current.restMode, .omit)
    }

    func testPushBodyUsesSnakeCaseKeys() throws {
        let prefs = GarminWatchDisplayPrefs(
            exerciseEnd: .showRepsLap,
            restMode: .lap,
            defaultRestSec: 90
        )
        let data = try JSONEncoder().encode(prefs.pushBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["exercise_end"] as? String, "show_reps_lap")
        XCTAssertEqual(json["rest_mode"] as? String, "lap")
        XCTAssertEqual(json["default_rest_sec"] as? Int, 90)
    }

    func testSummaryLine() {
        let line = GarminWatchDisplayPrefs.dogfood.summaryLine
        XCTAssertTrue(line.contains("Lap to advance"))
        XCTAssertTrue(line.contains("60"))
    }
}

@MainActor
final class GarminStartHandoffPrefsTests: XCTestCase {
    private var api: MockAPIService!

    override func setUp() async throws {
        api = MockAPIService()
        GarminWatchDisplayPrefsStore.resetForTests()
        GarminWatchDisplayPrefsStore.current = GarminWatchDisplayPrefs(
            exerciseEnd: .timedHoldsOnly,
            restMode: .omit,
            defaultRestSec: 60
        )
    }

    override func tearDown() async throws {
        GarminWatchDisplayPrefsStore.resetForTests()
    }

    func testPushSendsStoredDisplayPrefs() async {
        api.pushWatchDeliveryResult = .success(
            Components.Schemas.WatchResendResult(deliveryIds: ["d1"], success: true)
        )
        let service = GarminStartHandoffService(apiService: api, forceFailureCode: { nil })
        _ = await service.push(workoutId: "wk-1", gymTitle: "Gym")
        XCTAssertTrue(api.pushWatchDeliveryCalled)
        XCTAssertEqual(api.lastPushWatchDeliveryPrefs?.exerciseEnd, .timedHoldsOnly)
        XCTAssertEqual(api.lastPushWatchDeliveryPrefs?.restMode, .omit)
    }
}
