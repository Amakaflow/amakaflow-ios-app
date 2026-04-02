//
//  BlockToIntervalConverterTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for BlockToIntervalConverter
//

import XCTest
@testable import AmakaFlowCompanion

final class BlockToIntervalConverterTests: XCTestCase {

    // MARK: - Straight block produces sequential intervals with rest between exercises

    func testStraightBlockProducesSequentialIntervalsWithRestBetween() {
        let block = Block(
            label: "Main",
            structure: .straight,
            rounds: 1,
            exercises: [
                Exercise(name: "Squat", canonicalName: nil, sets: 3, reps: "10",
                         durationSeconds: nil, load: nil, restSeconds: 60,
                         distance: nil, notes: nil, supersetGroup: nil),
                Exercise(name: "Bench Press", canonicalName: nil, sets: 3, reps: "8",
                         durationSeconds: nil, load: nil, restSeconds: 90,
                         distance: nil, notes: nil, supersetGroup: nil),
                Exercise(name: "Row", canonicalName: nil, sets: 3, reps: "10",
                         durationSeconds: nil, load: nil, restSeconds: 60,
                         distance: nil, notes: nil, supersetGroup: nil)
            ]
        )

        let intervals = BlockToIntervalConverter.flatten([block])

        // 3 exercises with rest between first two = 5 intervals total
        // [Squat, rest(60), Bench Press, rest(90), Row]
        XCTAssertEqual(intervals.count, 5)

        // First interval: Squat reps
        if case .reps(let sets, let reps, let name, _, _, _) = intervals[0] {
            XCTAssertEqual(sets, 3)
            XCTAssertEqual(reps, 10)
            XCTAssertEqual(name, "Squat")
        } else {
            XCTFail("Expected reps interval for Squat, got \(intervals[0])")
        }

        // Second interval: rest between Squat and Bench Press
        if case .rest(let seconds) = intervals[1] {
            XCTAssertEqual(seconds, 60)
        } else {
            XCTFail("Expected rest interval after Squat, got \(intervals[1])")
        }

        // Third interval: Bench Press reps
        if case .reps(_, _, let name, _, _, _) = intervals[2] {
            XCTAssertEqual(name, "Bench Press")
        } else {
            XCTFail("Expected reps interval for Bench Press, got \(intervals[2])")
        }

        // Fourth interval: rest between Bench Press and Row
        if case .rest(let seconds) = intervals[3] {
            XCTAssertEqual(seconds, 90)
        } else {
            XCTFail("Expected rest interval after Bench Press, got \(intervals[3])")
        }

        // Fifth interval: Row reps (no rest after last exercise)
        if case .reps(_, _, let name, _, _, _) = intervals[4] {
            XCTAssertEqual(name, "Row")
        } else {
            XCTFail("Expected reps interval for Row, got \(intervals[4])")
        }
    }

    // MARK: - Timed exercise in cooldown block produces .cooldown interval

    func testTimedExerciseInCooldownBlockProducesCooldownInterval() {
        let block = Block(
            label: "Cool Down",
            structure: .straight,
            rounds: 1,
            exercises: [
                Exercise(name: "Stretch", canonicalName: nil, sets: nil, reps: nil,
                         durationSeconds: 300, load: nil, restSeconds: nil,
                         distance: nil, notes: "Easy stretch", supersetGroup: nil)
            ]
        )

        let intervals = BlockToIntervalConverter.flatten([block])

        XCTAssertEqual(intervals.count, 1)

        if case .cooldown(let seconds, let target) = intervals[0] {
            XCTAssertEqual(seconds, 300)
            XCTAssertEqual(target, "Easy stretch")
        } else {
            XCTFail("Expected cooldown interval, got \(intervals[0])")
        }
    }

    // MARK: - Circuit with rounds > 1 wraps in .repeat

    func testCircuitWithMultipleRoundsWrapsInRepeat() {
        let block = Block(
            label: "Circuit",
            structure: .circuit,
            rounds: 3,
            exercises: [
                Exercise(name: "Burpees", canonicalName: nil, sets: nil, reps: "10",
                         durationSeconds: nil, load: nil, restSeconds: nil,
                         distance: nil, notes: nil, supersetGroup: nil),
                Exercise(name: "Mountain Climbers", canonicalName: nil, sets: nil, reps: "20",
                         durationSeconds: nil, load: nil, restSeconds: nil,
                         distance: nil, notes: nil, supersetGroup: nil)
            ]
        )

        let intervals = BlockToIntervalConverter.flatten([block])

        XCTAssertEqual(intervals.count, 1, "Circuit with rounds > 1 should produce a single .repeat interval")

        if case .repeat(let reps, let innerIntervals) = intervals[0] {
            XCTAssertEqual(reps, 3)
            // 2 exercises + 1 rest between them = 3 inner intervals
            XCTAssertEqual(innerIntervals.count, 3)

            if case .reps(_, let r, let name, _, _, _) = innerIntervals[0] {
                XCTAssertEqual(name, "Burpees")
                XCTAssertEqual(r, 10)
            } else {
                XCTFail("Expected reps interval for Burpees")
            }

            if case .rest = innerIntervals[1] {
                // rest between exercises — OK
            } else {
                XCTFail("Expected rest between circuit exercises")
            }

            if case .reps(_, let r, let name, _, _, _) = innerIntervals[2] {
                XCTAssertEqual(name, "Mountain Climbers")
                XCTAssertEqual(r, 20)
            } else {
                XCTFail("Expected reps interval for Mountain Climbers")
            }
        } else {
            XCTFail("Expected .repeat interval, got \(intervals[0])")
        }
    }

    // MARK: - Empty blocks produces empty intervals

    func testEmptyBlocksProducesEmptyIntervals() {
        let intervals = BlockToIntervalConverter.flatten([])
        XCTAssertTrue(intervals.isEmpty, "Flattening empty blocks should produce empty intervals")
    }

    func testBlockWithNoExercisesProducesEmptyIntervals() {
        let block = Block(
            label: "Empty",
            structure: .straight,
            rounds: 1,
            exercises: []
        )

        let intervals = BlockToIntervalConverter.flatten([block])
        XCTAssertTrue(intervals.isEmpty)
    }

    // MARK: - Reps range "8-12" uses higher end (12)

    func testRepsRangeUsesHigherEnd() {
        let block = Block(
            label: "Main",
            structure: .straight,
            rounds: 1,
            exercises: [
                Exercise(name: "Squat", canonicalName: nil, sets: 3, reps: "8-12",
                         durationSeconds: nil, load: nil, restSeconds: nil,
                         distance: nil, notes: nil, supersetGroup: nil)
            ]
        )

        let intervals = BlockToIntervalConverter.flatten([block])

        XCTAssertEqual(intervals.count, 1)

        if case .reps(let sets, let reps, let name, _, _, _) = intervals[0] {
            XCTAssertEqual(name, "Squat")
            XCTAssertEqual(sets, 3)
            XCTAssertEqual(reps, 12, "Range '8-12' should use higher end: 12")
        } else {
            XCTFail("Expected reps interval, got \(intervals[0])")
        }
    }

    // MARK: - parseReps edge cases

    func testParseRepsPlainNumber() {
        XCTAssertEqual(BlockToIntervalConverter.parseReps("10"), 10)
    }

    func testParseRepsNil() {
        XCTAssertEqual(BlockToIntervalConverter.parseReps(nil), 0)
    }

    func testParseRepsEmpty() {
        XCTAssertEqual(BlockToIntervalConverter.parseReps(""), 0)
    }
}
