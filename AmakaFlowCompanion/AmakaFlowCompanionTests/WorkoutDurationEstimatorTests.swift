//
//  WorkoutDurationEstimatorTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2395 — worked examples E1–E4 from the ticket are the targets here.
//  E2 is the regression anchor: the "Bike ski row repeats" circuit that used
//  to render "~1 MIN" is 96:00 exact, against a real Apple recording of 1:36:10.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutDurationEstimatorTests: XCTestCase {

    // MARK: - Fixtures

    private func exercise(
        _ name: String,
        sets: Int? = nil,
        reps: String? = nil,
        seconds: Int? = nil,
        metres: Double? = nil,
        rest: Int? = nil
    ) -> Exercise {
        Exercise(
            name: name,
            canonicalName: nil,
            sets: sets,
            reps: reps,
            durationSeconds: seconds,
            load: nil,
            restSeconds: rest,
            distance: metres,
            notes: nil,
            supersetGroup: nil
        )
    }

    // MARK: - E1 — Instagram "Erg Workout For Time"

    /// 10 rounds of 500 m ski + 500 m row + 1000 m bike. Distances price off the
    /// pace table, so the whole thing is an estimate and picks up transitions.
    func testE1ErgWorkoutForTimeEstimatesFromDistances() {
        let block = Block(
            label: "For time",
            structure: .circuit,
            rounds: 10,
            exercises: [
                exercise("Ski Erg", metres: 500),
                exercise("Rowing", metres: 500),
                exercise("Bike", metres: 1000)
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])

        // round = 130 + 120 + 105 = 355s → ×10 = 3550 → +5% transitions.
        XCTAssertEqual(estimate.totalSec, 3728)
        XCTAssertTrue(estimate.isEstimate)
        XCTAssertEqual(estimate.totalLabel, "≈ 62 MIN")

        // Sanity anchor: the creator ran it in 57:53. Assert the BAND, not the
        // number, so tuning the pace table can't break this test.
        let creatorSeconds = 57 * 60 + 53
        let drift = abs(Double(estimate.totalSec - creatorSeconds)) / Double(creatorSeconds)
        XCTAssertLessThanOrEqual(drift, 0.15, "estimate \(estimate.totalSec)s vs creator \(creatorSeconds)s")

        XCTAssertTrue(estimate.basisNote.contains("DISTANCES"), estimate.basisNote)
        XCTAssertFalse(
            estimate.basisNote.contains("YOUR RECENT PACES"),
            "v1 uses default paces — never claim the user's own paces before AMA-2387 lands"
        )
    }

    // MARK: - E2 — the "~1 MIN" regression anchor

    /// CIRCUIT 8 rounds × 4 stations × 3:00, no rest steps. Every step is timed,
    /// so the total is EXACT — no ≈, and no transition padding either (padding
    /// is a guess and may not be added to an exact total).
    func testE2BikeSkiRowRepeatsIsExactNinetySixMinutes() {
        let estimate = WorkoutDurationEstimator.estimate(blocks: [bikeSkiRowCircuit(rounds: 8)])

        XCTAssertEqual(estimate.totalSec, 5760)
        XCTAssertEqual(estimate.activeSec, 5760)
        XCTAssertFalse(estimate.isEstimate)
        XCTAssertEqual(estimate.totalLabel, "96 MIN")
        XCTAssertFalse(estimate.totalLabel.contains("≈"))
        XCTAssertEqual(estimate.activeNote, "ALL TIMED · EXACT")

        // David's real Apple recording of this exact workout: 1:36:10.
        let recorded = 1 * 3600 + 36 * 60 + 10
        XCTAssertLessThanOrEqual(
            abs(estimate.totalSec - recorded), 60,
            "96:00 must land inside the transition margin of the real 1:36:10"
        )
    }

    func testE2SixRoundVariantIsExactSeventyTwoMinutes() {
        let estimate = WorkoutDurationEstimator.estimate(blocks: [bikeSkiRowCircuit(rounds: 6)])
        XCTAssertEqual(estimate.totalSec, 4320)
        XCTAssertEqual(estimate.totalLabel, "72 MIN")
        XCTAssertFalse(estimate.isEstimate)
    }

    private func bikeSkiRowCircuit(rounds: Int) -> Block {
        Block(
            label: "Main",
            structure: .circuit,
            rounds: rounds,
            exercises: [
                exercise("Assault Bike", seconds: 180),
                exercise("Ski Erg", seconds: 180),
                exercise("Rowing Machine", seconds: 180),
                exercise("Spin / Indoor Bike", seconds: 180)
            ]
        )
    }

    // MARK: - E3 — YouTube "Full Upper Body" (reps, no explicit rest)

    func testE3FullUpperBodyLandsInStrengthBand() {
        let estimate = WorkoutDurationEstimator.estimate(blocks: [fullUpperBodyBlock()])

        let minutes = Double(estimate.totalSec) / 60.0
        XCTAssertGreaterThanOrEqual(minutes, 49, "got \(minutes) min")
        XCTAssertLessThanOrEqual(minutes, 65, "got \(minutes) min")
        XCTAssertTrue(estimate.isEstimate)

        // ACTIVE is work only — roughly half the session once rest is stripped.
        let activeShare = Double(estimate.activeSec) / Double(estimate.totalSec)
        XCTAssertGreaterThan(activeShare, 0.35, "active share \(activeShare)")
        XCTAssertLessThan(activeShare, 0.60, "active share \(activeShare)")

        // Per-exercise estimates render, so a row can show "3 × 6 · ≈ 6 MIN".
        XCTAssertEqual(estimate.perExercise.count, 10)
        XCTAssertTrue(estimate.perExercise.allSatisfy { $0.seconds > 0 && $0.isEstimate })

        // Heavy sets (≤ 6 reps) rest longer, so the copy names a range.
        XCTAssertTrue(estimate.basisNote.contains("REST 60–90S/SET"), estimate.basisNote)
        XCTAssertTrue(estimate.activeNote.hasPrefix("LIFTING"), estimate.activeNote)
    }

    private func fullUpperBodyBlock() -> Block {
        Block(
            label: "Upper body",
            structure: .straight,
            rounds: 1,
            exercises: [
                exercise("Barbell Overhead Press", sets: 2, reps: "4"),
                exercise("Wide Grip Pull-Up", sets: 3, reps: "6"),
                exercise("Close Grip Bench Press", sets: 2, reps: "10"),
                exercise("Wide Grip Seated Cable Row", sets: 3, reps: "12"),
                exercise("Incline Dumbbell Press", sets: 3, reps: "10"),
                exercise("Chest Supported Row", sets: 3, reps: "10"),
                exercise("Dumbbell Lateral Raise", sets: 3, reps: "15"),
                exercise("Cable Triceps Extension", sets: 3, reps: "12"),
                exercise("Dumbbell Curl", sets: 3, reps: "12"),
                exercise("Face Pull", sets: 3, reps: "15")
            ]
        )
    }

    // MARK: - Exactness rule

    func testSingleEstimatedComponentFlipsWholeWorkoutToEstimate() {
        let timed = Block(
            label: "Main",
            structure: .straight,
            rounds: 1,
            exercises: [exercise("Rowing", seconds: 600), exercise("Bike", seconds: 600)]
        )
        XCTAssertFalse(WorkoutDurationEstimator.estimate(blocks: [timed]).isEstimate)

        let mixed = Block(
            label: "Main",
            structure: .straight,
            rounds: 1,
            exercises: [exercise("Rowing", seconds: 600), exercise("Back Squat", sets: 3, reps: "8")]
        )
        XCTAssertTrue(WorkoutDurationEstimator.estimate(blocks: [mixed]).isEstimate)
    }

    func testExplicitRestKeepsTimedWorkExact() {
        let block = Block(
            label: "Intervals",
            structure: .straight,
            rounds: 1,
            exercises: [exercise("Rowing", sets: 4, seconds: 120, rest: 60)]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        XCTAssertEqual(estimate.activeSec, 480)
        XCTAssertEqual(estimate.totalSec, 720)
        XCTAssertFalse(estimate.isEstimate, "an explicit rest value is a fact, not a guess")
    }

    // MARK: - Open goals

    func testOpenGoalStepIsExcludedAndNamedNeverGivenAFakeMinute() {
        let block = Block(
            label: "Main",
            structure: .straight,
            rounds: 1,
            exercises: [
                exercise("Rowing Machine", seconds: 600),
                exercise("Farmer Carry")  // no target at all
            ]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])

        XCTAssertEqual(estimate.totalSec, 600, "the open step contributes nothing")
        XCTAssertTrue(estimate.hasOpenSteps)
        XCTAssertTrue(estimate.basisNote.hasSuffix("+ OPEN STEPS"), estimate.basisNote)
        XCTAssertEqual(estimate.seconds(forExerciseID: block.exercises[1].id)?.seconds, 0)
    }

    func testWorkoutWithNothingMeasurableSaysSoRatherThanInventingAMinute() {
        let block = Block(
            label: "Main",
            structure: .straight,
            rounds: 1,
            exercises: [exercise("Mobility flow"), exercise("Breathing")]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        XCTAssertEqual(estimate.totalSec, 0)
        XCTAssertTrue(estimate.isUnknown)
        XCTAssertEqual(estimate.totalLabel, "TIME NOT SET")
    }

    /// The whole point of the ticket: "~1 MIN" must be unrepresentable.
    func testTildeMinuteIsUnrepresentable() {
        let candidates = [0, 1, 30, 59, 60, 61, 3550, 5760, 7200, 7260]
        for seconds in candidates {
            for isEstimate in [true, false] {
                let label = WorkoutDurationEstimate.label(seconds: seconds, isEstimate: isEstimate)
                XCTAssertFalse(label.contains("~"), "\(seconds)s produced \(label)")
            }
        }
        XCTAssertEqual(WorkoutDurationEstimate.label(seconds: 30, isEstimate: true), "≈ 30 SEC")
        XCTAssertEqual(WorkoutDurationEstimate.label(seconds: 0, isEstimate: true), "TIME NOT SET")
        // Minutes all the way up, per the rig: "96 MIN", never "1H 36M".
        XCTAssertEqual(WorkoutDurationEstimate.label(seconds: 5760, isEstimate: false), "96 MIN")
        XCTAssertEqual(WorkoutDurationEstimate.label(seconds: 7200, isEstimate: false), "120 MIN")
    }

    // MARK: - Capped structures

    func testEmomIsExactMinutesTimesRounds() {
        let block = Block(
            label: "EMOM 24",
            structure: .emom,
            rounds: 24,
            exercises: [exercise("Wall Ball", reps: "10"), exercise("Burpee", reps: "8")]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        XCTAssertEqual(estimate.totalSec, 24 * 60)
        XCTAssertFalse(estimate.isEstimate, "a cap is wall-clock, not a guess")
    }

    func testAmrapUsesTheCapNotTheContents() {
        let block = Block(
            label: "AMRAP 12",
            structure: .amrap,
            rounds: 1,
            exercises: [exercise("Pull-Up", reps: "5"), exercise("Push-Up", reps: "10")]
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        XCTAssertEqual(estimate.totalSec, 12 * 60)
        XCTAssertFalse(estimate.isEstimate)
    }

    // MARK: - Supersets

    func testSupersetRestsAfterThePairNotAfterEachExercise() {
        let superset = Block(
            label: "Bench",
            structure: .superset,
            rounds: 3,
            exercises: [
                exercise("Bench Press", reps: "8", rest: 90),
                exercise("Ring Row", reps: "10", rest: 90)
            ]
        )
        let straight = Block(
            label: "Bench",
            structure: .straight,
            rounds: 3,
            exercises: [
                exercise("Bench Press", reps: "8", rest: 90),
                exercise("Ring Row", reps: "10", rest: 90)
            ]
        )
        let supersetEstimate = WorkoutDurationEstimator.estimate(blocks: [superset])
        let straightEstimate = WorkoutDurationEstimator.estimate(blocks: [straight])
        XCTAssertLessThan(supersetEstimate.totalSec, straightEstimate.totalSec)

        // Work is identical; the superset simply drops one rest per round —
        // carried through the same transition padding both blocks receive.
        XCTAssertEqual(supersetEstimate.activeSec, straightEstimate.activeSec)
        let droppedRest = Double(90 * 3)
        let expectedGap = Int((droppedRest * WorkoutDurationEstimator.transitionFactor).rounded())
        XCTAssertEqual(straightEstimate.totalSec - supersetEstimate.totalSec, expectedGap)
    }

    // MARK: - Rounds + section breakdown

    func testSectionSubtotalsSumToTotal() {
        let blocks = [
            Block(
                label: "Warm-up",
                structure: .straight,
                rounds: 1,
                exercises: [exercise("Jump Rope", seconds: 180)]
            ),
            bikeSkiRowCircuit(rounds: 4)
        ]
        let estimate = WorkoutDurationEstimator.estimate(blocks: blocks)
        let summed = estimate.perSection.reduce(0) { $0 + $1.seconds }
        XCTAssertEqual(summed, estimate.totalSec)
        XCTAssertEqual(estimate.perSection.count, 2)
    }

    func testRestBetweenRoundsIsNotChargedAfterTheLastRound() {
        let block = Block(
            label: "Intervals",
            structure: .circuit,
            rounds: 3,
            exercises: [exercise("Rowing Machine", seconds: 120)],
            restBetweenSeconds: 60
        )
        let estimate = WorkoutDurationEstimator.estimate(blocks: [block])
        // 3 × 120 work + 2 × 60 rest between rounds.
        XCTAssertEqual(estimate.totalSec, 360 + 120)
        XCTAssertEqual(estimate.activeSec, 360)
    }
}
