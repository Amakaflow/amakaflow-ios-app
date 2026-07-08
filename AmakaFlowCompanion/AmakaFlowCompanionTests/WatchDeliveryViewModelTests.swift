//
//  WatchDeliveryViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2028: Watch delivery timeline + resend coverage.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class WatchDeliveryViewModelTests: XCTestCase {
    private var api: MockAPIService!
    private var viewModel: WatchDeliveryViewModel!
    private let fixedNow = Date(timeIntervalSince1970: 1_779_981_660) // 2026-05-28T15:21:00Z

    override func setUp() async throws {
        try await super.setUp()
        api = MockAPIService()
        viewModel = WatchDeliveryViewModel(
            apiService: api,
            pollIntervalNanoseconds: 20_000_000,
            now: { self.fixedNow }
        )
    }

    override func tearDown() async throws {
        viewModel?.cancelPolling()
        viewModel = nil
        api = nil
        try await super.tearDown()
    }

    func testLoadPerStateSurfacesStatusAndCanResend() async {
        let cases: [(Components.Schemas.WatchDeliveryState, Bool)] = [
            (.generated, false),
            (.pushed, false),
            (.fetchedByWidget, false),
            (.confirmedOnDevice, false),
            (.failed, true)
        ]

        for (state, canResend) in cases {
            api = MockAPIService()
            api.watchDeliveryStatusResult = .success(status(state, canResend: canResend))
            viewModel = WatchDeliveryViewModel(
                apiService: api,
                pollIntervalNanoseconds: 100_000_000,
                now: { self.fixedNow }
            )

            await viewModel.load(workoutId: "workout-\(state.rawValue)")
            viewModel.cancelPolling()

            XCTAssertTrue(api.watchDeliveryStatusCalled)
            XCTAssertEqual(api.lastWatchDeliveryWorkoutId, "workout-\(state.rawValue)")
            XCTAssertEqual(viewModel.state, .content)
            XCTAssertEqual(viewModel.status?.state, state)
            XCTAssertEqual(viewModel.status?.title, title(for: state))
            XCTAssertEqual(viewModel.canResend, canResend)
            XCTAssertEqual(viewModel.stateValue, state.rawValue)
            XCTAssertNil(viewModel.ctaError)
        }
    }

    func testPollingAdvancesAndStopsOnConfirmedTerminalState() async throws {
        api.watchDeliveryStatusResults = [
            .success(status(.generated)),
            .success(status(.pushed)),
            .success(status(.confirmedOnDevice))
        ]

        await viewModel.load(workoutId: "poll-workout")
        XCTAssertEqual(viewModel.status?.state, .generated)

        try await waitUntil { self.viewModel.status?.state == .confirmedOnDevice }

        XCTAssertEqual(viewModel.status?.state, .confirmedOnDevice)
        let callsAtTerminal = api.watchDeliveryStatusCallCount
        // Terminal state stops polling — yield to event loop to confirm call count is stable
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(api.watchDeliveryStatusCallCount, callsAtTerminal, "Polling must stop after confirmed_on_device")
        XCTAssertEqual(viewModel.state, .content)
    }

    func testPollingDoesNotStartForTerminalStates() async throws {
        for terminal in [Components.Schemas.WatchDeliveryState.confirmedOnDevice, .failed] {
            api = MockAPIService()
            api.watchDeliveryStatusResult = .success(status(terminal, canResend: terminal == .failed))
            viewModel = WatchDeliveryViewModel(
                apiService: api,
                pollIntervalNanoseconds: 20_000_000,
                now: { self.fixedNow }
            )

            await viewModel.load(workoutId: "terminal-\(terminal.rawValue)")
            // Terminal state must not trigger polling; yield to event loop to confirm no tasks were scheduled
            for _ in 0..<10 { await Task.yield() }

            XCTAssertEqual(viewModel.status?.state, terminal)
            XCTAssertEqual(api.watchDeliveryStatusCallCount, 1, "Terminal \(terminal.rawValue) must not poll")
        }
    }

    func testResendSuccessReturnsToGeneratedAndResumesPolling() async throws {
        api.watchDeliveryStatusResults = [
            .success(status(.failed, canResend: true)),
            .success(status(.confirmedOnDevice))
        ]
        api.resendWatchDeliveryResult = .success(
            Components.Schemas.WatchResendResult(deliveryIds: ["delivery-1"], success: true)
        )

        await viewModel.load(workoutId: "failed-workout")
        XCTAssertTrue(viewModel.canResend)

        await viewModel.resend()

        XCTAssertTrue(api.resendWatchDeliveryCalled)
        XCTAssertEqual(api.lastResendWatchDeliveryWorkoutId, "failed-workout")
        XCTAssertEqual(viewModel.status?.state, .generated)
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertNil(viewModel.ctaError)
        XCTAssertNil(viewModel.lastFailedAction)

        try await waitUntil { self.viewModel.status?.state == .confirmedOnDevice }
        XCTAssertEqual(viewModel.status?.state, .confirmedOnDevice)
        XCTAssertGreaterThanOrEqual(api.watchDeliveryStatusCallCount, 2)
    }

    func testResendFailure409And422MapCTAErrorAndLastFailedAction() async {
        let errors: [(Int, String)] = [
            (409, "Delivery state cannot be resent"),
            (422, "No Garmin device paired")
        ]

        for (statusCode, detail) in errors {
            api = MockAPIService()
            api.watchDeliveryStatusResult = .success(status(.failed, canResend: true))
            api.resendWatchDeliveryResult = .failure(APIError.serverErrorWithBody(statusCode, "{\"detail\":\"\(detail)\"}"))
            viewModel = WatchDeliveryViewModel(
                apiService: api,
                pollIntervalNanoseconds: 20_000_000,
                now: { self.fixedNow }
            )

            await viewModel.load(workoutId: "failed-\(statusCode)")
            await viewModel.resend()

            XCTAssertTrue(api.resendWatchDeliveryCalled)
            XCTAssertEqual(viewModel.lastFailedAction, .resend(workoutId: "failed-\(statusCode)"))
            guard let ctaError = viewModel.ctaError else {
                return XCTFail("Expected CTAError for \(statusCode)")
            }
            XCTAssertEqual(ctaError, .http(status: statusCode, body: "{\"detail\":\"\(detail)\"}", requestId: nil))
            XCTAssertTrue(ctaError.userMessage.contains(detail))
            XCTAssertEqual(viewModel.status?.state, .failed)
        }
    }

    func testResendLyingSuccessMapsToCTAError() async {
        api.watchDeliveryStatusResult = .success(status(.failed, canResend: true))
        api.resendWatchDeliveryResult = .success(Components.Schemas.WatchResendResult(deliveryIds: nil, success: false))

        await viewModel.load(workoutId: "lying-success-workout")
        await viewModel.resend()

        XCTAssertEqual(viewModel.lastFailedAction, .resend(workoutId: "lying-success-workout"))
        guard let ctaError = viewModel.ctaError else {
            return XCTFail("Expected CTAError for success:false resend")
        }
        guard case .lyingSuccess(let message, _, _) = ctaError else {
            return XCTFail("Expected lyingSuccess, got \(ctaError)")
        }
        XCTAssertEqual(message, "Watch delivery was not resent")
    }

    func testLoadFailureMapsCTAErrorAndRetry() async {
        api.watchDeliveryStatusResult = .failure(APIError.serverErrorWithBody(404, "{\"detail\":\"No watch delivery found\"}"))

        await viewModel.load(workoutId: "missing-workout")

        guard case .error(let ctaError) = viewModel.state else {
            return XCTFail("Expected error state, got \(viewModel.state)")
        }
        XCTAssertEqual(ctaError, .http(status: 404, body: "{\"detail\":\"No watch delivery found\"}", requestId: nil))
        XCTAssertEqual(viewModel.ctaError, ctaError)
        XCTAssertEqual(viewModel.lastFailedAction, .load(workoutId: "missing-workout"))

        api.watchDeliveryStatusResult = .success(status(.pushed))
        await viewModel.retryLastAction()

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.status?.state, .pushed)
        XCTAssertNil(viewModel.ctaError)
    }

    func testRelativeTimeAndGeneratedDecoderHandleWatchDeliverySchemas() throws {
        XCTAssertEqual(
            WatchDeliveryViewModel.relativeTimeText(occurredAt: "2026-05-28T15:20:30Z", now: fixedNow),
            "just now"
        )
        XCTAssertEqual(
            WatchDeliveryViewModel.relativeTimeText(occurredAt: "2026-05-28T15:16:00Z", now: fixedNow),
            "5m ago"
        )
        XCTAssertEqual(
            WatchDeliveryViewModel.relativeTimeText(occurredAt: "2026-05-28T12:21:00Z", now: fixedNow),
            "3h ago"
        )

        let statusJSON = """
        {
          "state": "fetched_by_widget",
          "title": "Fetched by widget",
          "subtitle": "The watch fetched this workout.",
          "occurredAt": "2026-05-28T15:18:00Z",
          "canResend": false
        }
        """.data(using: .utf8)!
        let resendJSON = """
        { "success": true, "deliveryIds": ["delivery-1", "delivery-2"] }
        """.data(using: .utf8)!

        let decoder = APIService.makeGeneratedDecoder()
        let decodedStatus = try decoder.decode(Components.Schemas.WatchDeliveryStatus.self, from: statusJSON)
        let decodedResend = try decoder.decode(Components.Schemas.WatchResendResult.self, from: resendJSON)

        XCTAssertEqual(decodedStatus.state, .fetchedByWidget)
        XCTAssertEqual(decodedStatus.occurredAt, "2026-05-28T15:18:00Z")
        XCTAssertEqual(decodedStatus.canResend, false)
        XCTAssertEqual(decodedResend.deliveryIds, ["delivery-1", "delivery-2"])
        XCTAssertTrue(decodedResend.success)
    }

    private func status(
        _ state: Components.Schemas.WatchDeliveryState,
        canResend: Bool = false,
        occurredAt: String = "2026-05-28T15:16:00Z"
    ) -> Components.Schemas.WatchDeliveryStatus {
        Components.Schemas.WatchDeliveryStatus(
            canResend: canResend,
            occurredAt: occurredAt,
            state: state,
            subtitle: subtitle(for: state),
            title: title(for: state)
        )
    }

    private func title(for state: Components.Schemas.WatchDeliveryState) -> String {
        switch state {
        case .generated: return "Workout generated"
        case .pushed: return "Pushed to Garmin"
        case .fetchedByWidget: return "Fetched by widget"
        case .confirmedOnDevice: return "Confirmed on device"
        case .failed: return "Delivery failed"
        }
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }

    // MARK: - Swift-6 Actor-Deinit Safety (#306)

    // Regression: deinit accessed actor-isolated pollingTask, which can crash when ARC releases the
    // last reference off the MainActor executor (swift_task_deinitOnExecutorImpl). Fix: mark
    // pollingTask nonisolated(unsafe). This test starts polling then releases the VM without calling
    // cancelPolling(); reaching the assertion without aborting proves the deinit path is safe.
    func testDeinitWithActivePollingTaskDoesNotCrash() async throws {
        api.watchDeliveryStatusResults = Array(
            repeating: .success(status(.generated)),
            count: 20
        )
        var local: WatchDeliveryViewModel? = WatchDeliveryViewModel(
            apiService: api,
            pollIntervalNanoseconds: 10_000_000,
            now: { self.fixedNow }
        )
        await local?.load(workoutId: "deinit-test")
        XCTAssertEqual(local?.state, .content)
        local = nil  // triggers deinit → pollingTask?.cancel() without going through cancelPolling()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    private func subtitle(for state: Components.Schemas.WatchDeliveryState) -> String {
        switch state {
        case .generated: return "Queued for delivery."
        case .pushed: return "Sent to Garmin Connect."
        case .fetchedByWidget: return "The watch fetched the workout."
        case .confirmedOnDevice: return "Ready on your watch."
        case .failed: return "Garmin did not acknowledge delivery."
        }
    }
}
