//
//  AMA1834_WorkoutEngine_IntervalStateMachineTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1834 / L2 — Workout state machine: interval transitions
//
//  Per docs/testing/blueprint.md, AMA-1834 = "user actually performs a
//  full workout (intervals + HR data + execution_log)". This file covers
//  the iOS-side interval state machine that the user drives during the
//  workout itself: work → rest → next-work → done, plus pause/resume.
//
//  No real network. No real HealthKit. No real timers — TestClock drives
//  every tick deterministically, and WorkoutEngine is built with the
//  same DI surface used by the existing CJ-01 L2 / WorkoutEngineTests
//  fixtures (clock + audioService + progressStore + pairingService).
//
//  Naming follows the blueprint XCTest convention:
//      test_<feature>__<condition>__<expectedOutcome>
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class AMA1834_WorkoutEngine_IntervalStateMachineTests: XCTestCase {

    // MARK: - Fixtures

    private var engine: WorkoutEngine!
    private var clock: TestClock!
    private var audio: MockAudioService!
    private var progress: MockProgressStore!
    private var pairing: MockPairingService!

    override func setUp() async throws {
        clock = TestClock()
        audio = MockAudioService()
        progress = MockProgressStore()
        pairing = MockPairingService()
        // Configure UNPAIRED so end() does NOT trigger a real network
        // call to APIService.shared.postWorkoutCompletion (the engine
        // short-circuits with an auth error and only mutates local
        // state — exactly what we want for L2).
        pairing.configureUnpaired()

        engine = WorkoutEngine(
            clock: clock,
            audioService: audio,
            progressStore: progress,
            pairingService: pairing
        )
    }

    override func tearDown() async throws {
        engine.reset()
        engine = nil
        clock = nil
        audio = nil
        progress = nil
        pairing = nil
    }

    // MARK: - Helpers

    /// A workout that exercises the full work → rest → next-work → done
    /// transition. Per `flattenIntervals`, `.reps(sets: 2, restSec: 5)`
    /// expands into TWO `.reps` flattened steps, with the first one
    /// carrying `hasRestAfter=true, restAfterSeconds=5` (timed rest
    /// between sets 1 and 2 — the "between-work rest" the AMA-1834
    /// spec is concerned with). Then a cooldown closes the workout.
    ///
    /// Resulting flattenedSteps:
    ///   [0] Warm Up      (timed=10, hasRestAfter=true,  restAfterSeconds=nil → manual rest)
    ///   [1] Push-ups #1  (reps,     hasRestAfter=true,  restAfterSeconds=5   → 5s timed rest)
    ///   [2] Push-ups #2  (reps,     hasRestAfter=false)
    ///   [3] Cool Down    (timed=10, hasRestAfter=false)
    private func threeIntervalWorkout() -> Workout {
        TestFixtures.workout(
            id: "ama-1834-state-machine",
            name: "AMA-1834 State Machine",
            intervals: [
                .warmup(seconds: 10, target: nil),
                .reps(sets: 2, reps: 5, name: "Push-ups", load: nil, restSec: 5, followAlongUrl: nil),
                .cooldown(seconds: 10, target: nil)
            ]
        )
    }

    // MARK: - Tests

    func test_workoutEngine__threeIntervalsCompleted__transitionsThroughExpectedStates() {
        let workout = threeIntervalWorkout()

        engine.start(workout: workout)
        XCTAssertEqual(engine.phase, .running, "after start, engine should be in .running phase")
        XCTAssertEqual(engine.currentStepIndex, 0, "first step should be index 0 (warmup)")
        XCTAssertEqual(
            engine.flattenedSteps.count, 4,
            "warmup + reps(sets:2,restSec:5) + cooldown should flatten to 4 steps (warmup, reps#1, reps#2, cooldown); got \(engine.flattenedSteps.count)"
        )
        XCTAssertEqual(engine.flattenedSteps[0].stepType, .timed, "step 0 should be timed (warmup)")
        XCTAssertEqual(engine.flattenedSteps[1].stepType, .reps, "step 1 should be reps (set 1 of 2)")
        XCTAssertEqual(engine.flattenedSteps[2].stepType, .reps, "step 2 should be reps (set 2 of 2)")
        XCTAssertEqual(engine.flattenedSteps[3].stepType, .timed, "step 3 should be timed (cooldown)")
        XCTAssertTrue(
            engine.flattenedSteps[1].hasRestAfter,
            "reps set 1 must carry hasRestAfter=true so the engine enters .resting between sets"
        )
        XCTAssertEqual(
            engine.flattenedSteps[1].restAfterSeconds, 5,
            "reps set 1 must carry restAfterSeconds=5 from the source `.reps(restSec:5)`"
        )

        // Advance past warmup → should land on reps set 1 (index 1).
        // Warmup has hasRestAfter=true with restAfterSeconds=nil
        // (manual rest), so nextStep() from index 0 actually enters
        // .resting first. completeRest() then advances to index 1.
        engine.nextStep()
        XCTAssertEqual(
            engine.phase, .resting,
            "after nextStep on warmup, engine enters manual rest (warmup carries hasRestAfter=true, restAfterSeconds=nil)"
        )
        XCTAssertTrue(engine.isManualRest, "warmup-to-reps gap is a manual rest (tap when ready)")
        engine.completeRest()
        XCTAssertEqual(engine.currentStepIndex, 1, "after completeRest, should be on reps set 1")
        XCTAssertEqual(engine.phase, .running, "phase should be .running on reps set 1")

        // nextStep() from reps set 1 enters .resting because
        // hasRestAfter=true with restAfterSeconds=5 (timed rest).
        engine.nextStep()
        XCTAssertEqual(
            engine.phase, .resting,
            "after nextStep on reps-set-1-with-rest, engine should enter .resting"
        )
        XCTAssertEqual(
            engine.currentStepIndex, 1,
            "during rest the index stays on the just-completed reps step"
        )
        XCTAssertEqual(
            engine.restRemainingSeconds, 5,
            "rest should be timed with restSec=5; got \(engine.restRemainingSeconds)"
        )
        XCTAssertFalse(engine.isManualRest, "5s timed rest must NOT be flagged as manualRest")

        // completeRest() advances to reps set 2 (index 2).
        engine.completeRest()
        XCTAssertEqual(engine.phase, .running, "after completeRest, phase should return to .running")
        XCTAssertEqual(
            engine.currentStepIndex, 2,
            "completeRest should advance to reps set 2 (index 2); got \(engine.currentStepIndex)"
        )

        // reps set 2 has hasRestAfter=false → nextStep() advances directly to cooldown.
        engine.nextStep()
        XCTAssertEqual(
            engine.phase, .running,
            "after nextStep on final reps set (no rest after), engine stays running"
        )
        XCTAssertEqual(
            engine.currentStepIndex, 3,
            "should land on cooldown (index 3); got \(engine.currentStepIndex)"
        )

        // End the workout — engine should land in .ended.
        engine.end(reason: .completed)
        XCTAssertEqual(engine.phase, .ended, "after end(.completed), phase should be .ended")
        XCTAssertTrue(
            audio.announceWorkoutCompleteCalled,
            "announceWorkoutComplete should fire on .completed end reason"
        )
    }

    func test_workoutEngine__pauseDuringWork__resumeContinuesSameInterval() throws {
        let workout = threeIntervalWorkout()
        engine.start(workout: workout)

        let stepBeforePause = engine.currentStepIndex
        let phaseBefore = engine.phase
        XCTAssertEqual(phaseBefore, .running, "precondition: engine starts running")

        engine.pause()
        XCTAssertEqual(engine.phase, .paused, "after pause(), phase should be .paused")
        XCTAssertEqual(
            engine.currentStepIndex, stepBeforePause,
            "pause must NOT advance the step index"
        )
        XCTAssertTrue(audio.announcePausedCalled, "announcePaused should fire on pause()")

        engine.resume()
        XCTAssertEqual(engine.phase, .running, "after resume(), phase should return to .running")
        XCTAssertEqual(
            engine.currentStepIndex, stepBeforePause,
            "resume must NOT change the step index"
        )
        XCTAssertTrue(audio.announceResumedCalled, "announceResumed should fire on resume()")
    }
}
