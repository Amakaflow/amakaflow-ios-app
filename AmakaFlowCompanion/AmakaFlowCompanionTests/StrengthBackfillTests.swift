//
//  StrengthBackfillTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2290: phone strength backfill draft/encode round-trip + watch/AI gates.
//

import XCTest
import Combine
@testable import AmakaFlowCompanion

@MainActor
final class StrengthBackfillTests: XCTestCase {

    func testFixtureEmomStrengthDecodable() throws {
        #if DEBUG
        let workout = try FixtureLoader.loadFixture(named: "emom_strength")
        XCTAssertEqual(workout.name, "Manual EMOM Strength")
        XCTAssertTrue(StrengthBackfill.shouldOfferBackfill(intervals: workout.intervals))
        #endif
    }

    func testFixtureLoaderLoadsNamedEmom() throws {
        #if DEBUG
        let workouts = try FixtureLoader.loadWorkouts()
        // When UITEST_FIXTURES unset in unit test host, expect all known fixtures or empty+no crash.
        _ = workouts
        let named = try FixtureLoader.loadFixture(named: "emom_strength")
        XCTAssertFalse(named.intervals.isEmpty)
        #endif
    }

    func testShouldOfferBackfillForRepsIntervals() {
        let intervals: [WorkoutInterval] = [
            .warmup(seconds: 60, target: nil),
            .reps(sets: 3, reps: 8, name: "Bench", load: nil, restSec: 90, followAlongUrl: nil),
            .cooldown(seconds: 60, target: nil)
        ]
        XCTAssertTrue(StrengthBackfill.shouldOfferBackfill(intervals: intervals))
    }

    func testShouldNotOfferBackfillForCardioOnly() {
        let intervals: [WorkoutInterval] = [
            .warmup(seconds: 60, target: nil),
            .distance(meters: 5000, target: "Z2"),
            .cooldown(seconds: 60, target: nil)
        ]
        XCTAssertFalse(StrengthBackfill.shouldOfferBackfill(intervals: intervals))
        XCTAssertFalse(StrengthBackfill.shouldOfferBackfill(intervals: []))
        XCTAssertFalse(StrengthBackfill.shouldOfferBackfill(intervals: nil))
    }

    func testDraftSeedsSetsFromPlannedStructure() {
        let drafts = StrengthBackfill.draft(
            from: [
                .reps(sets: 3, reps: 10, name: "Squat", load: "185", restSec: 120, followAlongUrl: nil),
                .reps(sets: 2, reps: 12, name: "RDL", load: nil, restSec: 90, followAlongUrl: nil)
            ]
        )
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].exerciseName, "Squat")
        XCTAssertEqual(drafts[0].sets.count, 3)
        XCTAssertEqual(drafts[0].sets.map(\.reps), [10, 10, 10])
        XCTAssertEqual(drafts[1].sets.count, 2)
    }

    func testRoundTripPreservesWeightsWithoutAI() {
        var drafts = StrengthBackfill.draft(
            from: [
                .reps(sets: 2, reps: 8, name: "Bench", load: nil, restSec: nil, followAlongUrl: nil)
            ]
        )
        drafts[0].sets[0].weight = 135
        drafts[0].sets[0].unit = "lbs"
        drafts[0].sets[1].weight = 145
        drafts[0].sets[1].unit = "lbs"

        XCTAssertFalse(StrengthBackfill.requiresAISuggestions)
        XCTAssertTrue(StrengthBackfill.roundTripPreservesWeights(drafts))

        let setLogs = StrengthBackfill.setLogs(from: drafts)
        XCTAssertEqual(setLogs.count, 1)
        XCTAssertEqual(setLogs[0].sets[0].weight, 135)
        XCTAssertEqual(setLogs[0].sets[1].weight, 145)
    }

    func testSaveAllowedWithEmptyWeights() {
        let drafts = StrengthBackfill.draft(
            from: [
                .reps(sets: 1, reps: 8, name: "Press", load: nil, restSec: nil, followAlongUrl: nil)
            ]
        )
        let setLogs = StrengthBackfill.setLogs(from: drafts)
        XCTAssertEqual(setLogs.count, 1)
        XCTAssertNil(setLogs[0].sets[0].weight)
        XCTAssertTrue(setLogs[0].sets[0].completed)
    }

    func testWatchIsNeverRequired() {
        XCTAssertFalse(StrengthBackfill.requiresAppleWatch)
    }

    func testPhoneStartCompleteTodayLoop() async {
        FixtureAPIService.resetLivePhoneDiaryForTesting()

        let clock = TestClock()
        let completionModule = WorkoutCompletionModule(
            queueService: StubQueue(),
            completionService: FixturePhoneCompletionService()
        )
        let engine = WorkoutEngine(
            clock: clock,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            pairingService: {
                let pairing = MockPairingService()
                pairing.isPaired = true
                return pairing
            }(),
            completionModule: completionModule
        )

        let workout = Workout(
            id: "ama-2290-phone",
            name: "Phone Push Day",
            sport: .strength,
            duration: 1800,
            intervals: [
                .reps(sets: 2, reps: 8, name: "Bench", load: nil, restSec: 90, followAlongUrl: nil)
            ],
            source: .manual
        )

        engine.start(workout: workout)
        XCTAssertEqual(engine.phase, .running)
        XCTAssertNil(engine.pendingPhoneCompletion)

        engine.end(reason: .userEnded)
        XCTAssertEqual(engine.phase, .ended)
        XCTAssertNotNil(engine.pendingPhoneCompletion)
        XCTAssertTrue(engine.offersStrengthBackfill)
        // Deferred — Today must not see the row until commit.
        XCTAssertFalse(completionModule.saveStatus == .succeeded)

        var drafts = engine.strengthBackfillDrafts()
        drafts[0].sets[0].weight = 135
        drafts[0].sets[1].weight = 140
        let setLogs = StrengthBackfill.setLogs(from: drafts)

        await engine.commitPendingPhoneCompletion(setLogs: setLogs)

        guard case .succeeded = engine.saveStatus else {
            return XCTFail("expected succeeded after commit, got \(engine.saveStatus)")
        }
        XCTAssertNil(engine.pendingPhoneCompletion)
        XCTAssertFalse(StrengthBackfill.requiresAISuggestions)

        let today = TodayDiary.completionsForToday(FixtureAPIService.diaryCompletions(limit: 20, offset: 0))
        XCTAssertTrue(today.contains(where: { $0.source == .phone && $0.workoutName == "Phone Push Day" }))

        FixtureAPIService.resetLivePhoneDiaryForTesting()
        engine.reset()
    }

    func testEngineDefersStrengthButNotCardio() async {
        let clock = TestClock()
        let module = MockDeferredCompletionModule()
        let engine = WorkoutEngine(
            clock: clock,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            pairingService: MockPairingService(),
            completionModule: module
        )

        let cardio = Workout(
            id: "cardio-1",
            name: "Easy Run",
            sport: .running,
            duration: 1800,
            intervals: [.distance(meters: 5000, target: "Z2")],
            source: .manual
        )
        engine.start(workout: cardio)
        engine.end(reason: .completed)
        // Give Task in postWorkoutCompletion a tick
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(engine.pendingPhoneCompletion)
        XCTAssertTrue(module.savePhoneCompletionCalled)

        module.savePhoneCompletionCalled = false
        let strength = Workout(
            id: "strength-1",
            name: "Lift",
            sport: .strength,
            duration: 1200,
            intervals: [.reps(sets: 3, reps: 5, name: "Deadlift", load: nil, restSec: nil, followAlongUrl: nil)],
            source: .manual
        )
        engine.start(workout: strength)
        engine.end(reason: .userEnded)
        XCTAssertNotNil(engine.pendingPhoneCompletion)
        XCTAssertFalse(module.savePhoneCompletionCalled)

        await engine.commitPendingPhoneCompletion(setLogs: nil)
        XCTAssertTrue(module.savePhoneCompletionCalled)
        engine.reset()
    }
}

// MARK: - Test doubles

@MainActor
private final class StubQueue: WorkoutCompletionQueueProviding {
    var pendingCount: Int = 0
    var pendingCountPublisher: AnyPublisher<Int, Never> { Just(0).eraseToAnyPublisher() }
    func retryPendingCompletions() async {}
}

@MainActor
private final class FixturePhoneCompletionService: WorkoutCompletionServiceProviding {
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
        let request = WorkoutCompletionRequest(
            workoutEventId: nil,
            workoutId: workoutId,
            followAlongWorkoutId: nil,
            startedAt: ISO8601DateFormatter().string(from: startedAt),
            endedAt: ISO8601DateFormatter().string(from: endedAt),
            healthMetrics: HealthMetrics(
                avgHeartRate: avgHeartRate,
                maxHeartRate: nil,
                minHeartRate: nil,
                activeCalories: activeCalories,
                totalCalories: nil,
                distanceMeters: nil,
                steps: nil
            ),
            source: "phone",
            deviceInfo: WorkoutDeviceInfo(platform: "ios", model: "iPhone", osVersion: nil),
            heartRateSamples: heartRateSamples,
            workoutStructure: workoutStructure,
            workoutName: workoutName,
            isSimulated: isSimulated ? true : nil,
            setLogs: setLogs,
            executionLog: executionLog.map { AnyCodable($0) },
            clientGeneratedId: UUID().uuidString.lowercased()
        )
        return FixtureAPIService.recordPhoneCompletion(request: request)
    }

    func postWatchWorkoutCompletion(
        summary: StandaloneWorkoutSummary,
        workoutStructure: [WorkoutInterval]?,
        workoutName: String?
    ) async throws -> WorkoutCompletionResponse? { nil }

    func postGarminWorkoutCompletion(
        workoutId: String,
        startedAt: Date,
        endedAt: Date,
        avgHeartRate: Int?,
        activeCalories: Int?,
        workoutStructure: [WorkoutInterval]?,
        workoutName: String?
    ) async throws -> WorkoutCompletionResponse? { nil }
}

@MainActor
private final class MockDeferredCompletionModule: WorkoutCompletionModuleProviding {
    var saveStatus: WorkoutCompletionModule.SaveStatus = .idle
    var lastSaveError: CTAError?
    var pendingCount: Int = 0
    var willChange: AnyPublisher<Void, Never> { Just(()).eraseToAnyPublisher() }
    var onWorkoutCompleted: ((String) -> Void)?
    var savePhoneCompletionCalled = false

    func beginSave() { saveStatus = .inFlight }
    func succeedSave() { saveStatus = .succeeded }
    func failSave(_ error: CTAError) {
        lastSaveError = error
        saveStatus = .failed(error)
    }
    func acknowledgeError() {
        lastSaveError = nil
        if case .failed = saveStatus { saveStatus = .idle }
    }
    func retryPending() async {}

    func savePhoneCompletion(
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
    ) async {
        savePhoneCompletionCalled = true
        beginSave()
        succeedSave()
        onWorkoutCompleted?(workoutId)
    }

    func saveWatchCompletion(summary: StandaloneWorkoutSummary) async {}
    func saveGarminCompletion(
        workoutId: String,
        startedAt: Date,
        endedAt: Date,
        avgHeartRate: Int?,
        activeCalories: Int?,
        workoutStructure: [WorkoutInterval]?,
        workoutName: String?
    ) async {}
}

