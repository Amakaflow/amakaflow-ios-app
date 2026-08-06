//
//  AppleStartHandoffTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2287: Start → Apple try — honest status copy + handoff paths.
//

import XCTest
import WatchConnectivity
import WorkoutKit
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

    // MARK: - AMA-2330 P1 fix: `showsManageScheduledPlans` on success

    func testScheduledMessageAlwaysShowsManageScheduledPlans() {
        for pairing: AppleWatchPairingRead in [.confirmedPaired, .unknown, .confirmedUnpaired] {
            let result = AppleStartHandoffCopy.scheduledInWorkoutMessage(
                workoutName: "Easy Run",
                pairing: pairing
            )
            XCTAssertTrue(result.showsManageScheduledPlans)
        }
    }

    func testSentToWatchMessageDoesNotShowManageScheduledPlans() {
        let result = AppleStartHandoffCopy.sentToWatchMessage(workoutName: "Push Day")
        XCTAssertFalse(result.showsManageScheduledPlans)
    }
}

/// AMA-2371 final review I4 — mirrors `GarminSentCardGateTests`. The detail
/// screen's compact lime "Scheduled on Apple Watch" card must only appear
/// for a terminal Apple success (`.savedToFitness` / `.sentToWatch`), not
/// for a still-in-flight preview or a failure/blocked outcome.
final class AppleSentCardGateTests: XCTestCase {
    func testSavedToFitnessIsATerminalSentCardSuccess() {
        XCTAssertTrue(AppleStartHandoffResult.Kind.savedToFitness.isTerminalAppleSentCardSuccess)
    }

    func testSentToWatchIsATerminalSentCardSuccess() {
        XCTAssertTrue(AppleStartHandoffResult.Kind.sentToWatch.isTerminalAppleSentCardSuccess)
    }

    func testFailedIsNotATerminalSentCardSuccess() {
        XCTAssertFalse(AppleStartHandoffResult.Kind.failed.isTerminalAppleSentCardSuccess)
    }

    func testBlockedIsNotATerminalSentCardSuccess() {
        XCTAssertFalse(AppleStartHandoffResult.Kind.blocked.isTerminalAppleSentCardSuccess)
    }

    func testPreviewReadyIsNotATerminalSentCardSuccess() {
        XCTAssertFalse(
            AppleStartHandoffResult.Kind.previewReady.isTerminalAppleSentCardSuccess,
            "The preview sheet is still in flight — nothing has been scheduled yet"
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
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
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
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
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
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: Data(#"""
            {"title":"Empty","sportType":"strengthTraining","intervals":[]}
            """#.utf8)),
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
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("permission denied"))
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Settings"))
    }

    func testNilWorkoutKitSaverIsBlockedIosUnsupported() async {
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .disabled,
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
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
            workoutKitSaver: .injected(MockWorkoutKitSaver()),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
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
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
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
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Manage scheduled plans"))
        XCTAssertEqual(saver.saveCallCount, 0, "must not save (and must not auto-delete) once at cap")
        // AMA-2330 P1 fix: at-cap failure must offer the same "Manage scheduled
        // plans" entry point as a successful schedule.
        XCTAssertTrue(result.showsManageScheduledPlans)
    }

    func testScheduleCapReachedBlocksWhenOverCap() async {
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 20, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
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
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(saver.saveCallCount, 1)
    }

    func testEmptyMapperPlanFailsWithoutSaveWhenUnderCap() async {
        let empty = Workout(
            name: "Empty", sport: .strength, duration: 0, intervals: [], source: .manual
        )
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 0, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: Data(#"""
            {"title":"Empty","sportType":"strengthTraining","intervals":[]}
            """#.utf8)),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: empty)
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("no steps"))
        XCTAssertEqual(saver.saveCallCount, 0)
        XCTAssertEqual(reader.statusCallCount, 1)
    }

    func testAtCapBlocksBeforeMapperCompose() async {
        let empty = Workout(
            name: "Empty", sport: .strength, duration: 0, intervals: [], source: .manual
        )
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 15, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: Data(#"""
            {"title":"Empty","sportType":"strengthTraining","intervals":[]}
            """#.utf8)),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: empty)
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("full"))
        XCTAssertEqual(saver.saveCallCount, 0)
        XCTAssertEqual(reader.statusCallCount, 1)
    }

    func testForcedFailureEnvironmentTakesPriorityOverCapPreflight() async {
        setenv("UITEST_APPLE_TRY_FAIL", "watch_not_reachable", 1)
        defer { unsetenv("UITEST_APPLE_TRY_FAIL") }
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 15, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("not reachable"))
        XCTAssertEqual(reader.statusCallCount, 0)
    }

    // MARK: - AMA-2330 P1 fix: `showsManageScheduledPlans` scoped to the cap failure only

    func testEmptyWorkoutFailureDoesNotShowManageScheduledPlans() async {
        let empty = Workout(
            name: "Empty", sport: .strength, duration: 0, intervals: [], source: .manual
        )
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(MockWorkoutKitSaver()),
            planProvider: StubWorkoutKitPlanProvider(json: Data(#"""
            {"title":"Empty","sportType":"strengthTraining","intervals":[]}
            """#.utf8)),
        )
        let result = await service.handoff(workout: empty)
        XCTAssertFalse(result.showsManageScheduledPlans)
    }

    func testBlockedIosUnsupportedDoesNotShowManageScheduledPlans() async {
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .disabled,
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertFalse(result.showsManageScheduledPlans)
    }

    func testUnderCapSaveShowsManageScheduledPlans() async {
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 14, maxAllowedCount: 15)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
            scheduleCapReader: .injected(reader)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertTrue(result.showsManageScheduledPlans)
    }

    func testForcedScheduleCapReachedShowsManageScheduledPlans() async {
        setenv("UITEST_APPLE_TRY_FAIL", "schedule_cap_reached", 1)
        defer { unsetenv("UITEST_APPLE_TRY_FAIL") }
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(MockWorkoutKitSaver()),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.showsManageScheduledPlans)
    }

    func testForcedOtherFailureDoesNotShowManageScheduledPlans() async {
        setenv("UITEST_APPLE_TRY_FAIL", "authorization_denied", 1)
        defer { unsetenv("UITEST_APPLE_TRY_FAIL") }
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(MockWorkoutKitSaver()),
            planProvider: StubWorkoutKitPlanProvider(json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")),
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertFalse(result.showsManageScheduledPlans)
    }

    func testConfirmScheduleReplacesIncompleteSameTitlePlans() async {
        let saver = MockWorkoutKitSaver()
        let replacer = MockIncompleteScheduleReplacer(
            matchingRows: [Self.incompleteRow(title: "Testing Apple 2")]
        )
        let planJSON = StubWorkoutKitPlanProvider.strengthFixture(title: "Testing Apple 2")
        let meta = WorkoutKitPlanMeta(fromMapperJSON: planJSON)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            incompleteScheduleReplacer: .injected(replacer)
        )
        let result = await service.confirmSchedule(
            workoutName: "Testing Apple 2",
            planJSON: planJSON,
            meta: meta
        )
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(replacer.findCallTitles, ["Testing Apple 2"])
        XCTAssertEqual(replacer.removedTitles, ["Testing Apple 2"])
        XCTAssertEqual(saver.saveCallCount, 1)
    }

    func testConfirmScheduleAllowsIntentionalCopyAlongsideOriginal() async {
        let saver = MockWorkoutKitSaver()
        // Finder only returns exact-title matches — a "(1)" copy must not wipe the original.
        let replacer = MockIncompleteScheduleReplacer(matchingRows: [])
        let planJSON = StubWorkoutKitPlanProvider.strengthFixture(title: "Testing Apple 2 (1)")
        let meta = WorkoutKitPlanMeta(fromMapperJSON: planJSON)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            incompleteScheduleReplacer: .injected(replacer)
        )
        let result = await service.confirmSchedule(
            workoutName: "Testing Apple 2 (1)",
            planJSON: planJSON,
            meta: meta
        )
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(replacer.findCallTitles, ["Testing Apple 2 (1)"])
        XCTAssertTrue(replacer.removedRows.isEmpty)
        XCTAssertEqual(saver.saveCallCount, 1)
        XCTAssertTrue(WatchWorkoutTitlePolicy.isIntentionalCopy("Testing Apple 2 (1)"))
        XCTAssertFalse(
            WatchWorkoutTitlePolicy.isSameScheduledTitle("Testing Apple 2", "Testing Apple 2 (1)")
        )
    }

    func testConfirmScheduleSurfacesReplacementLookupFailure() async {
        let saver = MockWorkoutKitSaver()
        let replacer = MockIncompleteScheduleReplacer(
            findError: NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "schedule fetch failed"
            ])
        )
        let planJSON = StubWorkoutKitPlanProvider.strengthFixture(title: "Testing Apple 2")
        let meta = WorkoutKitPlanMeta(fromMapperJSON: planJSON)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            incompleteScheduleReplacer: .injected(replacer)
        )
        let result = await service.confirmSchedule(
            workoutName: "Testing Apple 2",
            planJSON: planJSON,
            meta: meta
        )
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("schedule fetch failed"))
        XCTAssertEqual(saver.saveCallCount, 0)
        XCTAssertTrue(replacer.removedRows.isEmpty)
    }

    func testConfirmScheduleKeepsExistingOnSaveFailure() async {
        let saver = MockWorkoutKitSaver()
        saver.errorToThrow = WorkoutPlanError.saveFailed(
            NSError(domain: "test", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "save blew up"
            ])
        )
        let replacer = MockIncompleteScheduleReplacer(
            matchingRows: [Self.incompleteRow(title: "Testing Apple 2")]
        )
        let planJSON = StubWorkoutKitPlanProvider.strengthFixture(title: "Testing Apple 2")
        let meta = WorkoutKitPlanMeta(fromMapperJSON: planJSON)
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            incompleteScheduleReplacer: .injected(replacer)
        )
        let result = await service.confirmSchedule(
            workoutName: "Testing Apple 2",
            planJSON: planJSON,
            meta: meta
        )
        XCTAssertEqual(result.kind, .failed)
        XCTAssertEqual(saver.saveCallCount, 1)
        XCTAssertEqual(replacer.findCallTitles, ["Testing Apple 2"])
        XCTAssertTrue(replacer.removedRows.isEmpty, "must not remove existing schedule when save fails")
    }

    func testAtCapAllowsWhenMatchingIncompleteCanReplace() async {
        let saver = MockWorkoutKitSaver()
        let reader = MockScheduleCapReader(scheduledCount: 15, maxAllowedCount: 15)
        let replacer = MockIncompleteScheduleReplacer(
            matchingRows: [Self.incompleteRow(title: "Test Strength")]
        )
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: .injected(saver),
            planProvider: StubWorkoutKitPlanProvider(
                json: StubWorkoutKitPlanProvider.strengthFixture(title: "Test Strength")
            ),
            scheduleCapReader: .injected(reader),
            incompleteScheduleReplacer: .injected(replacer)
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(saver.saveCallCount, 1)
        XCTAssertEqual(replacer.removedTitles, ["Test Strength"])
        XCTAssertEqual(reader.statusCallCount, 2, "prepare + confirm both evaluate the live cap")
    }

    private static func incompleteRow(title: String) -> WorkoutScheduleRow {
        WorkoutScheduleRow(
            id: WorkoutScheduleRowID(
                planID: "incomplete-\(title)",
                date: DateComponents(year: 2026, month: 8, day: 1, hour: 9)
            ),
            title: title,
            dateComponents: DateComponents(year: 2026, month: 8, day: 1, hour: 9),
            scheduledAt: nil,
            isComplete: false
        )
    }

    func testEnrichmentFixtureParsesRestAndWarmupSteps() throws {
        // AMA-2366 — mapper wire shape must decode under workoutkit-sync ≥ 1.5.0
        let json = Data(
            #"""
            {
              "title": "One Squat",
              "sportType": "strengthTraining",
              "composition": "custom",
              "composition_effective": "custom",
              "routing_reason": "strength_sets",
              "intervals": [
                { "kind": "reps", "reps": 1, "name": "Jump Rope" },
                {
                  "kind": "repeat",
                  "reps": 1,
                  "intervals": [
                    { "kind": "reps", "reps": 8, "name": "WU · Barbell back squat" },
                    { "kind": "rest", "name": "Rest · tap" },
                    { "kind": "reps", "reps": 5, "name": "WU · Barbell back squat" }
                  ]
                },
                {
                  "kind": "repeat",
                  "reps": 3,
                  "intervals": [
                    { "kind": "reps", "reps": 10, "name": "Barbell back squat" },
                    { "kind": "rest", "name": "Rest · tap" }
                  ]
                }
              ]
            }
            """#.utf8
        )
        let dto = try WorkoutKitSync.default.parse(from: json)
        XCTAssertEqual(dto.intervals.count, 3)
        let lines = WorkoutKitPlanStepSummary.lines(from: json, limit: 20)
        XCTAssertTrue(lines.contains(where: { $0.contains("Jump Rope") }), String(describing: lines))
        XCTAssertTrue(lines.contains(where: { $0.contains("WU ·") }), String(describing: lines))
        XCTAssertTrue(lines.contains(where: { $0.contains("Rest · tap") }), String(describing: lines))
        XCTAssertTrue(lines.contains(where: { $0.contains("Repeat ×3") }), String(describing: lines))

        if #available(iOS 18.0, *) {
            let plan = try WorkoutPlanConverter().convert(dto)
            guard case .custom(let custom) = plan.workout else {
                return XCTFail("expected custom workout")
            }
            // Jump Rope block + WU block + work block — must not collapse to work-only.
            XCTAssertGreaterThanOrEqual(custom.blocks.count, 3, String(describing: custom.blocks.count))
            let recoveryCount = custom.blocks
                .flatMap(\.steps)
                .filter { $0.purpose == .recovery }
                .count
            XCTAssertGreaterThanOrEqual(recoveryCount, 2, "open rest must map to recovery")
        }
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
    private(set) var savedPlanTitles: [String] = []
    /// Attempts, incremented before any throw — tests assert 0 to prove fail-fast.
    private(set) var saveCallCount = 0
    var errorToThrow: Error?

    /// Compatibility for older assertions that used workout.name.
    var savedWorkoutNames: [String] { savedPlanTitles }

    func saveMapperPlanJSON(_ data: Data) async throws {
        saveCallCount += 1
        if let errorToThrow { throw errorToThrow }
        let title = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["title"] as? String
        savedPlanTitles.append(title ?? "untitled")
    }
}

private final class MockIncompleteScheduleReplacer: IncompleteScheduleReplacing, @unchecked Sendable {
    private(set) var findCallTitles: [String] = []
    private(set) var removedRows: [WorkoutScheduleRow] = []
    var matchingRows: [WorkoutScheduleRow]
    var findError: Error?

    init(matchingRows: [WorkoutScheduleRow] = [], findError: Error? = nil) {
        self.matchingRows = matchingRows
        self.findError = findError
    }

    var removedTitles: [String] { removedRows.map(\.title) }

    func findIncompletePlans(titled title: String) async throws -> [WorkoutScheduleRow] {
        findCallTitles.append(title)
        if let findError { throw findError }
        let needle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return matchingRows.filter {
            !$0.isComplete
                && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle
        }
    }

    func remove(rows: [WorkoutScheduleRow]) async {
        removedRows.append(contentsOf: rows)
    }
}

private struct StubWorkoutKitPlanProvider: WorkoutKitPlanProviding {
    var json: Data
    var error: Error?

    func fetchMapperPlanJSON(for workout: Workout) async throws -> Data {
        _ = workout
        if let error { throw error }
        return json
    }

    static func strengthFixture(title: String = "Test Strength") -> Data {
        Data(
            #"""
            {"title":"\#(title)","sportType":"strengthTraining","composition":"custom","composition_effective":"custom","routing_reason":"strength_sets","intervals":[{"kind":"reps","reps":8,"name":"Squat"}]}
            """#.utf8
        )
    }
}
