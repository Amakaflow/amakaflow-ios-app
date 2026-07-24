//
//  GarminHandoffStateStoreTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2317: the handoff record is what tells a returning user "your push
//  finished" and tells Sentry "the process died mid-push".
//

import XCTest
@testable import AmakaFlowCompanion

final class GarminHandoffStateStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: GarminHandoffStateStore!

    override func setUp() {
        super.setUp()
        suiteName = "GarminHandoffStateStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = GarminHandoffStateStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testNoRecordBeforeAnyPush() {
        XCTAssertNil(store.record)
        XCTAssertNil(store.takeInterrupted())
        XCTAssertNil(store.restorableMessage(workoutId: "wk-1"))
    }

    func testBeginMarksHandoffInFlight() {
        store.begin(workoutId: "wk-1", gymTitle: "Home")
        let record = store.record
        XCTAssertEqual(record?.workoutId, "wk-1")
        XCTAssertEqual(record?.gymTitle, "Home")
        XCTAssertEqual(record?.isInFlight, true)
        XCTAssertNil(store.restorableMessage(workoutId: "wk-1"), "In-flight pushes have nothing to restore yet")
    }

    func testFinishStoresRestorableMessage() {
        store.begin(workoutId: "wk-1", gymTitle: "Home")
        store.finish(workoutId: "wk-1", outcome: .sent, message: "Sent to Garmin — open CIQ widget.")

        XCTAssertEqual(store.record?.isInFlight, false)
        XCTAssertEqual(store.record?.outcome, .sent)
        XCTAssertEqual(store.restorableMessage(workoutId: "wk-1"), "Sent to Garmin — open CIQ widget.")
    }

    func testFinishIgnoresADifferentWorkout() {
        store.begin(workoutId: "wk-1", gymTitle: "Home")
        store.finish(workoutId: "wk-2", outcome: .sent, message: "Wrong workout")

        XCTAssertEqual(store.record?.isInFlight, true)
        XCTAssertNil(store.restorableMessage(workoutId: "wk-2"))
    }

    func testRestorableMessageIsScopedToTheWorkout() {
        store.begin(workoutId: "wk-1", gymTitle: "Home")
        store.finish(workoutId: "wk-1", outcome: .queued, message: "Queued for Garmin.")

        XCTAssertNil(store.restorableMessage(workoutId: "wk-other"))
    }

    func testRestorableMessageExpires() {
        let started = Date(timeIntervalSince1970: 1_000_000)
        store.begin(workoutId: "wk-1", gymTitle: "Home", now: started)
        store.finish(workoutId: "wk-1", outcome: .sent, message: "Sent to Garmin.", now: started)

        let withinWindow = started.addingTimeInterval(1800)
        XCTAssertNotNil(store.restorableMessage(workoutId: "wk-1", now: withinWindow, maxAge: 3600))

        let stale = started.addingTimeInterval(7200)
        XCTAssertNil(store.restorableMessage(workoutId: "wk-1", now: stale, maxAge: 3600))
    }

    func testInterruptedHandoffIsReportedOnceThenCleared() {
        store.begin(workoutId: "wk-1", gymTitle: "Home")

        let interrupted = store.takeInterrupted()
        XCTAssertEqual(interrupted?.workoutId, "wk-1")
        XCTAssertNil(store.record, "Taking the record must clear it so it isn't reported twice")
        XCTAssertNil(store.takeInterrupted())
    }

    func testCompletedHandoffIsNotReportedAsInterrupted() {
        store.begin(workoutId: "wk-1", gymTitle: "Home")
        store.finish(workoutId: "wk-1", outcome: .readyOnWatch, message: "Ready on watch.")

        XCTAssertNil(store.takeInterrupted(), "A finished push is a suspension, not a crash")
        XCTAssertNotNil(store.record, "The finished record must survive for restore")
    }

    func testFailedPushOutcomeIsRecorded() {
        store.begin(workoutId: "wk-1", gymTitle: "Home")
        store.finish(workoutId: "wk-1", outcome: .failed, message: "Garmin push failed.")

        XCTAssertEqual(store.record?.outcome, .failed)
        XCTAssertNil(store.takeInterrupted())
    }
}

@MainActor
final class GarminStartHandoffRecordingTests: XCTestCase {
    private var api: MockAPIService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: GarminHandoffStateStore!

    override func setUp() async throws {
        api = MockAPIService()
        suiteName = "GarminStartHandoffRecordingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = GarminHandoffStateStore(defaults: defaults)
        GarminWatchDisplayPrefsStore.resetForTests()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        GarminWatchDisplayPrefsStore.resetForTests()
    }

    func testSuccessfulPushLeavesARestorableStatus() async {
        api.pushWatchDeliveryResult = .success(
            Components.Schemas.WatchResendResult(deliveryIds: ["d1"], success: true)
        )
        let service = GarminStartHandoffService(
            apiService: api,
            forceFailureCode: { nil },
            handoffStore: store
        )

        let result = await service.push(workoutId: "wk-1", gymTitle: "Home")

        XCTAssertNotEqual(result.kind, .failed)
        XCTAssertEqual(store.record?.isInFlight, false)
        XCTAssertEqual(store.restorableMessage(workoutId: "wk-1"), result.message)
        XCTAssertNil(store.takeInterrupted(), "A completed push must never look like a crash")
    }

    func testFailedPushClosesTheRecordAsFailed() async {
        api.pushWatchDeliveryResult = .failure(APIError.serverErrorWithBody(500, "{\"detail\":\"boom\"}"))
        let service = GarminStartHandoffService(
            apiService: api,
            forceFailureCode: { nil },
            handoffStore: store
        )

        let result = await service.push(workoutId: "wk-1", gymTitle: "Home")

        XCTAssertEqual(result.kind, .failed)
        XCTAssertEqual(store.record?.outcome, .failed)
        XCTAssertNil(store.takeInterrupted(), "A handled failure is not an interrupted handoff")
    }
}

final class GarminPairFollowUpTests: XCTestCase {
    func testPrefsSheetFollowsAFirstSuccessfulPair() {
        XCTAssertTrue(
            GarminPairFollowUp.shouldPresentDisplayPrefs(pairSucceeded: true, hasConfiguredPrefs: false)
        )
    }

    func testConfiguredPrefsAreNotAskedAgain() {
        XCTAssertFalse(
            GarminPairFollowUp.shouldPresentDisplayPrefs(pairSucceeded: true, hasConfiguredPrefs: true)
        )
    }

    func testFailedPairDoesNotOpenPrefs() {
        XCTAssertFalse(
            GarminPairFollowUp.shouldPresentDisplayPrefs(pairSucceeded: false, hasConfiguredPrefs: false)
        )
    }
}
