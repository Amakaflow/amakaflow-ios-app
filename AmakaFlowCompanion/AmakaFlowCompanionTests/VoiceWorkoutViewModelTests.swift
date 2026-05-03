//
//  VoiceWorkoutViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1733: Tests for VoiceWorkoutViewModel interval consumption.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class VoiceWorkoutViewModelTests: XCTestCase {

  private var sut: VoiceWorkoutViewModel!

  override func setUp() {
    super.setUp()
    sut = VoiceWorkoutViewModel()
  }

  override func tearDown() {
    sut = nil
    super.tearDown()
  }

  // MARK: - updateIntervals

  func testUpdateIntervalsReplacesWorkoutIntervals() {
    sut.seedWorkout(intervals: [.time(seconds: 60, target: "old")])

    let intervals: [WorkoutInterval] = [
      .warmup(seconds: 90, target: "hips"),
      .time(seconds: 180, target: "tempo"),
    ]
    sut.updateIntervals(intervals)

    XCTAssertEqual(sut.workout?.intervals, intervals)
  }

  func testUpdateIntervalsPreservesWorkoutIdentityAndMetadata() {
    sut.seedWorkout(
      id: "voice-1",
      name: "Voice Session",
      sport: .running,
      description: "from transcript",
      intervals: [.time(seconds: 60, target: "old")]
    )

    sut.updateIntervals([.distance(meters: 1_000, target: "easy")])

    XCTAssertEqual(sut.workout?.id, "voice-1")
    XCTAssertEqual(sut.workout?.name, "Voice Session")
    XCTAssertEqual(sut.workout?.sport, .running)
    XCTAssertEqual(sut.workout?.description, "from transcript")
    XCTAssertEqual(sut.workout?.source, .ai)
  }

  func testUpdateIntervalsDoesNothingWithoutWorkout() {
    sut.updateIntervals([.time(seconds: 60, target: nil)])

    XCTAssertNil(sut.workout)
  }

  // MARK: - Duration Calculation

  func testUpdateIntervalsCalculatesWarmupDuration() {
    assertDuration(for: [.warmup(seconds: 120, target: "easy")], expected: 120)
  }

  func testUpdateIntervalsCalculatesCooldownDuration() {
    assertDuration(for: [.cooldown(seconds: 150, target: "walk")], expected: 150)
  }

  func testUpdateIntervalsCalculatesTimeDuration() {
    assertDuration(for: [.time(seconds: 240, target: "steady")], expected: 240)
  }

  func testUpdateIntervalsCalculatesRepsDurationWithExplicitSetsAndRest() {
    assertDuration(
      for: [
        .reps(
          sets: 4, reps: 8, name: "Bench Press", load: "82.5kg", restSec: 120, followAlongUrl: nil)
      ],
      expected: 600
    )
  }

  func testUpdateIntervalsCalculatesRepsDurationWithDefaultSetsAndNoRest() {
    assertDuration(
      for: [
        .reps(sets: nil, reps: 12, name: "Push-ups", load: nil, restSec: nil, followAlongUrl: nil)
      ],
      expected: 90
    )
  }

  func testUpdateIntervalsCalculatesDistanceDuration() {
    assertDuration(for: [.distance(meters: 1_500, target: "run")], expected: 450)
  }

  func testUpdateIntervalsCalculatesRepeatDurationRecursively() {
    let intervals: [WorkoutInterval] = [
      .repeat(
        reps: 3,
        intervals: [
          .time(seconds: 45, target: "hard"),
          .rest(seconds: 15),
        ])
    ]

    assertDuration(for: intervals, expected: 180)
  }

  func testUpdateIntervalsCalculatesTimedRestDuration() {
    assertDuration(for: [.rest(seconds: 75)], expected: 75)
  }

  func testUpdateIntervalsCalculatesManualRestDuration() {
    assertDuration(for: [.rest(seconds: nil)], expected: 60)
  }

  func testUpdateIntervalsCalculatesCanonicalAMA1720SuggestedWorkoutDuration() {
    assertDuration(for: Self.canonicalAMA1720Intervals, expected: 2_370)
  }

  // MARK: - Helpers

  private func assertDuration(
    for intervals: [WorkoutInterval],
    expected expectedDuration: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    sut.seedWorkout(intervals: [])
    sut.updateIntervals(intervals)
    XCTAssertEqual(sut.workout?.duration, expectedDuration, file: file, line: line)
  }

  private static var canonicalAMA1720Intervals: [WorkoutInterval] {
    [
      .warmup(seconds: 600, target: "bench press warm-up sets at 40 kg"),
      .reps(
        sets: 4, reps: 8, name: "bench press", load: "82.5 kg", restSec: 120, followAlongUrl: nil),
      .reps(
        sets: 3, reps: 10, name: "incline bench press", load: "60.0 kg", restSec: 90,
        followAlongUrl: nil),
      .reps(
        sets: 3, reps: 12, name: "dumbbell fly", load: "14.0 kg", restSec: 60, followAlongUrl: nil),
      .reps(
        sets: 3, reps: 12, name: "tricep pushdown", load: "25.0 kg", restSec: 60,
        followAlongUrl: nil),
      .reps(
        sets: 3, reps: 10, name: "skull crusher", load: "20.0 kg", restSec: 60, followAlongUrl: nil),
    ]
  }
}

extension VoiceWorkoutViewModel {
  fileprivate func seedWorkout(
    id: String = "voice-workout",
    name: String = "Voice Workout",
    sport: WorkoutSport = .strength,
    description: String? = "parsed from voice",
    intervals: [WorkoutInterval]
  ) {
    seedWorkoutForTesting(
      Workout(
        id: id,
        name: name,
        sport: sport,
        duration: 0,
        intervals: intervals,
        description: description,
        source: .ai
      )
    )
  }
}
