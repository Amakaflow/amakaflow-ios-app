//
//  WorkoutModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for Workout data models and encoding/decoding
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutModelTests: XCTestCase {

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    override func setUp() {
        encoder.outputFormatting = .sortedKeys
    }

    // MARK: - WorkoutInterval Encoding/Decoding Tests

    func testWarmupIntervalEncodeDecode() throws {
        let interval = WorkoutInterval.warmup(seconds: 300, target: "Easy pace")

        let data = try encoder.encode(interval)
        let decoded = try decoder.decode(WorkoutInterval.self, from: data)

        if case .warmup(let seconds, let target) = decoded {
            XCTAssertEqual(seconds, 300)
            XCTAssertEqual(target, "Easy pace")
        } else {
            XCTFail("Expected warmup interval")
        }
    }

    func testWarmupIntervalWithNilTarget() throws {
        let interval = WorkoutInterval.warmup(seconds: 60, target: nil)

        let data = try encoder.encode(interval)
        let decoded = try decoder.decode(WorkoutInterval.self, from: data)

        if case .warmup(let seconds, let target) = decoded {
            XCTAssertEqual(seconds, 60)
            XCTAssertNil(target)
        } else {
            XCTFail("Expected warmup interval")
        }
    }

    func testCooldownIntervalEncodeDecode() throws {
        let interval = WorkoutInterval.cooldown(seconds: 180, target: "Stretch")

        let data = try encoder.encode(interval)
        let decoded = try decoder.decode(WorkoutInterval.self, from: data)

        if case .cooldown(let seconds, let target) = decoded {
            XCTAssertEqual(seconds, 180)
            XCTAssertEqual(target, "Stretch")
        } else {
            XCTFail("Expected cooldown interval")
        }
    }

    func testTimeIntervalEncodeDecode() throws {
        let interval = WorkoutInterval.time(seconds: 45, target: "Plank hold")

        let data = try encoder.encode(interval)
        let decoded = try decoder.decode(WorkoutInterval.self, from: data)

        if case .time(let seconds, let target) = decoded {
            XCTAssertEqual(seconds, 45)
            XCTAssertEqual(target, "Plank hold")
        } else {
            XCTFail("Expected time interval")
        }
    }

    func testRepsIntervalEncodeDecode() throws {
        let interval = WorkoutInterval.reps(
            reps: 15,
            name: "Push-ups",
            load: "Bodyweight",
            restSec: 30,
            followAlongUrl: "https://example.com/pushups"
        )

        let data = try encoder.encode(interval)
        let decoded = try decoder.decode(WorkoutInterval.self, from: data)

        if case .reps(let reps, let name, let load, let restSec, let followAlongUrl) = decoded {
            XCTAssertEqual(reps, 15)
            XCTAssertEqual(name, "Push-ups")
            XCTAssertEqual(load, "Bodyweight")
            XCTAssertEqual(restSec, 30)
            XCTAssertEqual(followAlongUrl, "https://example.com/pushups")
        } else {
            XCTFail("Expected reps interval")
        }
    }

    func testRepsIntervalWithOptionalNils() throws {
        let interval = WorkoutInterval.reps(
            reps: 10,
            name: "Squats",
            load: nil,
            restSec: nil,
            followAlongUrl: nil
        )

        let data = try encoder.encode(interval)
        let decoded = try decoder.decode(WorkoutInterval.self, from: data)

        if case .reps(let reps, let name, let load, let restSec, let followAlongUrl) = decoded {
            XCTAssertEqual(reps, 10)
            XCTAssertEqual(name, "Squats")
            XCTAssertNil(load)
            XCTAssertNil(restSec)
            XCTAssertNil(followAlongUrl)
        } else {
            XCTFail("Expected reps interval")
        }
    }

    func testDistanceIntervalEncodeDecode() throws {
        let interval = WorkoutInterval.distance(meters: 400, target: "Sprint pace")

        let data = try encoder.encode(interval)
        let decoded = try decoder.decode(WorkoutInterval.self, from: data)

        if case .distance(let meters, let target) = decoded {
            XCTAssertEqual(meters, 400)
            XCTAssertEqual(target, "Sprint pace")
        } else {
            XCTFail("Expected distance interval")
        }
    }

    func testRepeatIntervalEncodeDecode() throws {
        let interval = WorkoutInterval.repeat(
            reps: 3,
            intervals: [
                .reps(reps: 10, name: "Burpees", load: nil, restSec: nil, followAlongUrl: nil),
                .time(seconds: 60, target: "Rest")
            ]
        )

        let data = try encoder.encode(interval)
        let decoded = try decoder.decode(WorkoutInterval.self, from: data)

        if case .repeat(let reps, let intervals) = decoded {
            XCTAssertEqual(reps, 3)
            XCTAssertEqual(intervals.count, 2)

            // Check nested intervals
            if case .reps(let nestedReps, let name, _, _, _) = intervals[0] {
                XCTAssertEqual(nestedReps, 10)
                XCTAssertEqual(name, "Burpees")
            } else {
                XCTFail("Expected reps as first nested interval")
            }

            if case .time(let seconds, let target) = intervals[1] {
                XCTAssertEqual(seconds, 60)
                XCTAssertEqual(target, "Rest")
            } else {
                XCTFail("Expected time as second nested interval")
            }
        } else {
            XCTFail("Expected repeat interval")
        }
    }

    func testNestedRepeatIntervals() throws {
        // Test deeply nested repeat intervals
        let interval = WorkoutInterval.repeat(
            reps: 2,
            intervals: [
                .repeat(
                    reps: 3,
                    intervals: [
                        .reps(reps: 5, name: "Pull-ups", load: nil, restSec: nil, followAlongUrl: nil)
                    ]
                )
            ]
        )

        let data = try encoder.encode(interval)
        let decoded = try decoder.decode(WorkoutInterval.self, from: data)

        if case .repeat(let outerReps, let outerIntervals) = decoded {
            XCTAssertEqual(outerReps, 2)
            XCTAssertEqual(outerIntervals.count, 1)

            if case .repeat(let innerReps, let innerIntervals) = outerIntervals[0] {
                XCTAssertEqual(innerReps, 3)
                XCTAssertEqual(innerIntervals.count, 1)
            } else {
                XCTFail("Expected nested repeat interval")
            }
        } else {
            XCTFail("Expected outer repeat interval")
        }
    }

    func testInvalidIntervalKindThrows() {
        let json = """
        {"kind": "invalid_kind", "seconds": 30}
        """

        XCTAssertThrowsError(try decoder.decode(WorkoutInterval.self, from: json.data(using: .utf8)!))
    }

    // MARK: - Workout Model Tests

    func testWorkoutEncodeDecode() throws {
        let workout = Workout(
            id: "workout-123",
            name: "Morning HIIT",
            sport: .strength,
            duration: 1800,
            intervals: [
                .warmup(seconds: 300, target: "Light jog"),
                .repeat(reps: 4, intervals: [
                    .time(seconds: 30, target: "High intensity"),
                    .time(seconds: 30, target: "Rest")
                ]),
                .cooldown(seconds: 300, target: nil)
            ],
            description: "High intensity interval training",
            source: .coach,
            sourceUrl: "https://example.com/workout"
        )

        let data = try encoder.encode(workout)
        let decoded = try decoder.decode(Workout.self, from: data)

        XCTAssertEqual(decoded.id, "workout-123")
        XCTAssertEqual(decoded.name, "Morning HIIT")
        XCTAssertEqual(decoded.sport, .strength)
        XCTAssertEqual(decoded.duration, 1800)
        XCTAssertEqual(decoded.intervals.count, 3)
        XCTAssertEqual(decoded.description, "High intensity interval training")
        XCTAssertEqual(decoded.source, .coach)
        XCTAssertEqual(decoded.sourceUrl, "https://example.com/workout")
    }

    func testWorkoutWithMinimalFields() throws {
        let workout = Workout(
            id: "minimal-1",
            name: "Quick Workout",
            sport: .other,
            duration: 600,
            intervals: [.time(seconds: 600, target: nil)],
            description: nil,
            source: .ai,
            sourceUrl: nil
        )

        let data = try encoder.encode(workout)
        let decoded = try decoder.decode(Workout.self, from: data)

        XCTAssertEqual(decoded.id, "minimal-1")
        XCTAssertNil(decoded.description)
        XCTAssertNil(decoded.sourceUrl)
    }

    func testWorkoutHashable() {
        let workout1 = Workout(
            id: "same-id",
            name: "Workout A",
            sport: .running,
            duration: 1000,
            intervals: [],
            source: .instagram
        )

        let workout2 = Workout(
            id: "same-id",
            name: "Workout A",
            sport: .running,
            duration: 1000,
            intervals: [],
            source: .instagram
        )

        XCTAssertEqual(workout1.hashValue, workout2.hashValue)
    }

    // MARK: - WorkoutSport Tests

    func testAllWorkoutSportsEncodeDecode() throws {
        let sports: [WorkoutSport] = [.running, .cycling, .strength, .mobility, .swimming, .other]

        for sport in sports {
            let data = try encoder.encode(sport)
            let decoded = try decoder.decode(WorkoutSport.self, from: data)
            XCTAssertEqual(decoded, sport)
        }
    }

    // MARK: - WorkoutSource Tests

    func testAllWorkoutSourcesEncodeDecode() throws {
        let sources: [WorkoutSource] = [.instagram, .youtube, .image, .ai, .coach]

        for source in sources {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(WorkoutSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }

    // MARK: - ScheduledWorkout Tests

    func testScheduledWorkoutEncodeDecode() throws {
        let workout = Workout(
            id: "scheduled-1",
            name: "Evening Run",
            sport: .running,
            duration: 2400,
            intervals: [.time(seconds: 2400, target: "Zone 2")],
            source: .coach
        )

        let scheduledDate = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC

        let scheduled = ScheduledWorkout(
            workout: workout,
            scheduledDate: scheduledDate,
            scheduledTime: "18:00",
            isRecurring: true,
            recurrenceDays: [1, 3, 5], // Mon, Wed, Fri
            recurrenceWeeks: 4,
            syncedToApple: true
        )

        let data = try encoder.encode(scheduled)
        let decoded = try decoder.decode(ScheduledWorkout.self, from: data)

        XCTAssertEqual(decoded.id, "scheduled-1")
        XCTAssertEqual(decoded.workout.name, "Evening Run")
        XCTAssertEqual(decoded.scheduledTime, "18:00")
        XCTAssertTrue(decoded.isRecurring)
        XCTAssertEqual(decoded.recurrenceDays, [1, 3, 5])
        XCTAssertEqual(decoded.recurrenceWeeks, 4)
        XCTAssertTrue(decoded.syncedToApple)
    }

    func testScheduledWorkoutMinimalFields() throws {
        let workout = Workout(
            id: "minimal-scheduled",
            name: "Quick Session",
            sport: .strength,
            duration: 300,
            intervals: [],
            source: .ai
        )

        let scheduled = ScheduledWorkout(workout: workout)

        let data = try encoder.encode(scheduled)
        let decoded = try decoder.decode(ScheduledWorkout.self, from: data)

        XCTAssertEqual(decoded.id, "minimal-scheduled")
        XCTAssertNil(decoded.scheduledDate)
        XCTAssertNil(decoded.scheduledTime)
        XCTAssertFalse(decoded.isRecurring)
        XCTAssertNil(decoded.recurrenceDays)
        XCTAssertNil(decoded.recurrenceWeeks)
        XCTAssertFalse(decoded.syncedToApple)
    }

    // MARK: - WorkoutHelpers Tests

    func testFormatDurationMinutesOnly() {
        XCTAssertEqual(WorkoutHelpers.formatDuration(seconds: 1800), "30m")
        XCTAssertEqual(WorkoutHelpers.formatDuration(seconds: 60), "1m")
        XCTAssertEqual(WorkoutHelpers.formatDuration(seconds: 0), "0m")
    }

    func testFormatDurationWithHours() {
        XCTAssertEqual(WorkoutHelpers.formatDuration(seconds: 3600), "1h 0m")
        XCTAssertEqual(WorkoutHelpers.formatDuration(seconds: 5400), "1h 30m")
        XCTAssertEqual(WorkoutHelpers.formatDuration(seconds: 7200), "2h 0m")
    }

    func testCountIntervalsSimple() {
        let intervals: [WorkoutInterval] = [
            .warmup(seconds: 60, target: nil),
            .time(seconds: 120, target: nil),
            .cooldown(seconds: 60, target: nil)
        ]

        XCTAssertEqual(WorkoutHelpers.countIntervals(intervals), 3)
    }

    func testCountIntervalsWithRepeat() {
        let intervals: [WorkoutInterval] = [
            .warmup(seconds: 60, target: nil),
            .repeat(reps: 3, intervals: [
                .time(seconds: 30, target: nil),
                .time(seconds: 30, target: nil)
            ]),
            .cooldown(seconds: 60, target: nil)
        ]

        // 1 warmup + (3 * 2) repeat + 1 cooldown = 8
        XCTAssertEqual(WorkoutHelpers.countIntervals(intervals), 8)
    }

    func testCountIntervalsNestedRepeat() {
        let intervals: [WorkoutInterval] = [
            .repeat(reps: 2, intervals: [
                .repeat(reps: 3, intervals: [
                    .reps(reps: 10, name: "Exercise", load: nil, restSec: nil, followAlongUrl: nil)
                ])
            ])
        ]

        // 2 * (3 * 1) = 6
        XCTAssertEqual(WorkoutHelpers.countIntervals(intervals), 6)
    }

    func testCountIntervalsEmpty() {
        XCTAssertEqual(WorkoutHelpers.countIntervals([]), 0)
    }

    func testFormatDistanceMeters() {
        XCTAssertEqual(WorkoutHelpers.formatDistance(meters: 100), "100m")
        XCTAssertEqual(WorkoutHelpers.formatDistance(meters: 400), "400m")
        XCTAssertEqual(WorkoutHelpers.formatDistance(meters: 999), "999m")
    }

    func testFormatDistanceKilometers() {
        XCTAssertEqual(WorkoutHelpers.formatDistance(meters: 1000), "1.0 km")
        XCTAssertEqual(WorkoutHelpers.formatDistance(meters: 1500), "1.5 km")
        XCTAssertEqual(WorkoutHelpers.formatDistance(meters: 5000), "5.0 km")
        XCTAssertEqual(WorkoutHelpers.formatDistance(meters: 10000), "10.0 km")
    }

    // MARK: - Workout Computed Properties Tests

    func testWorkoutFormattedDuration() {
        let workout = Workout(
            id: "test",
            name: "Test",
            sport: .strength,
            duration: 2700, // 45 minutes
            intervals: [],
            source: .coach
        )

        XCTAssertEqual(workout.formattedDuration, "45m")
    }

    func testWorkoutIntervalCount() {
        let workout = Workout(
            id: "test",
            name: "Test",
            sport: .strength,
            duration: 1000,
            intervals: [
                .warmup(seconds: 60, target: nil),
                .repeat(reps: 4, intervals: [
                    .reps(reps: 10, name: "Ex", load: nil, restSec: nil, followAlongUrl: nil)
                ]),
                .cooldown(seconds: 60, target: nil)
            ],
            source: .coach
        )

        // 1 + 4 + 1 = 6
        XCTAssertEqual(workout.intervalCount, 6)
    }

    // MARK: - JSON Format Compatibility Tests

    func testDecodeFromExternalJSON() throws {
        // Test decoding from JSON format that matches TypeScript implementation
        let json = """
        {
            "id": "external-1",
            "name": "External Workout",
            "sport": "strength",
            "duration": 1200,
            "intervals": [
                {"kind": "warmup", "seconds": 120, "target": "Light movement"},
                {"kind": "reps", "reps": 12, "name": "Kettlebell swings", "load": "16kg"},
                {"kind": "time", "seconds": 60, "target": "Rest"},
                {"kind": "cooldown", "seconds": 120}
            ],
            "description": "Full body workout",
            "source": "youtube",
            "sourceUrl": "https://youtube.com/watch?v=abc123"
        }
        """

        let workout = try decoder.decode(Workout.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(workout.id, "external-1")
        XCTAssertEqual(workout.name, "External Workout")
        XCTAssertEqual(workout.sport, .strength)
        XCTAssertEqual(workout.intervals.count, 4)
        XCTAssertEqual(workout.source, .youtube)
    }

    func testIntervalHashable() {
        let interval1 = WorkoutInterval.time(seconds: 60, target: "Work")
        let interval2 = WorkoutInterval.time(seconds: 60, target: "Work")
        let interval3 = WorkoutInterval.time(seconds: 30, target: "Work")

        XCTAssertEqual(interval1.hashValue, interval2.hashValue)
        XCTAssertNotEqual(interval1.hashValue, interval3.hashValue)
    }
}
