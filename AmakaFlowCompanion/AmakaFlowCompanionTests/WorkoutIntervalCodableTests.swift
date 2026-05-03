//
//  WorkoutIntervalCodableTests.swift
//  AmakaFlowCompanionTests
//
//  Locks WorkoutInterval encoder/decoder symmetry so backend/iOS schema drift fails locally.
//

import XCTest

@testable import AmakaFlowCompanion

final class WorkoutIntervalCodableTests: XCTestCase {
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private let decoder = JSONDecoder()

  // MARK: - Per-case round trips

  func testWarmupIntervalRoundTrips() throws {
    try assertRoundTrip(
      .warmup(seconds: 600, target: "Raise core temperature"),
      expectedKind: "warmup",
      expectedFields: ["kind", "seconds", "target"]
    )
  }

  func testCooldownIntervalRoundTrips() throws {
    try assertRoundTrip(
      .cooldown(seconds: 300, target: "Easy walk and nasal breathing"),
      expectedKind: "cooldown",
      expectedFields: ["kind", "seconds", "target"]
    )
  }

  func testTimeIntervalRoundTrips() throws {
    try assertRoundTrip(
      .time(seconds: 45, target: "Hollow hold"),
      expectedKind: "time",
      expectedFields: ["kind", "seconds", "target"]
    )
  }

  func testRepsIntervalRoundTrips() throws {
    try assertRoundTrip(
      .reps(
        sets: 4,
        reps: 8,
        name: "bench press",
        load: "82.5 kg",
        restSec: 120,
        followAlongUrl: "https://example.com/bench-press"
      ),
      expectedKind: "reps",
      expectedFields: [
        "followAlongUrl", "kind", "load", "name", "reps", "restSec", "sets",
      ]
    )
  }

  func testDistanceIntervalRoundTrips() throws {
    try assertRoundTrip(
      .distance(meters: 1000, target: "Zone 2"),
      expectedKind: "distance",
      expectedFields: ["kind", "meters", "target"]
    )
  }

  func testRepeatIntervalRoundTrips() throws {
    try assertRoundTrip(
      .repeat(
        reps: 3,
        intervals: [
          .time(seconds: 60, target: "Hard effort"),
          .rest(seconds: 30),
        ]
      ),
      expectedKind: "repeat",
      expectedFields: ["intervals", "kind", "reps"]
    )
  }

  func testRestIntervalRoundTrips() throws {
    try assertRoundTrip(
      .rest(seconds: 90),
      expectedKind: "rest",
      expectedFields: ["kind", "seconds"]
    )
  }

  // MARK: - AMA-1720 fixture shape

  func testCanonicalSuggestedWorkoutIntervalsDecodeWithExpectedKindsAndFields() throws {
    let json = """
      [
          {
              "kind": "warmup",
              "seconds": 600,
              "target": "bench press warm-up sets at 40 kg"
          },
          {
              "kind": "reps",
              "sets": 4,
              "reps": 8,
              "name": "bench press",
              "load": "82.5 kg",
              "restSec": 120
          },
          {
              "kind": "reps",
              "sets": 3,
              "reps": 10,
              "name": "incline bench press",
              "load": "60 kg",
              "restSec": 90
          },
          {
              "kind": "reps",
              "sets": 3,
              "reps": 12,
              "name": "dumbbell fly",
              "load": "14 kg",
              "restSec": 60
          },
          {
              "kind": "reps",
              "sets": 3,
              "reps": 12,
              "name": "tricep pushdown",
              "load": "25 kg",
              "restSec": 60
          },
          {
              "kind": "reps",
              "sets": 3,
              "reps": 10,
              "name": "skull crusher",
              "load": "20 kg",
              "restSec": 60
          }
      ]
      """

    let data = try XCTUnwrap(json.data(using: .utf8))
    let rawIntervals = try decodeJSONArray(data)
    let intervals = try decoder.decode([WorkoutInterval].self, from: data)

    XCTAssertEqual(intervals.count, 6)
    XCTAssertEqual(
      rawIntervals.map { $0["kind"] as? String },
      ["warmup", "reps", "reps", "reps", "reps", "reps"])

    XCTAssertEqual(Set(rawIntervals[0].keys), ["kind", "seconds", "target"])
    assertWarmup(intervals[0], seconds: 600, target: "bench press warm-up sets at 40 kg")

    let expectedExercises: [(sets: Int, reps: Int, name: String, load: String, restSec: Int)] = [
      (4, 8, "bench press", "82.5 kg", 120),
      (3, 10, "incline bench press", "60 kg", 90),
      (3, 12, "dumbbell fly", "14 kg", 60),
      (3, 12, "tricep pushdown", "25 kg", 60),
      (3, 10, "skull crusher", "20 kg", 60),
    ]

    for (index, expected) in expectedExercises.enumerated() {
      let intervalIndex = index + 1
      XCTAssertEqual(
        Set(rawIntervals[intervalIndex].keys),
        ["kind", "sets", "reps", "name", "load", "restSec"])
      assertReps(
        intervals[intervalIndex],
        sets: expected.sets,
        reps: expected.reps,
        name: expected.name,
        load: expected.load,
        restSec: expected.restSec
      )
    }
  }

  // MARK: - Helpers

  private func assertRoundTrip(
    _ interval: WorkoutInterval,
    expectedKind: String,
    expectedFields: Set<String>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let data = try encoder.encode(interval)
    let raw = try decodeJSONObject(data)
    let decoded = try decoder.decode(WorkoutInterval.self, from: data)

    XCTAssertEqual(decoded, interval, file: file, line: line)
    XCTAssertEqual(raw["kind"] as? String, expectedKind, file: file, line: line)
    XCTAssertEqual(Set(raw.keys), expectedFields, file: file, line: line)
  }

  private func decodeJSONObject(_ data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
  }

  private func decodeJSONArray(_ data: Data) throws -> [[String: Any]] {
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [[String: Any]])
  }

  private func assertWarmup(
    _ interval: WorkoutInterval,
    seconds: Int,
    target: String?,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard case .warmup(let actualSeconds, let actualTarget) = interval else {
      return XCTFail("Expected warmup interval", file: file, line: line)
    }

    XCTAssertEqual(actualSeconds, seconds, file: file, line: line)
    XCTAssertEqual(actualTarget, target, file: file, line: line)
  }

  private func assertReps(
    _ interval: WorkoutInterval,
    sets: Int?,
    reps: Int,
    name: String,
    load: String?,
    restSec: Int?,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard
      case .reps(
        let actualSets, let actualReps, let actualName, let actualLoad, let actualRestSec,
        let followAlongUrl) = interval
    else {
      return XCTFail("Expected reps interval", file: file, line: line)
    }

    XCTAssertEqual(actualSets, sets, file: file, line: line)
    XCTAssertEqual(actualReps, reps, file: file, line: line)
    XCTAssertEqual(actualName, name, file: file, line: line)
    XCTAssertEqual(actualLoad, load, file: file, line: line)
    XCTAssertEqual(actualRestSec, restSec, file: file, line: line)
    XCTAssertNil(followAlongUrl, file: file, line: line)
  }
}
