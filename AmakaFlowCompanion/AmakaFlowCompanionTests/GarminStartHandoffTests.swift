//
//  GarminStartHandoffTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2286: Start → Garmin push success + forced failure paths.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class GarminStartHandoffCopyTests: XCTestCase {

    func testFailureCopyNotPairedIsRecoverable() {
        let message = GarminStartHandoffCopy.failureMessage(code: .notPaired)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("not paired"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("devices"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("stub"))
    }

    func testUnpairedRecoveryCopyIsActionable() {
        XCTAssertTrue(
            GarminStartHandoffCopy.unpairedRecoverySubtitle
                .localizedCaseInsensitiveContains("pair")
        )
        XCTAssertTrue(
            GarminStartHandoffCopy.unpairedRecoverySubtitle
                .localizedCaseInsensitiveContains("devices")
                || GarminStartHandoffCopy.unpairedRecoverySubtitle
                    .localizedCaseInsensitiveContains("ciq")
        )
        XCTAssertEqual(GarminStartHandoffCopy.unpairedRecoveryTag, "PAIR")
        XCTAssertEqual(
            GarminStartHandoffCopy.unpairedRecoveryStatusMessage,
            GarminStartHandoffCopy.failureMessage(code: .notPaired)
        )
        XCTAssertFalse(
            GarminStartHandoffCopy.unpairedRecoverySubtitle
                .localizedCaseInsensitiveContains("settings to push")
        )
    }

    func testFailureCodeMapsEmptyConverterAndAuth() {
        XCTAssertEqual(
            GarminStartHandoffCopy.failureCode(fromHTTPStatus: 422, detail: "empty_converter"),
            .emptyConverter
        )
        XCTAssertEqual(
            GarminStartHandoffCopy.failureCode(fromHTTPStatus: 422, detail: "fit_too_large"),
            .fitTooLarge
        )
        XCTAssertEqual(
            GarminStartHandoffCopy.failureCode(
                fromHTTPStatus: 422,
                detail: "User has no paired Garmin devices"
            ),
            .notPaired
        )
        XCTAssertEqual(
            GarminStartHandoffCopy.failureCode(fromHTTPStatus: 401, detail: nil),
            .auth
        )
    }

    func testSuccessMessageForPushedIsNotStub() {
        let result = GarminStartHandoffCopy.successMessage(state: .pushed, workoutName: "Engine EMOM")
        XCTAssertEqual(result.kind, .sent)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("sent"))
        XCTAssertTrue(result.message.contains("Engine EMOM"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("Home gym"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("AMA-2286"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("stub"))
    }

    func testSuccessMessageUsesWorkoutNameNotGym() {
        let result = GarminStartHandoffCopy.successMessage(state: .pushed, workoutName: "For time x 5")
        XCTAssertTrue(result.message.contains("For time x 5"))
    }
}

@MainActor
final class GarminStartHandoffServiceTests: XCTestCase {
    private var api: MockAPIService!

    override func setUp() async throws {
        try await super.setUp()
        api = MockAPIService()
    }

    override func tearDown() async throws {
        api = nil
        try await super.tearDown()
    }

    func testPushSuccessUsesWatchDeliveryStatus() async {
        api.pushWatchDeliveryResult = .success(
            Components.Schemas.WatchResendResult(deliveryIds: ["d1"], success: true)
        )
        api.watchDeliveryStatusResult = .success(
            Components.Schemas.WatchDeliveryStatus(
                canResend: false,
                occurredAt: "2026-07-14T12:00:00Z",
                state: .pushed,
                subtitle: "Sent to your watch — waiting for sync",
                title: "Sent to watch"
            )
        )

        let service = GarminStartHandoffService(apiService: api, forceFailureCode: { nil })
        let result = await service.push(workoutId: "wk-strength", workoutName: "Strength A", gymTitle: "Home gym")

        XCTAssertTrue(api.pushWatchDeliveryCalled)
        XCTAssertEqual(api.lastPushWatchDeliveryWorkoutId, "wk-strength")
        XCTAssertTrue(api.watchDeliveryStatusCalled)
        XCTAssertEqual(api.lastWatchDeliveryWorkoutId, "wk-strength")
        XCTAssertEqual(result.kind, .sent)
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("stub"))
        XCTAssertTrue(result.message.contains("Strength A"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("Home gym"))
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("garmin")
            || result.message.localizedCaseInsensitiveContains("sent"))
    }

    func testPushForcedFailurePathNotPaired() async {
        let service = GarminStartHandoffService(
            apiService: api,
            forceFailureCode: { .notPaired }
        )
        let result = await service.push(workoutId: "wk-1", workoutName: "Engine EMOM", gymTitle: "Home gym")

        XCTAssertFalse(api.pushWatchDeliveryCalled)
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("not paired"))
    }

    func testPushMapsServerEmptyConverter() async {
        api.pushWatchDeliveryResult = .failure(
            APIError.serverErrorWithBody(422, "{\"detail\":\"empty_converter\"}")
        )

        let service = GarminStartHandoffService(apiService: api, forceFailureCode: { nil })
        let result = await service.push(workoutId: "wk-empty", workoutName: "Empty", gymTitle: "Home gym")

        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("exercise"))
    }
}

// MARK: - AMA-2455: the derived plan must actually reach the push body

/// The `hasDerivedWatchPlan` flag tests assert the DECISION; these assert the
/// WIRING. Without them, deleting `blocksJson:` from the push call still passes
/// every existing test — the same gap CodeRabbit flagged on #614.
@MainActor
final class GarminDerivedPlanPushTests: XCTestCase {

    private func makeService(_ api: MockAPIService) -> GarminStartHandoffService {
        GarminStartHandoffService(
            apiService: api,
            forceFailureCode: { nil },
            handoffStore: GarminHandoffStateStore()
        )
    }

    func testDerivedPlanBlocksReachTheGarminPushBody() async {
        let api = MockAPIService()
        let blocks: [[String: Any]] = [
            ["label": "Warm-up", "exercises": [["name": "Ski Erg"]]],
            ["label": "Main", "exercises": [["name": "Back Squat"]]]
        ]

        _ = await makeService(api).push(
            workoutId: "wk-derived",
            workoutName: "Engine EMOM",
            gymTitle: "Home",
            blocksJson: blocks
        )

        XCTAssertTrue(api.pushWatchDeliveryCalled, "the push must actually be attempted")
        guard let sent = api.lastPushWatchDeliveryBlocksJson else {
            return XCTFail("derived plan blocks were dropped before reaching the push body (AMA-2455)")
        }
        XCTAssertEqual(
            sent.count, 2,
            "every block of the derived plan must ride the push, not just the first"
        )
        XCTAssertEqual(
            sent.compactMap { $0["label"] as? String }, ["Warm-up", "Main"],
            "block order and content must survive the hop to the push body"
        )
    }

    func testPushWithoutDerivedPlanSendsNoBlocks() async {
        let api = MockAPIService()

        _ = await makeService(api).push(
            workoutId: "wk-plain",
            workoutName: "Authored only",
            gymTitle: "Home"
        )

        XCTAssertTrue(api.pushWatchDeliveryCalled)
        XCTAssertNil(
            api.lastPushWatchDeliveryBlocksJson,
            "no derived plan → the body must omit blocksJson so the backend falls back to stored workout_data"
        )
    }
}
