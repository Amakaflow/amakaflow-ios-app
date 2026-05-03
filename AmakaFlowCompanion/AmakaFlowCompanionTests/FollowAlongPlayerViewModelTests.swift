//
//  FollowAlongPlayerViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1182: Tests for FollowAlongPlayerViewModel
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class FollowAlongPlayerViewModelTests: XCTestCase {

    private var sut: FollowAlongPlayerViewModel!

    override func setUp() {
        super.setUp()
        sut = FollowAlongPlayerViewModel()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Loading

    func testLoadWorkoutExtractsSteps() {
        let workout = TestFixtures.workout(
            intervals: [
                .warmup(seconds: 60, target: "Easy"),
                .reps(sets: nil, reps: 10, name: "Push-ups", load: nil, restSec: 15, followAlongUrl: nil),
                .cooldown(seconds: 60, target: nil)
            ]
        )

        sut.loadWorkout(workout)

        // warmup + reps + rest(15s) + cooldown = 4 steps
        XCTAssertEqual(sut.steps.count, 4)
        XCTAssertEqual(sut.phase, .ready)
        XCTAssertEqual(sut.currentStepIndex, 0)
        XCTAssertEqual(sut.elapsedSeconds, 0)
    }

    func testLoadWorkoutWithRepeatExpandsRounds() {
        let workout = TestFixtures.workout(
            intervals: [
                .repeat(reps: 2, intervals: [
                    .reps(sets: nil, reps: 5, name: "Squats", load: nil, restSec: nil, followAlongUrl: nil)
                ])
            ]
        )

        sut.loadWorkout(workout)

        // 2 rounds * 1 exercise = 2 steps
        XCTAssertEqual(sut.steps.count, 2)
        XCTAssertTrue(sut.steps[0].name.contains("Round 1"))
        XCTAssertTrue(sut.steps[1].name.contains("Round 2"))
    }

    func testLoadEmptyWorkoutEndsWithError() {
        let workout = TestFixtures.workout(intervals: [])

        sut.loadWorkout(workout)

        XCTAssertEqual(sut.phase, .ended)
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - Playback Controls

    func testPlayFromReady() {
        loadSampleWorkout()

        sut.play()

        XCTAssertEqual(sut.phase, .playing)
    }

    func testPauseFromPlaying() {
        loadSampleWorkout()
        sut.play()

        sut.pause()

        XCTAssertEqual(sut.phase, .paused)
    }

    func testTogglePlayPause() {
        loadSampleWorkout()

        sut.togglePlayPause()
        XCTAssertEqual(sut.phase, .playing)

        sut.togglePlayPause()
        XCTAssertEqual(sut.phase, .paused)

        sut.togglePlayPause()
        XCTAssertEqual(sut.phase, .playing)
    }

    func testPlayDoesNothingWhenEnded() {
        loadSampleWorkout()
        sut.endWorkout()

        sut.play()

        XCTAssertEqual(sut.phase, .ended)
    }

    // MARK: - Step Navigation

    func testSkipToNextStep() {
        loadSampleWorkout()
        XCTAssertEqual(sut.currentStepIndex, 0)

        sut.skipToNextStep()

        XCTAssertEqual(sut.currentStepIndex, 1)
    }

    func testSkipToPreviousStep() {
        loadSampleWorkout()
        sut.skipToNextStep()
        XCTAssertEqual(sut.currentStepIndex, 1)

        sut.skipToPreviousStep()

        XCTAssertEqual(sut.currentStepIndex, 0)
    }

    func testSkipToPreviousDoesNothingAtStart() {
        loadSampleWorkout()
        XCTAssertEqual(sut.currentStepIndex, 0)

        sut.skipToPreviousStep()

        XCTAssertEqual(sut.currentStepIndex, 0)
    }

    func testSkipToNextEndsWorkoutOnLastStep() {
        let workout = TestFixtures.workout(
            intervals: [
                .warmup(seconds: 30, target: nil)
            ]
        )
        sut.loadWorkout(workout)
        XCTAssertEqual(sut.steps.count, 1)

        sut.skipToNextStep()

        XCTAssertEqual(sut.phase, .ended)
    }

    func testSkipToSpecificStep() {
        loadSampleWorkout()

        sut.skipToStep(2)

        XCTAssertEqual(sut.currentStepIndex, 2)
    }

    func testSkipToInvalidStepDoesNothing() {
        loadSampleWorkout()

        sut.skipToStep(999)

        XCTAssertEqual(sut.currentStepIndex, 0)
    }

    // MARK: - Current Step / Progress

    func testCurrentStepReturnsCorrectStep() {
        loadSampleWorkout()

        XCTAssertNotNil(sut.currentStep)
        XCTAssertEqual(sut.currentStep?.name, "Easy")  // warmup target
    }

    func testProgressCalculation() {
        loadSampleWorkout()
        // 4 steps total (warmup + reps + rest + cooldown)
        XCTAssertEqual(sut.progress, 0.0, accuracy: 0.01)

        sut.skipToNextStep()
        XCTAssertEqual(sut.progress, 1.0 / Float(sut.steps.count), accuracy: 0.01)
    }

    // MARK: - Time Formatting

    func testFormattedElapsed() {
        loadSampleWorkout()
        XCTAssertEqual(sut.formattedElapsed, "0:00")
    }

    // MARK: - AMA-1733 Interval Consumption

    func testRepeatWithRepsAndRestExpandsToSixSteps() {
        let workout = TestFixtures.workout(
            intervals: [
                .repeat(reps: 3, intervals: [
                    .reps(sets: nil, reps: 8, name: "Burpees", load: nil, restSec: nil, followAlongUrl: nil),
                    .rest(seconds: 20),
                ]),
            ]
        )

        sut.loadWorkout(workout)

        XCTAssertEqual(sut.steps.count, 6)
        XCTAssertEqual(sut.steps.map(\.name), [
            "Round 1/3 - Burpees",
            "Rest",
            "Round 2/3 - Burpees",
            "Rest",
            "Round 3/3 - Burpees",
            "Rest",
        ])
        XCTAssertEqual(sut.steps.map(\.reps), [8, nil, 8, nil, 8, nil])
        XCTAssertEqual(sut.steps.map(\.durationSeconds), [nil, 20, nil, 20, nil, 20])
    }

    func testRepeatExpansionKeepsNestedTimeAndDistanceNames() {
        let workout = TestFixtures.workout(
            intervals: [
                .repeat(reps: 2, intervals: [
                    .time(seconds: 45, target: "Hard"),
                    .distance(meters: 400, target: "Run"),
                ]),
            ]
        )

        sut.loadWorkout(workout)

        XCTAssertEqual(sut.steps.map(\.name), ["Hard", "Run", "Hard", "Run"])
        XCTAssertEqual(sut.steps.map(\.durationSeconds), [45, 144, 45, 144])
        XCTAssertEqual(sut.steps.map(\.videoTimestamp), [0, 45, 189, 234])
    }

    func testRepsStepPreservesFollowAlongURL() {
        let workout = TestFixtures.workout(
            intervals: [
                .reps(
                    sets: nil,
                    reps: 12,
                    name: "Push-ups",
                    load: nil,
                    restSec: nil,
                    followAlongUrl: "https://video.amakaflow.test/pushups.mp4"
                ),
            ]
        )

        sut.loadWorkout(workout)

        XCTAssertEqual(sut.steps.first?.name, "Push-ups")
        XCTAssertEqual(sut.steps.first?.reps, 12)
        XCTAssertEqual(sut.steps.first?.videoURL?.absoluteString, "https://video.amakaflow.test/pushups.mp4")
    }

    func testManualRestStepUsesDefaultOffsetButNilDuration() {
        let workout = TestFixtures.workout(
            intervals: [
                .time(seconds: 30, target: "Work"),
                .rest(seconds: nil),
                .time(seconds: 15, target: "Finish"),
            ]
        )

        sut.loadWorkout(workout)

        XCTAssertEqual(sut.steps.map(\.name), ["Work", "Rest", "Finish"])
        XCTAssertEqual(sut.steps.map(\.durationSeconds), [30, nil, 15])
        XCTAssertEqual(sut.steps.map(\.videoTimestamp), [0, 30, 60])
    }

    func testTimedRestAdvancesTimestamp() {
        let workout = TestFixtures.workout(
            intervals: [
                .reps(sets: nil, reps: 10, name: "Squats", load: nil, restSec: 30, followAlongUrl: nil),
                .time(seconds: 20, target: "Hold"),
            ]
        )

        sut.loadWorkout(workout)

        XCTAssertEqual(sut.steps.map(\.name), ["Squats", "Rest", "Hold"])
        XCTAssertEqual(sut.steps.map(\.videoTimestamp), [0, 30, 60])
        XCTAssertEqual(sut.steps[1].durationSeconds, 30)
    }

    func testAllIntervalKindsCanBeConsumedIntoSteps() {
        let workout = TestFixtures.workout(
            intervals: [
                .warmup(seconds: 60, target: "Warm"),
                .cooldown(seconds: 45, target: "Cool"),
                .time(seconds: 30, target: "Tempo"),
                .reps(sets: nil, reps: 5, name: "Lunges", load: nil, restSec: nil, followAlongUrl: nil),
                .distance(meters: 500, target: "Run"),
                .repeat(reps: 1, intervals: [.rest(seconds: 10)]),
                .rest(seconds: 15),
            ]
        )

        sut.loadWorkout(workout)

        XCTAssertEqual(sut.phase, .ready)
        XCTAssertEqual(sut.steps.map(\.name), ["Warm", "Cool", "Tempo", "Lunges", "Run", "Rest", "Rest"])
        XCTAssertEqual(sut.steps.map(\.durationSeconds), [60, 45, 30, nil, 180, 10, 15])
    }

    func testStateMachinePausesResumesAndCompletesWorkoutAcrossMixedIntervalKinds() {
        let workout = TestFixtures.workout(
            intervals: [
                .warmup(seconds: 20, target: "Warm"),
                .reps(sets: nil, reps: 6, name: "Step-ups", load: nil, restSec: 10, followAlongUrl: nil),
                .distance(meters: 100, target: "Shuttle"),
            ]
        )
        sut.loadWorkout(workout)

        sut.play()
        XCTAssertEqual(sut.phase, .playing)

        sut.pause()
        XCTAssertEqual(sut.phase, .paused)

        sut.play()
        XCTAssertEqual(sut.phase, .playing)

        while !sut.isLastStep {
            sut.skipToNextStep()
        }
        sut.skipToNextStep()

        XCTAssertEqual(sut.phase, .ended)
    }

    // MARK: - Step Properties

    func testTimedStepHasRemainingSeconds() {
        let workout = TestFixtures.workout(
            intervals: [
                .time(seconds: 120, target: "Plank")
            ]
        )
        sut.loadWorkout(workout)

        XCTAssertEqual(sut.stepRemainingSeconds, 120)
        XCTAssertTrue(sut.currentStep?.isTimeBased ?? false)
    }

    func testRepsStepHasNoRemainingSeconds() {
        let workout = TestFixtures.workout(
            intervals: [
                .reps(sets: nil, reps: 10, name: "Squats", load: nil, restSec: nil, followAlongUrl: nil)
            ]
        )
        sut.loadWorkout(workout)

        XCTAssertEqual(sut.stepRemainingSeconds, 0)
        XCTAssertFalse(sut.currentStep?.isTimeBased ?? true)
        XCTAssertEqual(sut.currentStep?.reps, 10)
    }

    // MARK: - End Workout

    func testEndWorkoutSetsPhaseToEnded() {
        loadSampleWorkout()
        sut.play()

        sut.endWorkout()

        XCTAssertEqual(sut.phase, .ended)
    }

    // MARK: - Direct Step Loading

    func testLoadStepsDirectly() {
        let steps = [
            FollowAlongStep(id: "1", name: "Step 1", durationSeconds: 30, reps: nil, videoURL: nil, videoTimestamp: 0),
            FollowAlongStep(id: "2", name: "Step 2", durationSeconds: 60, reps: nil, videoURL: nil, videoTimestamp: 30),
        ]

        sut.loadSteps(steps)

        XCTAssertEqual(sut.steps.count, 2)
        XCTAssertEqual(sut.phase, .ready)
    }

    // MARK: - Helpers

    private func loadSampleWorkout() {
        let workout = TestFixtures.workout(
            intervals: [
                .warmup(seconds: 60, target: "Easy"),
                .reps(sets: nil, reps: 10, name: "Push-ups", load: nil, restSec: 15, followAlongUrl: nil),
                .cooldown(seconds: 60, target: nil)
            ]
        )
        sut.loadWorkout(workout)
    }
}
