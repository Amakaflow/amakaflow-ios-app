//
//  AppleStartHandoffTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2287: Start → Apple try — honest status copy + handoff paths.
//

import XCTest
import WorkoutKitSync
@testable import AmakaFlowCompanion

@MainActor
final class AppleStartHandoffCopyTests: XCTestCase {

    func testFailureCopyWatchNotReachableIsRecoverable() {
        let message = AppleStartHandoffCopy.failureMessage(code: .watchNotReachable)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("not reachable"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("AmakaFlowWatch"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("stub"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("AMA-2287"))
    }

    func testSentToWatchMessageIsNotStub() {
        let result = AppleStartHandoffCopy.sentToWatchMessage(workoutName: "Push Day")
        XCTAssertEqual(result.kind, .sentToWatch)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("sent"))
        XCTAssertTrue(result.message.contains("Push Day"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("stub"))
    }

    func testSavedToFitnessMessageIsNotStub() {
        let result = AppleStartHandoffCopy.savedToFitnessMessage(workoutName: "Easy Run")
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Apple Fitness"))
        XCTAssertTrue(result.message.contains("Easy Run"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("stub"))
    }

    func testFailureCodeMapsAuthorizationDenied() {
        XCTAssertEqual(
            AppleStartHandoffCopy.failureCode(from: WorkoutPlanError.authorizationDenied),
            .authorizationDenied
        )
    }
}

@MainActor
final class AppleStartHandoffServiceTests: XCTestCase {
    private func sampleWorkout() -> Workout {
        Workout(
            name: "Test Strength",
            sport: .strength,
            duration: 1800,
            intervals: [
                .reps(sets: 3, reps: 8, name: "Squat", load: nil, restSec: 90, followAlongUrl: nil)
            ],
            source: .manual
        )
    }

    func testHandoffWatchReachableSendSuccess() async {
        let mock = MockWatchSession()
        mock.isReachable = true
        mock.isWatchAppInstalled = true
        mock.sendMessageReply = ["status": "received"]
        let manager = WatchConnectivityManager(session: mock)

        let service = AppleStartHandoffService(
            watchManager: manager,
            workoutKitSaver: MockWorkoutKitSaver()
        )
        let result = await service.handoff(workout: sampleWorkout(), watchReachable: true)

        XCTAssertEqual(result.kind, .sentToWatch)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Sent to Apple Watch"))
    }

    func testHandoffWatchUnreachableFallsBackToFitnessSave() async {
        let mock = MockWatchSession()
        mock.isReachable = false
        let manager = WatchConnectivityManager(session: mock)
        let saver = MockWorkoutKitSaver()

        let service = AppleStartHandoffService(
            watchManager: manager,
            workoutKitSaver: saver
        )
        let result = await service.handoff(workout: sampleWorkout(), watchReachable: false)

        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(saver.savedWorkoutNames, ["Test Strength"])
    }

    func testHandoffWatchSendRejectedFallsBackToFitnessSave() async {
        let mock = MockWatchSession()
        mock.isReachable = true
        mock.sendMessageReply = ["status": "error", "message": "decode_failed"]
        let manager = WatchConnectivityManager(session: mock)
        let saver = MockWorkoutKitSaver()

        let service = AppleStartHandoffService(
            watchManager: manager,
            workoutKitSaver: saver
        )
        let result = await service.handoff(workout: sampleWorkout(), watchReachable: true)

        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(saver.savedWorkoutNames, ["Test Strength"])
    }

    func testHandoffEmptyWorkoutFailsFast() async {
        let empty = Workout(
            name: "Empty",
            sport: .strength,
            duration: 0,
            intervals: [],
            source: .manual
        )
        let service = AppleStartHandoffService(
            watchManager: WatchConnectivityManager(session: MockWatchSession()),
            workoutKitSaver: MockWorkoutKitSaver()
        )
        let result = await service.handoff(workout: empty, watchReachable: false)

        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("no steps"))
    }

    func testForcedFailureEnvironment() async {
        setenv("UITEST_APPLE_TRY_FAIL", "authorization_denied", 1)
        defer { unsetenv("UITEST_APPLE_TRY_FAIL") }

        let service = AppleStartHandoffService(
            watchManager: WatchConnectivityManager(session: MockWatchSession()),
            workoutKitSaver: MockWorkoutKitSaver()
        )
        let result = await service.handoff(workout: sampleWorkout(), watchReachable: true)

        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("permission denied"))
    }
}

@MainActor
final class WatchWorkoutSendOutcomeTests: XCTestCase {

    func testSendWorkoutWithOutcomeSuccessWhenWatchAcks() async {
        let mock = MockWatchSession()
        mock.isReachable = true
        mock.sendMessageReply = ["status": "received"]
        let manager = WatchConnectivityManager(session: mock)

        let workout = Workout(
            name: "Ack Test",
            sport: .running,
            duration: 1200,
            intervals: [.time(seconds: 600, target: nil)],
            source: .manual
        )

        let outcome = await manager.sendWorkoutWithOutcome(workout)
        XCTAssertEqual(outcome, .sent)
        XCTAssertTrue(mock.sendMessageCalled)
    }

    func testSendWorkoutWithOutcomeWatchRejected() async {
        let mock = MockWatchSession()
        mock.isReachable = true
        mock.sendMessageReply = ["status": "error", "message": "decode_failed"]
        let manager = WatchConnectivityManager(session: mock)

        let workout = Workout(
            name: "Reject Test",
            sport: .running,
            duration: 1200,
            intervals: [.time(seconds: 600, target: nil)],
            source: .manual
        )

        let outcome = await manager.sendWorkoutWithOutcome(workout)
        XCTAssertEqual(outcome, .watchRejected("decode_failed"))
    }
}

private final class MockWorkoutKitSaver: WorkoutKitSaving, @unchecked Sendable {
    private(set) var savedWorkoutNames: [String] = []
    var errorToThrow: Error?

    func saveToWorkoutKit(_ workout: Workout) async throws {
        if let errorToThrow { throw errorToThrow }
        savedWorkoutNames.append(workout.name)
    }
}
