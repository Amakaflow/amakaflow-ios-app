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

    // MARK: - AMA-2357: sheet selections must write through immediately.
    //
    // Root cause: `GarminWatchDisplayPrefsSheet` staged the user's tap only in
    // local `@State` and persisted it exclusively inside `save()`. SwiftUI
    // sheets are swipe-to-dismiss by default, and that gesture calls no button
    // action — so tapping "Countdown from the workout rest" and then swiping
    // the sheet away (instead of tapping Save) silently discarded the choice.
    // The store kept whatever was persisted before (often `lap`, from an
    // earlier dogfood pass), and every subsequent Garmin push kept sending it
    // no matter what Settings appeared to show. Fix: persist on every tap via
    // `GarminWatchDisplayPrefsStore.applyLiveSelection`, which the sheet's row
    // actions call directly (verified here without needing a live SwiftUI
    // view hierarchy, since `@State` mutations aren't observable outside one).

    func testApplyLiveSelectionWritesRestModeThroughImmediately() {
        GarminWatchDisplayPrefsStore.current = GarminWatchDisplayPrefs(
            exerciseEnd: .lap,
            restMode: .lap,
            defaultRestSec: 60
        )

        // What the sheet's "Countdown from the workout rest" row now does on tap.
        GarminWatchDisplayPrefsStore.applyLiveSelection(restMode: .timed)

        // A swipe-to-dismiss would run no further code — this alone must be
        // enough for the next push to send `rest_mode: timed`.
        XCTAssertEqual(GarminWatchDisplayPrefsStore.current.restMode, .timed)
        // Untouched fields survive the partial update.
        XCTAssertEqual(GarminWatchDisplayPrefsStore.current.exerciseEnd, .lap)
    }

    func testApplyLiveSelectionWritesExerciseEndThroughImmediately() {
        GarminWatchDisplayPrefsStore.current = GarminWatchDisplayPrefs(
            exerciseEnd: .lap,
            restMode: .timed,
            defaultRestSec: 60
        )

        GarminWatchDisplayPrefsStore.applyLiveSelection(exerciseEnd: .showRepsLap)

        XCTAssertEqual(GarminWatchDisplayPrefsStore.current.exerciseEnd, .showRepsLap)
        XCTAssertEqual(GarminWatchDisplayPrefsStore.current.restMode, .timed)
    }

    func testApplyLiveSelectionMarksConfigured() {
        GarminWatchDisplayPrefsStore.resetForTests()
        XCTAssertTrue(GarminWatchDisplayPrefsStore.shouldPresentOnboarding)

        GarminWatchDisplayPrefsStore.applyLiveSelection(restMode: .timed)

        XCTAssertFalse(GarminWatchDisplayPrefsStore.shouldPresentOnboarding)
        XCTAssertEqual(GarminWatchDisplayPrefsStore.current.restMode, .timed)
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
        _ = await service.push(workoutId: "wk-1", workoutName: "Lab workout", gymTitle: "Gym")
        XCTAssertTrue(api.pushWatchDeliveryCalled)
        XCTAssertEqual(api.lastPushWatchDeliveryPrefs?.exerciseEnd, .timedHoldsOnly)
        XCTAssertEqual(api.lastPushWatchDeliveryPrefs?.restMode, .omit)
    }
}
