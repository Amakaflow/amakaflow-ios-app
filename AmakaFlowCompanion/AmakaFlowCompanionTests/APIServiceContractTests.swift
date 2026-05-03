//
//  APIServiceContractTests.swift
//  AmakaFlowCompanionTests
//
//  Decoder contract tests for workout-shaped API responses (AMA-1731).
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class APIServiceContractTests: XCTestCase {

  private let decoder = APIService.makeDecoder()

  func testCoachSuggestWorkoutResponseDecodesCanonicalWorkoutShape() throws {
    let response = try decodeFixture(
      "coach_suggest_workout_response",
      as: SuggestWorkoutResponse.self
    )

    XCTAssertEqual(response.name, "Upper Body Push - Hypertrophy Focus")
    XCTAssertEqual(response.sport, .strength)
    XCTAssertEqual(response.durationSeconds, 3300)
    XCTAssertEqual(response.blocks.count, 5)
    XCTAssertEqual(response.warmUp?.seconds, 600)
    XCTAssertEqual(response.warmUp?.target, "bench press warm-up sets at 40 kg")
    XCTAssertEqual(response.cooldown?.seconds, 300)
    XCTAssertEqual(response.cooldown?.target, "easy upper body mobility")

    let expectedBlocks: [(sets: Int, reps: Int, name: String, load: String, restSec: Int)] = [
      (4, 8, "bench press", "82.5 kg", 120),
      (3, 10, "incline bench press", "60.0 kg", 90),
      (3, 12, "dumbbell fly", "14.0 kg", 60),
      (3, 12, "tricep pushdown", "25.0 kg", 60),
      (3, 10, "skull crusher", "20.0 kg", 60),
    ]

    for (index, expected) in expectedBlocks.enumerated() {
      assertReps(
        response.blocks[index],
        sets: expected.sets,
        reps: expected.reps,
        name: expected.name,
        load: expected.load,
        restSec: expected.restSec
      )
    }
  }

  func testCoachMessageResponseDecodesWorkoutSuggestionMetadata() throws {
    let response = try decodeFixture("coach_message_response", as: CoachResponse.self)

    XCTAssertEqual(response.id, "coach-msg-1")
    XCTAssertEqual(response.message, "I built a push workout for today.")
    XCTAssertEqual(response.suggestions?.first?.id, "suggestion-1")
    XCTAssertEqual(response.suggestions?.first?.type, .workout)
    XCTAssertEqual(response.actionItems?.first?.actionType, "open_workout")
  }

  func testCoachMessageStreamFunctionResultDecodesGeneratedWorkoutPayload() throws {
    let envelope = try decodeFixture(
      "coach_message_stream_function_result_generated_workout",
      as: StreamFunctionResultEnvelope.self
    )

    XCTAssertEqual(envelope.toolUseId, "toolu_create_workout_1")
    XCTAssertEqual(envelope.name, "create_workout_plan")

    let resultData = try XCTUnwrap(envelope.result.data(using: .utf8))
    let workout = try decoder.decode(GeneratedWorkout.self, from: resultData)

    XCTAssertEqual(workout.name, "Upper Body Push")
    XCTAssertEqual(workout.duration, "55 min")
    XCTAssertEqual(workout.exercises.count, 2)
    XCTAssertEqual(workout.exercises[0].muscleGroup, "chest")
    XCTAssertEqual(workout.exercises[0].notes, "82.5 kg")
  }

  func testAPIWorkoutsIncomingResponseDecodesBlockWorkoutShape() throws {
    let workouts = try decodeFixture("api_workouts_incoming_response", as: [Workout].self)

    XCTAssertEqual(workouts.count, 1)
    let workout = try XCTUnwrap(workouts.first)
    XCTAssertEqual(workout.id, "workout-incoming-1")
    XCTAssertEqual(workout.name, "Incoming Strength Blocks")
    XCTAssertEqual(workout.sport, .strength)
    XCTAssertEqual(workout.source, .coach)
    XCTAssertEqual(workout.sourceUrl, "https://amakaflow.test/workouts/incoming-1")
    XCTAssertEqual(workout.blocks.count, 1)
    XCTAssertEqual(workout.blocks[0].restBetweenSeconds, 120)
    XCTAssertEqual(workout.blocks[0].exercises.count, 2)
    XCTAssertEqual(workout.blocks[0].exercises[0].canonicalName, "barbell bench press")
    XCTAssertEqual(workout.blocks[0].exercises[0].load, ExerciseLoad(value: 82.5, unit: "kg"))
    XCTAssertEqual(
      workout.intervals.first,
      .reps(
        sets: 4,
        reps: 8,
        name: "bench press",
        load: "82.5kg",
        restSec: 120,
        followAlongUrl: nil
      ))
  }

  func testAPIWorkoutsLegacyIntervalsResponseDecodesFallbackIntervalShape() throws {
    let workouts = try decodeFixture("api_workouts_legacy_intervals_response", as: [Workout].self)

    XCTAssertEqual(workouts.count, 1)
    let workout = try XCTUnwrap(workouts.first)
    XCTAssertEqual(workout.id, "workout-legacy-1")
    XCTAssertEqual(workout.sport, .other)
    XCTAssertEqual(workout.blocks.count, 5)
    XCTAssertEqual(workout.intervals.first, .warmup(seconds: 300, target: "easy ski"))
    XCTAssertTrue(workout.intervals.contains(.distance(meters: 1000, target: "run")))
    XCTAssertTrue(
      workout.intervals.contains(
        .repeat(
          reps: 2,
          intervals: [.time(seconds: 45, target: "wall balls")]
        )))
    XCTAssertFalse(workout.intervals.contains(.rest(seconds: 60)))
  }

  func testCalendarScheduledWorkoutsResponseDecodesFractionalDateAndIntervals() throws {
    let scheduled = try decodeFixture(
      "calendar_scheduled_workouts_response",
      as: [ScheduledWorkout].self
    )

    XCTAssertEqual(scheduled.count, 1)
    let item = try XCTUnwrap(scheduled.first)
    XCTAssertEqual(item.id, "scheduled-workout-1")
    XCTAssertEqual(item.scheduledTime, "09:30")
    XCTAssertTrue(item.isRecurring)
    XCTAssertEqual(item.recurrenceDays, [1, 3, 5])
    XCTAssertEqual(item.recurrenceWeeks, 4)
    XCTAssertFalse(item.syncedToApple)
    XCTAssertNotNil(item.scheduledDate)
    XCTAssertEqual(item.workout.sport, .running)
    XCTAssertEqual(
      item.workout.intervals,
      [
        .warmup(seconds: 600, target: "easy jog"),
        .time(seconds: 1200, target: "tempo pace"),
        .cooldown(seconds: 300, target: "easy jog"),
      ])
  }

  func testSyncPendingWorkoutsResponseDecodesWrappedWorkoutList() throws {
    let response = try decodeFixture(
      "sync_pending_workouts_response", as: PendingWorkoutsResponse.self)

    XCTAssertTrue(response.success)
    XCTAssertEqual(response.count, 1)
    let workout = try XCTUnwrap(response.workouts.first)
    XCTAssertEqual(workout.id, "pending-workout-1")
    XCTAssertEqual(workout.sport, .other)
    XCTAssertEqual(workout.blocks.count, 2)
    XCTAssertEqual(workout.blocks[0].label, "Bike")
    XCTAssertEqual(workout.blocks[0].exercises[0].durationSeconds, 1800)
    XCTAssertEqual(workout.blocks[1].exercises[0].distance, 5000.0)
  }

  private func decodeFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
      "Missing fixture: \(name).json"
    )
    let data = try Data(contentsOf: url)
    return try decoder.decode(T.self, from: data)
  }

  private func assertReps(
    _ interval: WorkoutInterval,
    sets: Int?,
    reps: Int,
    name: String,
    load: String?,
    restSec: Int?
  ) {
    guard case .reps(sets, reps, name, load, restSec, nil) = interval else {
      XCTFail("Expected reps interval, got \(interval)")
      return
    }
  }
}

private struct StreamFunctionResultEnvelope: Decodable {
  let toolUseId: String
  let name: String
  let result: String
}
