//
//  WorkoutCompletionModuleTests.swift
//  AmakaFlowCompanionTests
//
//  Issue #446: state-machine tests for WorkoutCompletionModule.
//  Issue #448: savePhoneCompletion round-trip tests.
//  No WorkoutEngine spy — tests drive the module directly.
//

import Combine
import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutCompletionModuleTests: XCTestCase {

    private var module: WorkoutCompletionModule!

    override func setUp() async throws {
        try await super.setUp()
        module = WorkoutCompletionModule()
    }

    override func tearDown() async throws {
        module = nil
        try await super.tearDown()
    }

    func test_initialState_isIdle() {
        XCTAssertEqual(module.saveStatus, .idle)
        XCTAssertNil(module.lastSaveError)
    }

    func test_idle_inFlight_succeeded() {
        module.beginSave()
        XCTAssertEqual(module.saveStatus, .inFlight)
        XCTAssertNil(module.lastSaveError)

        module.succeedSave()
        XCTAssertEqual(module.saveStatus, .succeeded)
        XCTAssertNil(module.lastSaveError)
    }

    func test_idle_inFlight_failed() {
        let error = CTAError.network(code: .notConnectedToInternet)

        module.beginSave()
        XCTAssertEqual(module.saveStatus, .inFlight)
        XCTAssertNil(module.lastSaveError)

        module.failSave(error)
        XCTAssertEqual(module.saveStatus, .failed(error))
        XCTAssertEqual(module.lastSaveError, error)
    }

    func test_acknowledgeError_resetsToIdle() {
        let error = CTAError.network(code: .timedOut)
        module.beginSave()
        module.failSave(error)

        module.acknowledgeError()
        XCTAssertEqual(module.saveStatus, .idle)
        XCTAssertNil(module.lastSaveError)
    }

    func test_beginSave_clearsPriorSaveError() {
        let error = CTAError.network(code: .timedOut)
        module.beginSave()
        module.failSave(error)

        module.beginSave()
        XCTAssertNil(module.lastSaveError)
        XCTAssertEqual(module.saveStatus, .inFlight)
    }
}

// MARK: - savePhoneCompletion tests (issue #448)

@MainActor
final class WorkoutCompletionModuleSaveTests: XCTestCase {

    private var module: WorkoutCompletionModule!
    private var completionService: StubWorkoutCompletionService!

    override func setUp() async throws {
        try await super.setUp()
        completionService = StubWorkoutCompletionService()
        module = WorkoutCompletionModule(
            queueService: StubWorkoutCompletionQueueService(),
            completionService: completionService
        )
    }

    override func tearDown() async throws {
        module = nil
        completionService = nil
        try await super.tearDown()
    }

    func test_savePhoneCompletion_success_marksSucceeded() async {
        completionService.result = .success(
            WorkoutCompletionResponse(completionId: "cid-1", id: nil, status: "saved", success: true)
        )

        await module.savePhoneCompletion(
            workoutId: "w1", workoutName: "Run", startedAt: Date(), endedAt: Date(),
            durationSeconds: 600, avgHeartRate: nil, activeCalories: nil,
            heartRateSamples: nil, workoutStructure: nil, isSimulated: false,
            setLogs: nil, executionLog: nil
        )

        guard case .succeeded = module.saveStatus else {
            return XCTFail("expected .succeeded, got \(module.saveStatus)")
        }
        XCTAssertNil(module.lastSaveError)
    }

    func test_savePhoneCompletion_lyingSuccess_marksFailedNonRetryable() async {
        completionService.result = .success(
            WorkoutCompletionResponse(completionId: nil, id: nil, status: "rejected", success: false)
        )

        await module.savePhoneCompletion(
            workoutId: "w1", workoutName: "Run", startedAt: Date(), endedAt: Date(),
            durationSeconds: 600, avgHeartRate: nil, activeCalories: nil,
            heartRateSamples: nil, workoutStructure: nil, isSimulated: false,
            setLogs: nil, executionLog: nil
        )

        guard case .failed(let cta) = module.saveStatus,
              case .lyingSuccess(let message, let errorCode, _) = cta else {
            return XCTFail("expected .failed(.lyingSuccess), got \(module.saveStatus)")
        }
        XCTAssertEqual(message, "Workout completion failed")
        XCTAssertEqual(errorCode, "WORKOUT_COMPLETION_FAILED")
        XCTAssertFalse(cta.isRetryable)
    }

    func test_savePhoneCompletion_networkError_marksFailedRetryable() async {
        completionService.result = .failure(URLError(.notConnectedToInternet))

        await module.savePhoneCompletion(
            workoutId: "w1", workoutName: "Run", startedAt: Date(), endedAt: Date(),
            durationSeconds: 600, avgHeartRate: nil, activeCalories: nil,
            heartRateSamples: nil, workoutStructure: nil, isSimulated: false,
            setLogs: nil, executionLog: nil
        )

        guard case .failed(let cta) = module.saveStatus,
              case .network(let code, _) = cta else {
            return XCTFail("expected .failed(.network), got \(module.saveStatus)")
        }
        XCTAssertEqual(code, .notConnectedToInternet)
        XCTAssertTrue(cta.isRetryable)
    }

    func test_savePhoneCompletion_4xxError_marksFailedNonRetryable() async {
        completionService.result = .failure(APIError.serverError(422))

        await module.savePhoneCompletion(
            workoutId: "w1", workoutName: "Run", startedAt: Date(), endedAt: Date(),
            durationSeconds: 600, avgHeartRate: nil, activeCalories: nil,
            heartRateSamples: nil, workoutStructure: nil, isSimulated: false,
            setLogs: nil, executionLog: nil
        )

        guard case .failed(let cta) = module.saveStatus,
              case .http(let status, _, _) = cta else {
            return XCTFail("expected .failed(.http), got \(module.saveStatus)")
        }
        XCTAssertEqual(status, 422)
        XCTAssertFalse(cta.isRetryable, "4xx must not offer Retry")
    }

    func test_savePhoneCompletion_5xxError_marksFailedRetryable() async {
        completionService.result = .failure(APIError.serverError(503))

        await module.savePhoneCompletion(
            workoutId: "w1", workoutName: "Run", startedAt: Date(), endedAt: Date(),
            durationSeconds: 600, avgHeartRate: nil, activeCalories: nil,
            heartRateSamples: nil, workoutStructure: nil, isSimulated: false,
            setLogs: nil, executionLog: nil
        )

        guard case .failed(let cta) = module.saveStatus,
              case .http(let status, _, _) = cta else {
            return XCTFail("expected .failed(.http), got \(module.saveStatus)")
        }
        XCTAssertEqual(status, 503)
        XCTAssertTrue(cta.isRetryable, "5xx must offer Retry")
    }

    // Verifies the `onWorkoutCompleted` callback fires only on terminal success —
    // no WorkoutEngine or NotificationCenter observation needed.
    func test_workoutCompleted_callbackFiresOnTerminalSuccessOnly() async {
        var callbackWorkoutIds: [String] = []
        module.onWorkoutCompleted = { id in callbackWorkoutIds.append(id) }

        // Failure path — callback must NOT fire
        completionService.result = .failure(URLError(.notConnectedToInternet))
        await module.savePhoneCompletion(
            workoutId: "w-fail", workoutName: "Run", startedAt: Date(), endedAt: Date(),
            durationSeconds: 300, avgHeartRate: nil, activeCalories: nil,
            heartRateSamples: nil, workoutStructure: nil, isSimulated: false,
            setLogs: nil, executionLog: nil
        )
        XCTAssertTrue(callbackWorkoutIds.isEmpty, "callback must not fire on failure")

        // Success path — callback must fire with the correct id
        module.acknowledgeError()
        completionService.result = .success(
            WorkoutCompletionResponse(completionId: "cid-cb", id: nil, status: "saved", success: true)
        )
        await module.savePhoneCompletion(
            workoutId: "w-success", workoutName: "Run", startedAt: Date(), endedAt: Date(),
            durationSeconds: 300, avgHeartRate: nil, activeCalories: nil,
            heartRateSamples: nil, workoutStructure: nil, isSimulated: false,
            setLogs: nil, executionLog: nil
        )
        XCTAssertEqual(callbackWorkoutIds, ["w-success"],
                       "callback must fire exactly once on terminal success with the workout id")
    }

    func test_savePhoneCompletion_beginsInFlight_thenTransitions() async {
        var capturedDuringFlight: WorkoutCompletionModule.SaveStatus?
        completionService.onCall = {
            capturedDuringFlight = self.module.saveStatus
        }
        completionService.result = .success(
            WorkoutCompletionResponse(completionId: "cid-2", id: nil, status: "saved", success: true)
        )

        await module.savePhoneCompletion(
            workoutId: "w1", workoutName: "Run", startedAt: Date(), endedAt: Date(),
            durationSeconds: 600, avgHeartRate: nil, activeCalories: nil,
            heartRateSamples: nil, workoutStructure: nil, isSimulated: false,
            setLogs: nil, executionLog: nil
        )

        XCTAssertEqual(capturedDuringFlight, .inFlight)
        guard case .succeeded = module.saveStatus else {
            return XCTFail("expected .succeeded after completion")
        }
    }
}

// MARK: - Stubs

@MainActor
private final class StubWorkoutCompletionService: WorkoutCompletionServiceProviding {
    var result: Result<WorkoutCompletionResponse?, Error> = .success(nil)
    var onCall: (() -> Void)?

    func postPhoneWorkoutCompletion(
        workoutId: String,
        workoutName: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        avgHeartRate: Int?,
        activeCalories: Int?,
        heartRateSamples: [HRSample]?,
        workoutStructure: [WorkoutInterval]?,
        isSimulated: Bool,
        setLogs: [SetLog]?,
        executionLog: [String: Any]?
    ) async throws -> WorkoutCompletionResponse? {
        onCall?()
        return try result.get()
    }

    func postWatchWorkoutCompletion(
        summary: StandaloneWorkoutSummary,
        workoutStructure: [WorkoutInterval]?,
        workoutName: String?
    ) async throws -> WorkoutCompletionResponse? {
        onCall?()
        return try result.get()
    }

    func postGarminWorkoutCompletion(
        workoutId: String,
        startedAt: Date,
        endedAt: Date,
        avgHeartRate: Int?,
        activeCalories: Int?,
        workoutStructure: [WorkoutInterval]?,
        workoutName: String?
    ) async throws -> WorkoutCompletionResponse? {
        onCall?()
        return try result.get()
    }
}

@MainActor
private final class StubWorkoutCompletionQueueService: WorkoutCompletionQueueProviding {
    var pendingCount: Int = 0
    var pendingCountPublisher: AnyPublisher<Int, Never> { Just(0).eraseToAnyPublisher() }
    func retryPendingCompletions() async {}
}

// MARK: - saveWatchCompletion tests (issue #449)

@MainActor
final class WorkoutCompletionModuleWatchTests: XCTestCase {

    private var module: WorkoutCompletionModule!
    private var completionService: StubWorkoutCompletionService!

    override func setUp() async throws {
        try await super.setUp()
        completionService = StubWorkoutCompletionService()
        module = WorkoutCompletionModule(
            queueService: StubWorkoutCompletionQueueService(),
            completionService: completionService
        )
    }

    override func tearDown() async throws {
        module = nil
        completionService = nil
        try await super.tearDown()
    }

    private func makeSummary(workoutId: String = "watch-w1") -> StandaloneWorkoutSummary {
        StandaloneWorkoutSummary(
            workoutId: workoutId,
            workoutName: "Watch Run",
            startDate: Date(),
            endDate: Date(),
            durationSeconds: 1800,
            totalCalories: 300,
            averageHeartRate: 145,
            completedSteps: 3,
            totalSteps: 3
        )
    }

    func test_saveWatchCompletion_success_callsOnWorkoutCompleted() async {
        completionService.result = .success(
            WorkoutCompletionResponse(completionId: "cid-w1", id: nil, status: "saved", success: true)
        )
        var receivedWorkoutId: String?
        module.onWorkoutCompleted = { id in receivedWorkoutId = id }

        await module.saveWatchCompletion(summary: makeSummary(workoutId: "watch-w1"))

        guard case .succeeded = module.saveStatus else {
            return XCTFail("expected .succeeded, got \(module.saveStatus)")
        }
        XCTAssertEqual(receivedWorkoutId, "watch-w1", "callback must carry the workoutId")
    }

    func test_saveWatchCompletion_networkError_doesNotCallOnWorkoutCompleted() async {
        completionService.result = .failure(URLError(.notConnectedToInternet))
        var callbackFired = false
        module.onWorkoutCompleted = { _ in callbackFired = true }

        await module.saveWatchCompletion(summary: makeSummary())

        guard case .failed = module.saveStatus else {
            return XCTFail("expected .failed, got \(module.saveStatus)")
        }
        XCTAssertFalse(callbackFired, "callback must NOT fire on failure")
    }

    func test_saveWatchCompletion_beginsInFlight_thenSucceeds() async {
        var capturedDuringFlight: WorkoutCompletionModule.SaveStatus?
        completionService.onCall = {
            capturedDuringFlight = self.module.saveStatus
        }
        completionService.result = .success(
            WorkoutCompletionResponse(completionId: "cid-w2", id: nil, status: "saved", success: true)
        )

        await module.saveWatchCompletion(summary: makeSummary())

        XCTAssertEqual(capturedDuringFlight, .inFlight)
        guard case .succeeded = module.saveStatus else {
            return XCTFail("expected .succeeded after completion")
        }
    }
}
