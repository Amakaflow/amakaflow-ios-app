//
//  WorkoutCodableTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for Workout Codable (blocks format, legacy intervals, preference logic)
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutCodableTests: XCTestCase {

    // MARK: - Decode workout with blocks format

    func testDecodeWorkoutWithBlocksFormat() throws {
        let json = """
        {
            "id": "w-123",
            "name": "Full Body",
            "sport": "strength",
            "duration": 2700,
            "blocks": [{
                "label": "Main",
                "structure": "straight",
                "rounds": 1,
                "exercises": [{"name": "Squat", "sets": 3, "reps": "10"}]
            }]
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let workout = try decoder.decode(Workout.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(workout.id, "w-123")
        XCTAssertEqual(workout.name, "Full Body")
        XCTAssertEqual(workout.sport, .strength)
        XCTAssertEqual(workout.duration, 2700)

        // Blocks present
        XCTAssertEqual(workout.blocks.count, 1)
        XCTAssertEqual(workout.blocks[0].label, "Main")
        XCTAssertEqual(workout.blocks[0].structure, .straight)
        XCTAssertEqual(workout.blocks[0].rounds, 1)

        // Exercises accessible
        XCTAssertEqual(workout.blocks[0].exercises.count, 1)
        XCTAssertEqual(workout.blocks[0].exercises[0].name, "Squat")
        XCTAssertEqual(workout.blocks[0].exercises[0].sets, 3)
        XCTAssertEqual(workout.blocks[0].exercises[0].reps, "10")

        // Computed intervals work
        let intervals = workout.intervals
        XCTAssertFalse(intervals.isEmpty, "Computed intervals should be non-empty for blocks with exercises")

        if case .reps(let sets, let reps, let name, _, _, _) = intervals[0] {
            XCTAssertEqual(name, "Squat")
            XCTAssertEqual(sets, 3)
            XCTAssertEqual(reps, 10)
        } else {
            XCTFail("Expected reps interval from computed intervals")
        }
    }

    // MARK: - Decode workout with legacy intervals format

    func testDecodeWorkoutWithLegacyIntervalsFormat() throws {
        let json = """
        {
            "id": "w-legacy",
            "name": "Old Workout",
            "sport": "strength",
            "duration": 1800,
            "intervals": [
                {"kind": "reps", "sets": 3, "reps": 10, "name": "Push-up"},
                {"kind": "rest", "seconds": 60}
            ]
        }
        """

        let decoder = JSONDecoder()
        let workout = try decoder.decode(Workout.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(workout.id, "w-legacy")
        XCTAssertEqual(workout.name, "Old Workout")
        XCTAssertEqual(workout.duration, 1800)

        // Legacy intervals should be wrapped in a single block.
        // .rest intervals are skipped — rest is structural, not an exercise.
        XCTAssertEqual(workout.blocks.count, 1, "Legacy intervals should be wrapped in one block")
        XCTAssertEqual(workout.blocks[0].structure, .straight)
        XCTAssertEqual(workout.blocks[0].exercises.count, 1, "Only non-rest intervals become exercises")

        // First exercise: Push-up
        XCTAssertEqual(workout.blocks[0].exercises[0].name, "Push-up")
        XCTAssertEqual(workout.blocks[0].exercises[0].sets, 3)
        XCTAssertEqual(workout.blocks[0].exercises[0].reps, "10")
    }

    // MARK: - Decode workout with both blocks and intervals — prefers blocks

    func testDecodeWorkoutWithBothBlocksAndIntervals_PrefersBlocks() throws {
        let json = """
        {
            "id": "w-both",
            "name": "Both Formats",
            "sport": "strength",
            "duration": 1800,
            "blocks": [{
                "label": "Block Path",
                "structure": "straight",
                "rounds": 1,
                "exercises": [{"name": "Deadlift", "sets": 5, "reps": "5"}]
            }],
            "intervals": [
                {"kind": "reps", "sets": 3, "reps": 10, "name": "Legacy Exercise"}
            ]
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let workout = try decoder.decode(Workout.self, from: json.data(using: .utf8)!)

        // Should prefer blocks over intervals
        XCTAssertEqual(workout.blocks.count, 1)
        XCTAssertEqual(workout.blocks[0].label, "Block Path", "Should use blocks path, not legacy intervals")
        XCTAssertEqual(workout.blocks[0].exercises[0].name, "Deadlift")
        XCTAssertEqual(workout.blocks[0].exercises[0].sets, 5)

        // Computed intervals should come from blocks (Deadlift), not the legacy "Legacy Exercise"
        let intervals = workout.intervals
        XCTAssertFalse(intervals.isEmpty)

        if case .reps(_, _, let name, _, _, _) = intervals[0] {
            XCTAssertEqual(name, "Deadlift", "Computed intervals should come from blocks, not legacy intervals")
        } else {
            XCTFail("Expected reps interval from blocks path")
        }
    }

    // MARK: - Edge: no blocks and no intervals

    func testDecodeWorkoutWithNoBlocksAndNoIntervals() throws {
        let json = """
        {
            "id": "w-empty",
            "name": "Empty Workout",
            "sport": "other",
            "duration": 0
        }
        """

        let decoder = JSONDecoder()
        let workout = try decoder.decode(Workout.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(workout.blocks.count, 0)
        XCTAssertTrue(workout.intervals.isEmpty)
    }
}
