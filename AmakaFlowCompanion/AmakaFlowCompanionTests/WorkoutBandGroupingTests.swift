//
//  WorkoutBandGroupingTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2395 — semantic bands replace "Block 7" / "Round 1–3" and the
//  duplicated "WU · squat" rows. E4 from the ticket is the anchor.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutBandGroupingTests: XCTestCase {

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

    private func bands(_ blocks: [Block]) -> [WorkoutBand] {
        WorkoutBandGrouping.bands(
            blocks: blocks,
            estimate: WorkoutDurationEstimator.estimate(blocks: blocks)
        )
    }

    // MARK: - E4 — "Full Body Aesthetics Session" (the Block-7/9/11 mess)

    private func fullBodyAestheticsBlocks() -> [Block] {
        [
            // Unlabeled 3:00 opener — reads as WARM-UP without being told.
            Block(label: nil, structure: .straight, rounds: 1,
                  exercises: [exercise("Jump Rope", seconds: 180)]),
            // The duplicate ramp rows that used to render as their own "Block 8".
            Block(label: "Block 8", structure: .straight, rounds: 1,
                  exercises: [exercise("WU · squat", reps: "8"), exercise("WU · squat", reps: "5")]),
            Block(label: "Block 9", structure: .straight, rounds: 3,
                  exercises: [exercise("squat", reps: "8", rest: 90)]),
            Block(label: "Block 10", structure: .straight, rounds: 1,
                  exercises: [exercise("WU · plank", seconds: 20)]),
            Block(label: "Block 11", structure: .straight, rounds: 2,
                  exercises: [exercise("plank", seconds: 30)]),
            Block(label: "Timed Work", structure: .straight, rounds: 1,
                  exercises: [exercise("Timed Work", seconds: 300)])
        ]
    }

    func testE4NamesSectionsForWhatTheyAreNeverBlockN() {
        let result = bands(fullBodyAestheticsBlocks())
        let titles = result.map(\.title)

        XCTAssertTrue(titles.contains("WARM-UP"), "\(titles)")
        XCTAssertTrue(titles.contains("SQUAT · 3 ROUNDS"), "\(titles)")
        XCTAssertTrue(titles.contains("CORE · 2 ROUNDS"), "\(titles)")

        for title in titles {
            XCTAssertNil(
                title.range(of: #"BLOCK\s*\d"#, options: [.regularExpression, .caseInsensitive]),
                "section named \(title) — 'Block N' must be unrepresentable"
            )
        }
    }

    func testE4FoldsWarmupRampsIntoOneRowInsideWarmUp() {
        let result = bands(fullBodyAestheticsBlocks())
        let allRows = result.flatMap(\.rows)

        // Zero rows named "WU · …" anywhere.
        for row in allRows {
            XCTAssertFalse(
                row.name.lowercased().hasPrefix("wu"),
                "row \(row.name) still renders as a raw warm-up entry"
            )
        }

        guard let warmUp = result.first(where: { $0.title == "WARM-UP" }) else {
            return XCTFail("no WARM-UP band in \(result.map(\.title))")
        }
        XCTAssertEqual(warmUp.kind, .warmUp)

        let ramp = warmUp.rows.first { $0.name.contains("warm-up ramp") && $0.name.contains("Squat") }
        XCTAssertNotNil(ramp, "\(warmUp.rows.map(\.name))")
        // Two duplicate rows became one ramp row with both steps.
        XCTAssertEqual(ramp?.prescription, "8 · 5 · BUILDING")
        XCTAssertEqual(ramp?.exerciseIDs.count, 2)

        XCTAssertTrue(warmUp.rows.contains { $0.name == "Jump Rope" }, "\(warmUp.rows.map(\.name))")
    }

    func testE4SectionSubtotalsSumToTheWorkoutTotal() {
        let blocks = fullBodyAestheticsBlocks()
        let estimate = WorkoutDurationEstimator.estimate(blocks: blocks)
        let result = WorkoutBandGrouping.bands(blocks: blocks, estimate: estimate)

        let summed = result.reduce(0) { $0 + $1.seconds }
        XCTAssertEqual(summed, estimate.totalSec, "bands \(result.map { ($0.title, $0.seconds) })")
    }

    // MARK: - Named structures keep their shape

    func testCircuitKeepsRoundsAndRotateNoRest() {
        let block = Block(
            label: "Main",
            structure: .circuit,
            rounds: 8,
            exercises: [
                exercise("Assault Bike", seconds: 180),
                exercise("Ski Erg", seconds: 180),
                exercise("Rowing Machine", seconds: 180),
                exercise("Spin / Indoor Bike", seconds: 180)
            ]
        )
        let result = bands([block])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "CIRCUIT · 8 ROUNDS · ROTATE, NO REST")
        XCTAssertEqual(result[0].kind, .conditioning)
        XCTAssertEqual(result[0].timeLabel, "96 MIN")
        XCTAssertFalse(result[0].isEstimate)
    }

    func testEmomAndAmrapKeepTheirCaps() {
        let emom = bands([
            Block(label: "Block 3", structure: .emom, rounds: 24,
                  exercises: [exercise("Wall Ball", reps: "10")])
        ])
        XCTAssertEqual(emom.first?.title, "EMOM 24")

        let amrap = bands([
            Block(label: nil, structure: .amrap, rounds: 12,
                  exercises: [exercise("Pull-Up", reps: "5"), exercise("Push-Up", reps: "10")])
        ])
        XCTAssertEqual(amrap.first?.title, "AMRAP 12")
    }

    func testForTimeLabelKeepsItsShape() {
        let result = bands([
            Block(label: "For time", structure: .circuit, rounds: 10,
                  exercises: [
                    exercise("Ski Erg", metres: 500),
                    exercise("Rowing", metres: 500),
                    exercise("Bike", metres: 1000)
                  ])
        ])
        // A circuit structure names itself; the rounds shape survives either way.
        XCTAssertTrue(result[0].title.contains("10 ROUNDS"), result[0].title)
        XCTAssertEqual(result[0].timeLabel, "≈ 62 MIN")
    }

    func testSupersetTakesTheLeadLiftName() {
        let result = bands([
            Block(label: nil, structure: .superset, rounds: 3,
                  exercises: [
                    exercise("Bench Press", reps: "8"),
                    exercise("Ring Row", reps: "10")
                  ])
        ])
        XCTAssertEqual(result.first?.title, "BENCH PRESS · SUPERSET × 3")
    }

    func testUntitledMixedBlockIsNamedForItsDominantModality() {
        let conditioning = bands([
            Block(label: "Block 4", structure: .straight, rounds: 1,
                  exercises: [exercise("Rowing Machine", seconds: 300), exercise("Assault Bike", seconds: 300)])
        ])
        XCTAssertEqual(conditioning.first?.title, "CONDITIONING")

        let core = bands([
            Block(label: "Block 5", structure: .straight, rounds: 2,
                  exercises: [exercise("Plank", seconds: 30), exercise("Hollow Hold", seconds: 30)])
        ])
        XCTAssertEqual(core.first?.title, "CORE · 2 ROUNDS")
    }

    func testSingleLiftBlockTakesTheLiftName() {
        let result = bands([
            Block(label: "Block 2", structure: .straight, rounds: 3,
                  exercises: [exercise("Back Squat", reps: "5", rest: 120)])
        ])
        XCTAssertEqual(result.first?.title, "BACK SQUAT · 3 ROUNDS")
        XCTAssertEqual(result.first?.kind, .work)
    }

    func testLooseSingleExerciseBlocksMergeIntoOneBand() {
        let result = bands([
            Block(label: nil, structure: .straight, rounds: 1,
                  exercises: [exercise("Barbell Bench Press", sets: 3, reps: "8")]),
            Block(label: nil, structure: .straight, rounds: 1,
                  exercises: [exercise("Dumbbell Curl", sets: 3, reps: "12")]),
            Block(label: nil, structure: .straight, rounds: 1,
                  exercises: [exercise("Cable Triceps Extension", sets: 3, reps: "12")])
        ])
        XCTAssertEqual(result.count, 1, "\(result.map(\.title))")
        XCTAssertEqual(result[0].rows.count, 3)
        XCTAssertEqual(result[0].title, "ACCESSORIES")
    }

    // MARK: - Prescription grammar

    func testOneGrammarForEveryTargetFamily() {
        let estimate = WorkoutDurationEstimate.empty
        func line(_ ex: Exercise) -> String {
            WorkoutBandPrescription.line(for: ex, estimate: nil)
        }
        _ = estimate

        XCTAssertEqual(line(exercise("Back Squat", sets: 3, reps: "8")), "3 × 8")
        // Hyphen stored, en-dash displayed (AMA-2379 rule).
        XCTAssertEqual(line(exercise("Back Squat", sets: 3, reps: "8-12")), "3 × 8–12")
        XCTAssertEqual(line(exercise("Rowing", metres: 500)), "500 M")
        XCTAssertEqual(line(exercise("Bike", metres: 1000)), "1.0 KM")
        XCTAssertEqual(line(exercise("Ski Erg", seconds: 180)), "3:00")
        XCTAssertEqual(line(exercise("Farmer Carry")), "OPEN")
        XCTAssertEqual(line(exercise("Bench Press", sets: 3, reps: "8", rest: 90)), "3 × 8 · REST 90S")
    }

    func testStrengthRowsCarryTheirOwnEstimateButTimedRowsDoNot() {
        let strength = exercise("Wide Grip Pull-Up", sets: 3, reps: "6")
        let timed = exercise("Ski Erg", seconds: 180)
        let blocks = [
            Block(label: "Upper", structure: .straight, rounds: 1, exercises: [strength, timed])
        ]
        let estimate = WorkoutDurationEstimator.estimate(blocks: blocks)

        let strengthLine = WorkoutBandPrescription.line(
            for: strength, estimate: estimate.seconds(forExerciseID: strength.id)
        )
        XCTAssertTrue(strengthLine.hasPrefix("3 × 6 · ≈ "), strengthLine)

        let timedLine = WorkoutBandPrescription.line(
            for: timed, estimate: estimate.seconds(forExerciseID: timed.id)
        )
        XCTAssertEqual(timedLine, "3:00", "a timed row already shows its duration")
    }

    // MARK: - Empty

    func testWorkoutWithNoExercisesHasNoBands() {
        XCTAssertTrue(bands([]).isEmpty)
        XCTAssertTrue(bands([Block(label: "Empty", structure: .straight, rounds: 1, exercises: [])]).isEmpty)
    }
}
