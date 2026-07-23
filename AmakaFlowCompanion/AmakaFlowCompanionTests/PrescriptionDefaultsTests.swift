//
//  PrescriptionDefaultsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2311 Task 8 — client soft-default fallback + push parity fixtures.
//

import XCTest
@testable import AmakaFlowCompanion

final class PrescriptionDefaultsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PrescriptionDefaults.resetClientFallbackFlagForTesting()
    }

    override func tearDown() {
        PrescriptionDefaults.resetClientFallbackFlagForTesting()
        super.tearDown()
    }

    // MARK: - Contract parity with backend sanitize shape

    func testMissingSetsGetsDefaultOnStraightSetBlock() throws {
        let json = """
        {
          "title": "Defaults",
          "blocks": [{
            "label": "Main",
            "structure": null,
            "exercises": [
              {"name": "A", "sets": null, "reps_range": {"low": 8, "high": 10}, "rest_sec": null},
              {"name": "B", "sets": 2, "reps": 6}
            ]
          }]
        }
        """.data(using: .utf8)!

        let draft = try SocialImportDraft.fromIngestJSON(
            json,
            platform: .instagram,
            sourceURL: nil,
            equipmentEmpty: false,
            equipmentNote: nil
        )

        let exercises = draft.blocks[0].exercises
        XCTAssertEqual(exercises[0].sets, 3)
        XCTAssertEqual(exercises[0].restSeconds, 60)
        XCTAssertEqual(exercises[0].repsRange, "8-10")
        XCTAssertNil(exercises[0].reps)
        XCTAssertEqual(exercises[1].sets, 2)
        XCTAssertEqual(exercises[1].reps, 6)
        XCTAssertTrue(PrescriptionDefaults.clientFallbackWasUsed)
    }

    func testNoDefaultRepsWhenDistanceOrLoad() throws {
        let json = """
        {
          "title": "Modality",
          "blocks": [{
            "structure": null,
            "exercises": [
              {"name": "Ski", "sets": null, "distance_m": 500, "reps": null, "rest_sec": null},
              {"name": "Carry", "sets": null, "load": "40kg", "reps": null, "rest_sec": null}
            ]
          }]
        }
        """.data(using: .utf8)!

        let draft = try SocialImportDraft.fromIngestJSON(
            json,
            platform: .instagram,
            sourceURL: nil,
            equipmentEmpty: false,
            equipmentNote: nil
        )

        for exercise in draft.exercises {
            XCTAssertNil(exercise.reps)
            XCTAssertEqual(exercise.sets, 3)
            XCTAssertEqual(exercise.restSeconds, 60)
        }
    }

    func testNoPerExerciseRestInsideSupersetBlock() {
        var bench = SocialImportExercise(name: "Bench", sets: 4, reps: 8)
        var row = SocialImportExercise(name: "Row", sets: 4, reps: 8)
        XCTAssertFalse(PrescriptionDefaults.applyIfNeeded(to: &bench, roundsOwnedByFormat: true, recordAnalytics: false))
        XCTAssertFalse(PrescriptionDefaults.applyIfNeeded(to: &row, roundsOwnedByFormat: true, recordAnalytics: false))
        XCTAssertNil(bench.restSeconds)
        XCTAssertNil(row.restSeconds)
    }

    func testDefaultRepsWhenNoPrescriptionMetric() {
        var exercise = SocialImportExercise(name: "Pull Up", sets: 3, reps: nil)
        XCTAssertTrue(PrescriptionDefaults.applyIfNeeded(to: &exercise, roundsOwnedByFormat: false))
        XCTAssertEqual(exercise.reps, 10)
        XCTAssertTrue(PrescriptionDefaults.clientFallbackWasUsed)
    }

    // MARK: - Push / save interval uses effectivePrescription

    func testSaveIntervalUsesRepRangeTarget() {
        let exercise = EditorV2Exercise(
            name: "Squat",
            sets: 3,
            repsRange: RepsRange(low: 8, high: 10),
            restSeconds: 60
        )

        let interval = PrescriptionFormatter.saveInterval(from: exercise)
        XCTAssertEqual(interval.type, "reps")
        XCTAssertEqual(interval.sets, 3)
        XCTAssertEqual(interval.reps, 9)
        XCTAssertEqual(interval.target, "8-10")
        XCTAssertEqual(interval.restSeconds, 60)
    }

    func testSaveIntervalUsesDistancePrimary() {
        let exercise = EditorV2Exercise(
            name: "Ski Erg",
            sets: 3,
            distanceMeters: 500,
            restSeconds: 60
        )

        let interval = PrescriptionFormatter.saveInterval(from: exercise)
        XCTAssertEqual(interval.type, "distance")
        XCTAssertEqual(interval.meters, 500)
    }

    func testBlockConverterUsesEffectivePrescriptionForRange() {
        let exercise = Exercise(
            name: "Squat",
            canonicalName: nil,
            sets: 3,
            reps: "8-10",
            durationSeconds: nil,
            load: nil,
            restSeconds: 60,
            distance: nil,
            notes: nil,
            supersetGroup: nil
        )
        let block = Block(label: "Main", structure: .straight, rounds: 1, exercises: [exercise])

        let intervals = BlockToIntervalConverter.flatten([block])
        guard case .reps(let sets, let reps, let name, _, let restSec, _) = intervals.first else {
            return XCTFail("Expected reps interval")
        }
        XCTAssertEqual(sets, 3)
        XCTAssertEqual(reps, 10)
        XCTAssertEqual(name, "Squat")
        XCTAssertEqual(restSec, 60)
    }
}
