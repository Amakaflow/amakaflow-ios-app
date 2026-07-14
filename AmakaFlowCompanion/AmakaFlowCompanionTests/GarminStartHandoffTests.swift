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
        let result = GarminStartHandoffCopy.successMessage(state: .pushed, gymTitle: "Home gym")
        XCTAssertEqual(result.kind, .sent)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("sent"))
        XCTAssertTrue(result.message.contains("Home gym"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("AMA-2286"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("stub"))
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
        let result = await service.push(workoutId: "wk-strength", gymTitle: "Home gym")

        XCTAssertTrue(api.pushWatchDeliveryCalled)
        XCTAssertEqual(api.lastPushWatchDeliveryWorkoutId, "wk-strength")
        XCTAssertEqual(result.kind, .sent)
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("stub"))
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("garmin")
            || result.message.localizedCaseInsensitiveContains("sent"))
    }

    func testPushForcedFailurePathNotPaired() async {
        let service = GarminStartHandoffService(
            apiService: api,
            forceFailureCode: { .notPaired }
        )
        let result = await service.push(workoutId: "wk-1", gymTitle: "Home gym")

        XCTAssertFalse(api.pushWatchDeliveryCalled)
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("not paired"))
    }

    func testPushMapsServerEmptyConverter() async {
        api.pushWatchDeliveryResult = .failure(
            APIError.serverErrorWithBody(422, "{\"detail\":\"empty_converter\"}")
        )

        let service = GarminStartHandoffService(apiService: api, forceFailureCode: { nil })
        let result = await service.push(workoutId: "wk-empty", gymTitle: "Home gym")

        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("exercise"))
    }
}
