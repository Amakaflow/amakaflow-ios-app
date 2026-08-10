//
//  WorkoutDurationEstimatorTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2395 — worked examples E1–E3 + exactness / open-goal rules.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutDurationEstimatorTests: XCTestCase {

    private func timedExercise(name: String, seconds: Int) -> Exercise {
        Exercise(
            name: name,
            canonicalName: nil,
            sets: nil,
            reps: nil,
            durationSeconds: seconds,
            load: nil,
            restSeconds: nil,
            distance: nil,
            notes: nil,
            focus: nil,
            supersetGroup: nil
        )
    }

    private func distanceExercise(name: String, meters: Double) -> Exercise {
        Exercise(
            name: name,
            canonicalName: nil,
            sets: nil,
            reps: nil,
            durationSeconds: nil,
            load: nil,
            restSeconds: nil,
            distance: meters,
            notes: nil,
            focus: nil,
            supersetGroup: nil
        )
    }

    private func repsExercise(name: String, sets: Int, reps: String) -> Exercise {
        Exercise(
            name: name,
            canonicalName: nil,
            sets: sets,
            reps: reps,
            durationSeconds: nil,
            load: nil,
            restSeconds: nil,
            distance: nil,
            notes: nil,
            focus: nil,
            supersetGroup: nil
        )
    }

    // MARK: - E1 Erg for time

    func testE1ErgForTimeWithinCreatorBand() {
        let block = Block(
            label: "For Time",
            structure: .circuit,
            rounds: 10,
            exercises: [
                distanceExercise(name: "Ski Erg", meters: 500),
                distanceExercise(name: "Rowing", meters: 500),
                distanceExercise(name: "Bike", meters: 1000),
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])

        // 130 + 120 + 105 = 355 × 10 = 3550 + 5% ≈ 3728s → ≈ 62 MIN
        XCTAssertEqual(estimate.totalSec, 3728)
        XCTAssertTrue(estimate.isEstimate)
        XCTAssertEqual(estimate.minuteLabel, "≈ 62 MIN")
        XCTAssertFalse(estimate.minuteLabel.contains("~"))

        let creatorSec = 57 * 60 + 53
        let delta = abs(Double(estimate.totalSec - creatorSec) / Double(creatorSec))
        XCTAssertLessThanOrEqual(delta, 0.15, "Estimate must land within ±15% of creator 57:53")
    }

    // MARK: - E2 Bike ski row (exact)

    func testE2BikeSkiRowEightRoundsExact96() {
        let block = Block(
            label: "Circuit",
            structure: .circuit,
            rounds: 8,
            exercises: [
                timedExercise(name: "Assault Bike", seconds: 180),
                timedExercise(name: "Ski Erg", seconds: 180),
                timedExercise(name: "Rowing Machine", seconds: 180),
                timedExercise(name: "Spin / Indoor Bike", seconds: 180),
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])

        XCTAssertEqual(estimate.totalSec, 5760)
        XCTAssertFalse(estimate.isEstimate)
        XCTAssertEqual(estimate.minuteLabel, "96 MIN")
        XCTAssertFalse(estimate.minuteLabel.contains("≈"))
        XCTAssertFalse(estimate.minuteLabel.contains("~"))

        // Real Apple recording 1:36:10 — estimator 96:00 within transition margin.
        let recorded = 96 * 60 + 10
        XCTAssertLessThanOrEqual(abs(estimate.totalSec - recorded), 60)
        XCTAssertEqual(estimate.activeSublabel, "ALL TIMED · EXACT")
    }

    func testE2SixRoundVariantExact72() {
        let block = Block(
            label: "Circuit",
            structure: .circuit,
            rounds: 6,
            exercises: [
                timedExercise(name: "Assault Bike", seconds: 180),
                timedExercise(name: "Ski Erg", seconds: 180),
                timedExercise(name: "Rowing Machine", seconds: 180),
                timedExercise(name: "Spin / Indoor Bike", seconds: 180),
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        XCTAssertEqual(estimate.totalSec, 4320)
        XCTAssertFalse(estimate.isEstimate)
        XCTAssertEqual(estimate.minuteLabel, "72 MIN")
    }

    // MARK: - E3 Strength

    func testE3UpperBodyBandAndActiveShare() {
        // 10 exercises, 28 sets: mix of 3×10 and heavier 2×4 / 3×6.
        var exercises: [Exercise] = (0..<7).map { i in
            repsExercise(name: "Lift \(i)", sets: 3, reps: "10")
        }
        exercises.append(repsExercise(name: "Heavy A", sets: 2, reps: "4"))
        exercises.append(repsExercise(name: "Heavy B", sets: 3, reps: "6"))
        exercises.append(repsExercise(name: "Finisher", sets: 3, reps: "10"))
        // 7*3 + 2 + 3 + 3 = 21 + 8 = 29 — trim one set via a 2×10
        exercises[0] = repsExercise(name: "Lift 0", sets: 2, reps: "10")
        // 2+3*6 +2+3+3 = 2+18+8 = 28 sets

        let block = Block(
            label: nil,
            structure: .straight,
            rounds: 1,
            exercises: exercises
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        let minutes = Double(estimate.totalSec) / 60.0
        XCTAssertTrue(estimate.isEstimate)
        XCTAssertGreaterThanOrEqual(minutes, 49)
        XCTAssertLessThanOrEqual(minutes, 65)

        let activeShare = Double(estimate.activeSec) / Double(max(1, estimate.totalSec))
        XCTAssertGreaterThan(activeShare, 0.30)
        XCTAssertLessThan(activeShare, 0.70)

        let heavy = estimate.perExercise.first { $0.exerciseId == exercises[8].id }
        XCTAssertNotNil(heavy)
        XCTAssertGreaterThan(heavy?.seconds ?? 0, 0)
        XCTAssertTrue(heavy?.isEstimate == true)
    }

    // MARK: - Rules

    func testExactnessFlipsWhenAnyComponentEstimated() {
        let timed = Block(
            label: nil,
            structure: .circuit,
            rounds: 1,
            exercises: [timedExercise(name: "Bike", seconds: 60)]
        )
        let mixed = Block(
            label: nil,
            structure: .circuit,
            rounds: 1,
            exercises: [
                timedExercise(name: "Bike", seconds: 60),
                distanceExercise(name: "Row", meters: 500),
            ]
        )
        XCTAssertFalse(WorkoutDurationEstimator.estimate(blocks: [timed]).isEstimate)
        XCTAssertTrue(WorkoutDurationEstimator.estimate(blocks: [mixed]).isEstimate)
    }

    func testOpenGoalExcludedAndNamedInBasis() {
        let block = Block(
            label: nil,
            structure: .straight,
            rounds: 1,
            exercises: [
                timedExercise(name: "Bike", seconds: 180),
                Exercise(
                    name: "Max effort",
                    canonicalName: nil,
                    sets: nil,
                    reps: nil,
                    durationSeconds: nil,
                    load: nil,
                    restSeconds: nil,
                    distance: nil,
                    notes: nil,
                    focus: nil,
                    supersetGroup: nil
                ),
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        XCTAssertEqual(estimate.totalSec, 180)
        XCTAssertTrue(estimate.basisNote.contains("OPEN"))
        XCTAssertTrue(estimate.perExercise.contains(where: \.isOpen))
        XCTAssertFalse(estimate.minuteLabel.contains("~1"))
    }

    func testSetsOnlyUsesOneMinWorkAndOneMinRestPerSet() {
        // Jeff-style import: sets known, no reps/time → 2 min per set.
        let block = Block(
            label: nil,
            structure: .straight,
            rounds: 1,
            exercises: [
                Exercise(
                    name: "Incline Smith Machine Press",
                    canonicalName: nil,
                    sets: 5,
                    reps: nil,
                    durationSeconds: nil,
                    load: nil,
                    restSeconds: nil,
                    distance: nil,
                    notes: nil,
                    focus: nil,
                    supersetGroup: nil
                ),
                Exercise(
                    name: "Machine Pec Deck",
                    canonicalName: nil,
                    sets: 3,
                    reps: nil,
                    durationSeconds: nil,
                    load: nil,
                    restSeconds: nil,
                    distance: nil,
                    notes: nil,
                    focus: nil,
                    supersetGroup: nil
                ),
                repsExercise(name: "Weighted Pull-Ups", sets: 3, reps: "6"),
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        // 5×120 + 3×120 = 960; pull-ups still use reps rule (3×(18+15+90)=369)
        XCTAssertEqual(estimate.totalSec, 960 + 369)
        XCTAssertTrue(estimate.isEstimate)
        XCTAssertTrue(estimate.basisNote.contains("1 MIN WORK"))
        XCTAssertFalse(estimate.perExercise.contains(where: \.isOpen))
        XCTAssertEqual(estimate.minuteLabel, "≈ 22 MIN")
    }

    func testJeffUpperBodySetsOnlyNearCreator45() {
        let block = Block(
            label: nil,
            structure: .straight,
            rounds: 1,
            exercises: [
                Exercise(name: "Incline Smith Machine Press", canonicalName: nil, sets: 5, reps: nil, durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                Exercise(name: "Machine Pec Deck", canonicalName: nil, sets: 3, reps: nil, durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                Exercise(name: "Machine Lateral Raises", canonicalName: nil, sets: 3, reps: nil, durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                repsExercise(name: "Weighted Pull-Ups", sets: 3, reps: "6"),
                Exercise(name: "Machine Rows", canonicalName: nil, sets: 3, reps: nil, durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                Exercise(name: "Easy Bar Preacher Curls", canonicalName: nil, sets: 3, reps: nil, durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                Exercise(name: "Triceps Press Downs", canonicalName: nil, sets: 3, reps: nil, durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        // 20 sets × 120s + pull-ups 369 = 2769s ≈ 46 MIN — near the creator's 45.
        XCTAssertEqual(estimate.totalSec, 2769)
        XCTAssertEqual(estimate.minuteLabel, "≈ 46 MIN")
        let creatorSec = 45 * 60
        let delta = abs(Double(estimate.totalSec - creatorSec) / Double(creatorSec))
        XCTAssertLessThanOrEqual(delta, 0.15)
    }

    func testJeffFixtureFileMatchesHandBuiltSetsOnlyMath() throws {
        #if DEBUG
        let workout = try FixtureLoader.loadFixture(named: "jeff_nippard_upper_body")
        let estimate = WorkoutDurationEstimator.estimate(for: workout)
        XCTAssertEqual(estimate.totalSec, 2769)
        XCTAssertEqual(estimate.minuteLabel, "≈ 46 MIN")
        XCTAssertEqual(estimate.perExercise.count, 7)
        XCTAssertEqual(estimate.perExercise.filter(\.isOpen).count, 0)
        #else
        throw XCTSkip("FixtureLoader is DEBUG-only")
        #endif
    }

    func testTabataCapUsesThirtySecondsPerExercisePerRound() {
        let block = Block(
            label: nil,
            structure: .tabata,
            rounds: 8,
            exercises: [
                Exercise(name: "Squat", canonicalName: nil, sets: nil, reps: nil, durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                Exercise(name: "Push-Up", canonicalName: nil, sets: nil, reps: nil, durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        // 8 rounds × 2 stations × 30s = 480s exact
        XCTAssertEqual(estimate.totalSec, 480)
        XCTAssertFalse(estimate.isEstimate)
        XCTAssertEqual(estimate.minuteLabel, "8 MIN")
    }

    func testMultiStationIgnoresPerExerciseSets() {
        let block = Block(
            label: nil,
            structure: .circuit,
            rounds: 4,
            exercises: [
                Exercise(name: "Bike", canonicalName: nil, sets: 3, reps: "10", durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                Exercise(name: "Ski", canonicalName: nil, sets: 3, reps: "10", durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        // Per round: 2 × (10×3 + 15) = 90; ×4 rounds = 360; +5% transitions ≈ 378
        XCTAssertEqual(estimate.totalSec, 378)
        XCTAssertTrue(estimate.isEstimate)
    }

    func testStructureWinsOverBogusStoredDuration() {
        let workout = Workout(
            id: "w",
            name: "Circuit",
            sport: .cardio,
            duration: 60, // the old ~1 MIN bug source
            blocks: [
                Block(
                    label: nil,
                    structure: .circuit,
                    rounds: 8,
                    exercises: [
                        timedExercise(name: "Assault Bike", seconds: 180),
                        timedExercise(name: "Ski Erg", seconds: 180),
                        timedExercise(name: "Rowing Machine", seconds: 180),
                        timedExercise(name: "Spin", seconds: 180),
                    ]
                )
            ],
            source: .manual
        )
        let estimate = WorkoutDurationEstimator.estimate(for: workout)
        XCTAssertEqual(estimate.totalSec, 5760)
        XCTAssertEqual(estimate.minuteLabel, "96 MIN")
    }

    func testMinuteLabelNeverEmitsTildeOneMin() {
        let labels = [
            WorkoutDurationEstimate.minuteLabel(seconds: 0, isEstimate: true),
            WorkoutDurationEstimate.minuteLabel(seconds: 45, isEstimate: true),
            WorkoutDurationEstimate.minuteLabel(seconds: 60, isEstimate: false),
        ]
        for label in labels {
            XCTAssertFalse(label.contains("~1 MIN"), label)
            XCTAssertFalse(label.hasPrefix("~"), label)
        }
    }
}
