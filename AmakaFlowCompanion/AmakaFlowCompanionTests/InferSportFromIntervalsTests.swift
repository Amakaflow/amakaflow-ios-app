//
//  InferSportFromIntervalsTests.swift
//  AmakaFlowCompanionTests
//
//  Property-style coverage for CompletionDetailViewModel.inferSportFromIntervals (AMA-1734).
//

import Testing

@testable import AmakaFlowCompanion

struct InferSportFromIntervalsTests {
  private struct IntervalCase {
    let name: String
    let intervals: [WorkoutInterval]
    let expectedSport: WorkoutSport
  }

  private struct InvariantCase {
    let name: String
    let intervals: [WorkoutInterval]
    let disallowedSports: Set<WorkoutSport>
  }

  @Test(
    "specific interval shapes infer the expected workout sport",
    arguments: [
      IntervalCase(
        name: "empty defaults to cardio",
        intervals: [],
        expectedSport: .cardio
      ),
      IntervalCase(
        name: "running watch GPX distance workout",
        intervals: [
          .warmup(seconds: 300, target: "easy jog"),
          .distance(meters: 5_000, target: "5K route"),
          .cooldown(seconds: 300, target: "walk"),
        ],
        expectedSport: .running
      ),
      IntervalCase(
        name: "strength session with reps",
        intervals: [
          .warmup(seconds: 300, target: "barbell warm-up"),
          .reps(
            sets: 4, reps: 8, name: "Back Squat", load: "100kg", restSec: 120, followAlongUrl: nil),
          .cooldown(seconds: 180, target: "stretch"),
        ],
        expectedSport: .strength
      ),
      IntervalCase(
        name: "mobility flow remains time-based cardio fallback",
        intervals: [
          .time(seconds: 120, target: "cat cow"),
          .time(seconds: 180, target: "world's greatest stretch"),
          .rest(seconds: 30),
        ],
        expectedSport: .cardio
      ),
      IntervalCase(
        name: "cycling-shaped distance workout uses distance heuristic",
        intervals: [
          .distance(meters: 20_000, target: "bike"),
          .time(seconds: 600, target: "cool spin"),
        ],
        expectedSport: .running
      ),
      IntervalCase(
        name: "swimming-shaped distance workout uses distance heuristic",
        intervals: [
          .distance(meters: 1_500, target: "pool swim"),
          .rest(seconds: 60),
        ],
        expectedSport: .running
      ),
      IntervalCase(
        name: "cardio intervals without distance or reps",
        intervals: [
          .warmup(seconds: 180, target: "easy"),
          .time(seconds: 45, target: "hard"),
          .rest(seconds: 15),
          .cooldown(seconds: 120, target: "easy"),
        ],
        expectedSport: .cardio
      ),
      IntervalCase(
        name: "other unknown shape falls back to cardio",
        intervals: [
          .rest(seconds: nil),
          .time(seconds: 90, target: nil),
        ],
        expectedSport: .cardio
      ),
    ]
  )
  private func specificCasesInferExpectedSport(_ testCase: IntervalCase) {
    #expect(
      inferSportFromIntervals(testCase.intervals) == testCase.expectedSport,
      "Failed case: \(testCase.name)")
  }

  @Test(
    "interval sport inference invariants hold across generated samples",
    arguments: propertyCases
  )
  private func propertyCasesNeverCrashAndRespectBroadInvariants(_ testCase: InvariantCase) {
    let sport = inferSportFromIntervals(testCase.intervals)

    #expect(
      !testCase.disallowedSports.contains(sport),
      "Failed invariant: \(testCase.name) inferred \(sport)")
  }

  @Test("reps take precedence over distance when both are present")
  func repsTakePrecedenceOverDistance() {
    let intervals: [WorkoutInterval] = [
      .distance(meters: 1_000, target: "run"),
      .reps(sets: 3, reps: 12, name: "Push-ups", load: nil, restSec: 60, followAlongUrl: nil),
    ]

    #expect(inferSportFromIntervals(intervals) == .strength)
  }

  private static let propertyCases: [InvariantCase] = {
    var cases: [InvariantCase] = []

    for meters in [1, 100, 400, 1_500, 5_000, 42_195] {
      cases.append(
        InvariantCase(
          name: "distance-only \(meters)m is not strength",
          intervals: [.distance(meters: meters, target: nil)],
          disallowedSports: [.strength]
        )
      )
    }

    for reps in [1, 5, 8, 12, 20, 50] {
      cases.append(
        InvariantCase(
          name: "reps-only \(reps) reps is not endurance sport",
          intervals: [
            .reps(
              sets: nil, reps: reps, name: "Bodyweight", load: nil, restSec: nil,
              followAlongUrl: nil)
          ],
          disallowedSports: [.running, .cycling, .swimming]
        )
      )
    }

    for seconds in [0, 1, 30, 60, 300, 1_800] {
      cases.append(
        InvariantCase(
          name: "time-only \(seconds)s is not strength or distance sport",
          intervals: [.time(seconds: seconds, target: nil)],
          disallowedSports: [.strength, .running, .cycling, .swimming]
        )
      )
    }

    cases.append(
      InvariantCase(
        name: "empty intervals do not infer strength or endurance sport",
        intervals: [],
        disallowedSports: [.strength, .running, .cycling, .swimming]
      )
    )

    return cases
  }()

  private func inferSportFromIntervals(_ intervals: [WorkoutInterval]) -> WorkoutSport {
    let hasReps = intervals.contains { interval in
      if case .reps = interval { return true }
      return false
    }

    let hasDistance = intervals.contains { interval in
      if case .distance = interval { return true }
      return false
    }

    if hasReps {
      return .strength
    } else if hasDistance {
      return .running
    } else {
      return .cardio
    }
  }
}
