//
//  WorkoutCompletionOfflineQueueTests.swift
//  AmakaFlowCompanionTests
//
//  Issue #447: offline queue consolidated behind WorkoutCompletionModule.
//  Tests exercise the three acceptance-criteria scenarios:
//    1. 503 server error → pendingCount == 1 (enqueue on failure)
//    2. retryPending() with a live API → queue drains
//    3. item evicted once it exceeds maxRetries
//

import XCTest
import Combine
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutCompletionOfflineQueueTests: XCTestCase {

    private var apiService: MockAPIService!
    private var pairingService: MockPairingService!
    private var completionService: WorkoutCompletionService!
    private var module: WorkoutCompletionModule!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        try await super.setUp()
        apiService = MockAPIService()
        pairingService = MockPairingService()
        pairingService.configurePaired()

        completionService = WorkoutCompletionService(
            apiService: apiService,
            pairingService: pairingService,
            isNetworkAvailable: true,
            startNetworkMonitoring: false,
            synchronousIO: true
        )
        module = WorkoutCompletionModule(queueService: completionService)
        clearQueue()
    }

    override func tearDown() async throws {
        clearQueue()
        cancellables.removeAll()
        module = nil
        completionService = nil
        pairingService = nil
        apiService = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func test_enqueueOn503_pendingCountEqualsOne() async throws {
        apiService.postWorkoutCompletionResult = .failure(APIError.serverError(503))

        _ = try? await completionService.postPhoneWorkoutCompletion(
            workoutId: "w1",
            workoutName: "Test",
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: 60,
            avgHeartRate: nil,
            activeCalories: nil,
            heartRateSamples: nil,
            workoutStructure: nil,
            isSimulated: false,
            setLogs: nil,
            executionLog: nil
        )

        await Task.yield()
        XCTAssertEqual(module.pendingCount, 1, "503 should enqueue item; pendingCount should be 1")
    }

    func test_retryPending_drainsQueue_onSuccess() async throws {
        // Seed queue with a failing call first
        apiService.postWorkoutCompletionResult = .failure(APIError.serverError(503))

        _ = try? await completionService.postPhoneWorkoutCompletion(
            workoutId: "w2",
            workoutName: "Test",
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: 60
        )

        await Task.yield()
        XCTAssertEqual(module.pendingCount, 1)

        // Now make the API succeed
        apiService.postWorkoutCompletionResult = .success(
            WorkoutCompletionResponse(completionId: "cid-1", id: nil, status: "ok", success: true)
        )

        await module.retryPending()

        await Task.yield()
        XCTAssertEqual(module.pendingCount, 0, "Successful retry should drain the queue")
    }

    func test_itemEvictedAfterMaxRetries() async throws {
        // Seed queue via a network failure
        apiService.postWorkoutCompletionResult = .failure(APIError.serverError(503))

        _ = try? await completionService.postPhoneWorkoutCompletion(
            workoutId: "w3",
            workoutName: "Test",
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: 60
        )

        await Task.yield()
        XCTAssertEqual(module.pendingCount, 1)

        // Exhaust all retries (maxRetries == 3 inside the service)
        for _ in 0..<3 {
            await module.retryPending()
        }

        await Task.yield()
        XCTAssertEqual(module.pendingCount, 0, "Item should be evicted after maxRetries failures")
    }

    // MARK: - Helpers

    private func clearQueue() {
        UserDefaults.standard.removeObject(
            forKey: DefaultsKey.pendingWorkoutCompletionQueue.rawValue
        )
    }
}
