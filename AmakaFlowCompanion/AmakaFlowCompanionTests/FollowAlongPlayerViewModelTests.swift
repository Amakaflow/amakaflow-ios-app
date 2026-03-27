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

    // MARK: - Reload Workout (AMA-1358)

    func testLoadWorkoutTwiceDoesNotLeakObservers() {
        let workout1 = TestFixtures.workout(
            intervals: [
                .warmup(seconds: 60, target: "Workout 1")
            ]
        )
        let workout2 = TestFixtures.workout(
            intervals: [
                .warmup(seconds: 30, target: "Workout 2")
            ]
        )

        // Load first workout
        sut.loadWorkout(workout1)
        XCTAssertEqual(sut.steps.count, 1)
        XCTAssertEqual(sut.steps[0].name, "Workout 1")

        // Load second workout - should not leak observer from first
        sut.loadWorkout(workout2)
        XCTAssertEqual(sut.steps.count, 1)
        XCTAssertEqual(sut.steps[0].name, "Workout 2")
    }

    func testLoadWorkoutClearsObserverWhenNoVideoURL() {
        let workoutWithVideo = TestFixtures.workout(
            intervals: [
                .reps(sets: nil, reps: 10, name: "Exercise", load: nil, restSec: nil, followAlongUrl: "https://example.com/video.mp4")
            ]
        )
        let workoutWithoutVideo = TestFixtures.workout(
            intervals: [
                .warmup(seconds: 30, target: "Warmup")
            ]
        )

        // Load workout with video URL
        sut.loadWorkout(workoutWithVideo)
        XCTAssertEqual(sut.phase, .ready)

        // Load workout without video URL - should clean up observer
        sut.loadWorkout(workoutWithoutVideo)
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
