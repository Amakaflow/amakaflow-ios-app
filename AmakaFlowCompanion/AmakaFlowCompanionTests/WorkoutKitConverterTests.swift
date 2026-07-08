//
//  WorkoutKitConverterTests.swift
//  AmakaFlowCompanionTests
//
//  Golden tests for WorkoutKitConverter sport-type mapping and conversion smoke tests (issue #434, slice 4).
//
//  Note: WKPlanDTO property assertions require WorkoutKitSync linked to the test target.
//  Current coverage: all 7 sport-type string mappings + no-throw smoke tests for each interval kind.
//

import XCTest
@testable import AmakaFlowCompanion

@available(iOS 18.0, *)
final class WorkoutKitConverterTests: XCTestCase {

    private var converter: WorkoutKitConverter { WorkoutKitConverter.shared }

    // MARK: - Sport type mapping (golden)

    func testRunningMapsToRunning() {
        XCTAssertEqual(converter.mapSportType(.running), "running")
    }

    func testCyclingMapsToCycling() {
        XCTAssertEqual(converter.mapSportType(.cycling), "cycling")
    }

    func testStrengthMapsToStrengthTraining() {
        XCTAssertEqual(converter.mapSportType(.strength), "strengthTraining")
    }

    func testMobilityMapsToOther() {
        XCTAssertEqual(converter.mapSportType(.mobility), "other")
    }

    func testSwimmingMapsToSwimming() {
        XCTAssertEqual(converter.mapSportType(.swimming), "swimming")
    }

    func testCardioMapsToMixedCardio() {
        XCTAssertEqual(converter.mapSportType(.cardio), "mixedCardio")
    }

    func testOtherMapsToOther() {
        XCTAssertEqual(converter.mapSportType(.other), "other")
    }

    // MARK: - convertToWKPlanDTO smoke tests (no-throw verification)

    func testRunningWorkoutWithTimedIntervalsConvertsWithoutThrowing() throws {
        let workout = Workout(
            name: "Threshold Run",
            sport: .running,
            duration: 3600,
            intervals: [
                .warmup(seconds: 300, target: nil),
                .time(seconds: 1800, target: "Zone 3"),
                .cooldown(seconds: 300, target: nil)
            ],
            source: .coach
        )
        XCTAssertNoThrow(try converter.convertToWKPlanDTO(workout))
    }

    func testStrengthWorkoutWithRepIntervalsConvertsWithoutThrowing() throws {
        let workout = Workout(
            name: "Push Day",
            sport: .strength,
            duration: 2700,
            intervals: [
                .reps(sets: 3, reps: 10, name: "Bench Press", load: nil, restSec: 60, followAlongUrl: nil),
                .reps(sets: 3, reps: 12, name: "Dumbbell Row", load: nil, restSec: 60, followAlongUrl: nil)
            ],
            source: .coach
        )
        XCTAssertNoThrow(try converter.convertToWKPlanDTO(workout))
    }

    func testCyclingWorkoutWithDistanceIntervalConvertsWithoutThrowing() throws {
        let workout = Workout(
            name: "Easy Ride",
            sport: .cycling,
            duration: 5400,
            intervals: [
                .warmup(seconds: 600, target: nil),
                .distance(meters: 20_000, target: nil),
                .cooldown(seconds: 600, target: nil)
            ],
            source: .coach
        )
        XCTAssertNoThrow(try converter.convertToWKPlanDTO(workout))
    }

    func testRepeatSetIntervalConvertsWithoutThrowing() throws {
        let workout = Workout(
            name: "Circuit",
            sport: .cardio,
            duration: 1800,
            intervals: [
                .repeat(reps: 3, intervals: [
                    .time(seconds: 40, target: nil),
                    .rest(seconds: 20)
                ])
            ],
            source: .coach
        )
        XCTAssertNoThrow(try converter.convertToWKPlanDTO(workout))
    }

    func testEmptyWorkoutConvertsWithoutThrowing() throws {
        let workout = Workout(
            name: "Rest Day",
            sport: .other,
            duration: 0,
            intervals: [],
            source: .other
        )
        XCTAssertNoThrow(try converter.convertToWKPlanDTO(workout))
    }

    func testRestIntervalConvertsWithoutThrowing() throws {
        let workout = Workout(
            name: "Recovery",
            sport: .mobility,
            duration: 1200,
            intervals: [
                .rest(seconds: 120),
                .rest(seconds: nil)
            ],
            source: .coach
        )
        XCTAssertNoThrow(try converter.convertToWKPlanDTO(workout))
    }
}
