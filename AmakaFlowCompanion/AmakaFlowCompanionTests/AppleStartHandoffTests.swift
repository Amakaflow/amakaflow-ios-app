//
//  AppleStartHandoffTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2287: Start → Apple try — honest status copy + handoff paths.
//

import XCTest
import WatchConnectivity
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

    func testScheduledMessagePairedOrUnknownIsWatchLeading() {
        for pairing: AppleWatchPairingRead in [.confirmedPaired, .unknown] {
            let result = AppleStartHandoffCopy.scheduledInWorkoutMessage(
                workoutName: "Easy Run",
                pairing: pairing
            )
            XCTAssertEqual(result.kind, .savedToFitness)
            XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Workout"))
            XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Apple Watch"))
            XCTAssertTrue(result.message.contains("Easy Run"))
            XCTAssertFalse(result.message.localizedCaseInsensitiveContains("Apple Fitness"))
            XCTAssertFalse(result.message.localizedCaseInsensitiveContains("iPhone"))
            XCTAssertFalse(result.message.localizedCaseInsensitiveContains("AmakaFlowWatch"))
        }
    }

    func testScheduledMessageConfirmedUnpairedAsksToPair() {
        let result = AppleStartHandoffCopy.scheduledInWorkoutMessage(
            workoutName: "Push Day",
            pairing: .confirmedUnpaired
        )
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("pair"))
        XCTAssertTrue(result.message.contains("Push Day"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("open the Workout app on your Apple Watch"))
    }

    func testAuthorizationDeniedCopyMentionsSettingsHealth() {
        let message = AppleStartHandoffCopy.failureMessage(code: .authorizationDenied)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("permission denied"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Settings"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Health"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("Apple Fitness"))
    }

    func testIosUnsupportedCopyMentionsWorkoutApp() {
        let message = AppleStartHandoffCopy.failureMessage(code: .iosVersionUnsupported)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("iOS 18"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Workout"))
    }

    // MARK: - AMA-2330: at-cap preflight copy

    func testScheduleCapReachedCopyPointsToManageScheduledPlans() {
        let message = AppleStartHandoffCopy.failureMessage(code: .scheduleCapReached)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Manage scheduled plans"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Devices"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Scheduled in Workout"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("full"))
    }

    func testScheduleCapReachedCopyNeverImpliesAutoDelete() {
        let message = AppleStartHandoffCopy.failureMessage(code: .scheduleCapReached)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("automatically"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("we removed"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("we deleted"))
    }

    func testFailureCodeMapsAuthorizationDenied() {
        XCTAssertEqual(
            AppleStartHandoffCopy.failureCode(from: WorkoutPlanError.authorizationDenied),
            .authorizationDenied
        )
    }
}

@MainActor
final class AppleWatchPairingReadTests: XCTestCase {
    func testNotActivatedIsUnknownEvenIfIsPairedFalse() {
        let mock = MockWatchSession()
        mock.activationState = .notActivated
        mock.isPaired = false
        XCTAssertEqual(AppleWatchPairingRead.resolve(from: mock), .unknown)
    }

    func testActivatedAndNotPairedIsConfirmedUnpaired() {
        let mock = MockWatchSession()
        mock.activationState = .activated
        mock.isPaired = false
        XCTAssertEqual(AppleWatchPairingRead.resolve(from: mock), .confirmedUnpaired)
    }

    func testActivatedAndPairedIsConfirmedPaired() {
        let mock = MockWatchSession()
        mock.activationState = .activated
        mock.isPaired = true
        XCTAssertEqual(AppleWatchPairingRead.resolve(from: mock), .confirmedPaired)
    }

    func testNilSessionIsUnknown() {
        XCTAssertEqual(AppleWatchPairingRead.resolve(from: nil), .unknown)
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

    func testHandoffAlwaysSavesViaWorkoutKit() async {
        let saver = MockWorkoutKitSaver()
        let pairing = MockPairingReader(read: .unknown)
        let service = AppleStartHandoffService(
            pairingReader: pairing,
            workoutKitSaver: .injected(saver)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(saver.savedWorkoutNames, ["Test Strength"])
        XCTAssertEqual(saver.saveCallCount, 1)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Apple Watch"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("Sent to Apple Watch"))
    }

    func testHandoffConfirmedUnpairedUsesPairCopy() async {
        let saver = MockWorkoutKitSaver()
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .confirmedUnpaired),
            workoutKitSaver: .injected(saver)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("pair"))
    }

    func testHandoffEmptyWorkoutFailsFastWithoutSave() async {
        let empty = Workout(
            name: "Empty", sport: .strength, duration: 0, intervals: [], source: .manual
        )
        let saver = MockWorkoutKitSaver()
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver)
        )
        let result = await service.handoff(workout: empty)
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("no steps"))
        XCTAssertEqual(saver.saveCallCount, 0)
    }

    func testAuthorizationDeniedMapsToSettingsCopy() async {
        let saver = MockWorkoutKitSaver()
        saver.errorToThrow = WorkoutPlanError.authorizationDenied
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .confirmedPaired),
            workoutKitSaver: .injected(saver)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("permission denied"))
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Settings"))
    }

    func testNilWorkoutKitSaverIsBlockedIosUnsupported() async {
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .disabled
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .blocked)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("iOS 18"))
    }

    func testForcedFailureEnvironment() async {
        setenv("UITEST_APPLE_TRY_FAIL", "authorization_denied", 1)
        defer { unsetenv("UITEST_APPLE_TRY_FAIL") }
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(MockWorkoutKitSaver())
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("permission denied"))
    }

    // MARK: - AMA-2330: at-cap preflight

    func testScheduleCapReaderOmittedNeverBlocksSave() async {
        // Default `scheduleCapReader` is `.disabled` — existing/omitted call sites
        // must keep saving exactly as before this feature existed.
        let saver = MockWorkoutKitSaver()
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(saver.saveCallCount, 1)
    }

    func testScheduleCapReachedBlocksBeforeSaveWhenAtCap() async {
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 15, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Manage scheduled plans"))
        XCTAssertEqual(saver.saveCallCount, 0, "must not save (and must not auto-delete) once at cap")
    }

    func testScheduleCapReachedBlocksWhenOverCap() async {
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 20, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertEqual(saver.saveCallCount, 0)
    }

    func testUnderCapStillSavesNormally() async {
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 14, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(saver.saveCallCount, 1)
    }

    func testEmptyWorkoutFailsFastBeforeCapPreflight() async {
        // Cap check should never run (and never matter) when the empty-workout
        // guard already fails fast — preflight ordering must not regress this.
        let empty = Workout(
            name: "Empty", sport: .strength, duration: 0, intervals: [], source: .manual
        )
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 15, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: empty)
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("no steps"))
        XCTAssertEqual(reader.statusCallCount, 0)
    }

    func testForcedFailureEnvironmentTakesPriorityOverCapPreflight() async {
        setenv("UITEST_APPLE_TRY_FAIL", "watch_not_reachable", 1)
        defer { unsetenv("UITEST_APPLE_TRY_FAIL") }
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 15, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("not reachable"))
        XCTAssertEqual(reader.statusCallCount, 0)
    }
}

private struct MockPairingReader: AppleWatchPairingReading {
    let read: AppleWatchPairingRead
    func pairingReadForCopy() -> AppleWatchPairingRead { read }
}

private final class MockScheduleCapReader: ScheduleCapReading, @unchecked Sendable {
    let scheduledCount: Int
    let maxAllowedCount: Int
    private(set) var statusCallCount = 0

    init(scheduledCount: Int, maxAllowedCount: Int) {
        self.scheduledCount = scheduledCount
        self.maxAllowedCount = maxAllowedCount
    }

    func scheduleCapStatus() async -> (scheduledCount: Int, maxAllowedCount: Int) {
        statusCallCount += 1
        return (scheduledCount, maxAllowedCount)
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
    /// Attempts, incremented before any throw — tests assert 0 to prove fail-fast.
    private(set) var saveCallCount = 0
    var errorToThrow: Error?

    func saveToWorkoutKit(_ workout: Workout) async throws {
        saveCallCount += 1
        if let errorToThrow { throw errorToThrow }
        savedWorkoutNames.append(workout.name)
    }
}
