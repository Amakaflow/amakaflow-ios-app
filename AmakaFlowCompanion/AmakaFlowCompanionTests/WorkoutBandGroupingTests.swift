//
//  WorkoutBandGroupingTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2395 — the section layer RESTYLES the stored structure and never
//  reshapes it. These tests exist mainly to hold that line: one block in, one
//  section out, same order, same members, no invented sections.
//
//  Warm-up ramps are deliberately absent here. They belong to the Apple Watch
//  plan, not the library workout (see WorkoutKitPlanStepSummary+Sections).
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

    // MARK: - The rule: structure in, structure out

    /// A real imported upper-body session: seven exercises, one block, no
    /// warm-up, no rest recorded. It must render as exactly that.
    func testStoredStructureSurvivesUnchanged() {
        let names = [
            "Incline Smith Machine Press", "Machine Pec Deck", "Machine Lateral Raises",
            "Weighted Pull-Ups", "Machine Rows", "Easy Bar Preacher Curls", "Triceps Press Downs"
        ]
        let block = Block(
            label: nil,
            structure: .straight,
            rounds: 1,
            exercises: names.map { exercise($0, sets: 3) }
        )
        let result = bands([block])

        XCTAssertEqual(result.count, 1, "one stored block must render as one section")
        XCTAssertEqual(result[0].rows.map(\.name), names, "order and membership are untouched")
        XCTAssertFalse(result[0].hasHeader, "an unlabeled straight block gets no invented heading")
    }

    func testBlocksAreNeitherMergedNorReordered() {
        let blocks = [
            Block(label: nil, structure: .straight, rounds: 1, exercises: [exercise("A", sets: 3)]),
            Block(label: nil, structure: .straight, rounds: 1, exercises: [exercise("B", sets: 3)]),
            Block(label: nil, structure: .straight, rounds: 1, exercises: [exercise("C", sets: 3)])
        ]
        let result = bands(blocks)
        XCTAssertEqual(result.count, 3, "loose blocks stay separate — merging is reshaping")
        XCTAssertEqual(result.map { $0.rows.map(\.name) }, [["A"], ["B"], ["C"]])
    }

    /// A short opener is NOT promoted to a warm-up. Only the data decides that.
    func testShortOpenerIsNotPromotedToWarmUp() {
        let result = bands([
            Block(label: nil, structure: .straight, rounds: 1, exercises: [exercise("Jump Rope", seconds: 180)]),
            Block(label: nil, structure: .straight, rounds: 3, exercises: [exercise("Back Squat", reps: "8")])
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertNotEqual(result[0].title, "WARM-UP")
        XCTAssertNotEqual(result[0].kind, .warmUp)
    }

    func testWarmUpSectionAppearsOnlyWhenTheBlockSaysSo() {
        let result = bands([
            Block(label: "Warm-up", structure: .straight, rounds: 1, exercises: [exercise("Band Pull-Apart", reps: "10")]),
            Block(label: "Cool-down", structure: .straight, rounds: 1, exercises: [exercise("Stretch", seconds: 120)])
        ])
        XCTAssertEqual(result.map(\.title), ["WARM-UP", "COOLDOWN"])
        XCTAssertEqual(result.map(\.kind), [.warmUp, .cooldown])
    }

    /// Exercises named "WU · …" are a WATCH-PLAN convention. If one ever turns
    /// up in a library block it is rendered where it sits, like any other row.
    func testWatchStyleWarmupEntriesAreNotHoistedOrFolded() {
        let block = Block(
            label: nil,
            structure: .straight,
            rounds: 1,
            exercises: [
                exercise("WU · Back Squat", reps: "8"),
                exercise("WU · Back Squat", reps: "5"),
                exercise("Back Squat", sets: 3, reps: "8")
            ]
        )
        let result = bands([block])
        XCTAssertEqual(result.count, 1, "no warm-up section is conjured out of row names")
        XCTAssertEqual(result[0].rows.map(\.name), ["WU · Back Squat", "WU · Back Squat", "Back Squat"])
    }

    // MARK: - Titles come from the block, never from a guess

    func testGenericExporterLabelsAreDroppedNotReplaced() {
        for label in ["Block 7", "Main", "Section 2", "Round 1-3"] {
            let result = bands([
                Block(label: label, structure: .straight, rounds: 1, exercises: [exercise("Back Squat", sets: 3)])
            ])
            XCTAssertFalse(result[0].hasHeader, "\(label) should render no heading at all")
            XCTAssertNil(
                result[0].title.range(of: #"BLOCK\s*\d"#, options: [.regularExpression, .caseInsensitive]),
                result[0].title
            )
        }
    }

    func testRealLabelIsKept() {
        let result = bands([
            Block(label: "Finisher", structure: .straight, rounds: 1, exercises: [exercise("Ski Erg", metres: 500)])
        ])
        XCTAssertEqual(result[0].title, "FINISHER")
    }

    // MARK: - Circuit / superset / straight sets

    /// One station is not a circuit, whatever the stored structure claims.
    func testSingleExerciseBlockIsNeverACircuit() {
        let block = Block(
            label: nil,
            structure: .circuit,
            rounds: 5,
            exercises: [exercise("Incline Smith Machine Press", sets: 5)]
        )
        XCTAssertNil(WorkoutBandGrouping.structureDescriptor(for: block))

        let result = bands([block])
        XCTAssertFalse(result[0].title.contains("CIRCUIT"), result[0].title)
        XCTAssertEqual(result[0].rows[0].prescription, "5 SETS", "straight sets read as sets")
    }

    func testCircuitNeedsSeveralStations() {
        let result = bands([
            Block(label: nil, structure: .circuit, rounds: 8, exercises: [
                exercise("Assault Bike", seconds: 180),
                exercise("Ski Erg", seconds: 180),
                exercise("Rowing Machine", seconds: 180),
                exercise("Spin / Indoor Bike", seconds: 180)
            ])
        ])
        XCTAssertEqual(result[0].title, "CIRCUIT · 8 ROUNDS")
        XCTAssertFalse(result[0].title.contains("NO REST"), "absence of rest says nothing")
        XCTAssertEqual(result[0].timeLabel, "96 MIN")
    }

    func testSupersetIsAPairWorkedTogether() {
        let result = bands([
            Block(label: nil, structure: .superset, rounds: 3, exercises: [
                exercise("Bench Press", reps: "8"),
                exercise("Ring Row", reps: "10")
            ])
        ])
        XCTAssertEqual(result[0].title, "SUPERSET × 3")
    }

    func testEmomAndAmrapKeepTheirCaps() {
        let emom = bands([
            Block(label: "Block 3", structure: .emom, rounds: 24, exercises: [
                exercise("Wall Ball", reps: "10"), exercise("Burpee", reps: "8")
            ])
        ])
        XCTAssertEqual(emom[0].title, "EMOM 24")

        let amrap = bands([
            Block(label: nil, structure: .amrap, rounds: 12, exercises: [
                exercise("Pull-Up", reps: "5"), exercise("Push-Up", reps: "10")
            ])
        ])
        XCTAssertEqual(amrap[0].title, "AMRAP 12")
    }

    func testLabelAndFormatCombineWhenBothArePresent() {
        let result = bands([
            Block(label: "Engine", structure: .circuit, rounds: 4, exercises: [
                exercise("Rowing Machine", seconds: 120), exercise("Assault Bike", seconds: 120)
            ])
        ])
        XCTAssertEqual(result[0].title, "ENGINE · CIRCUIT · 4 ROUNDS")
    }

    // MARK: - Subtotals

    func testSectionSubtotalsSumToTheWorkoutTotal() {
        let blocks = [
            Block(label: "Warm-up", structure: .straight, rounds: 1, exercises: [exercise("Jump Rope", seconds: 180)]),
            Block(label: nil, structure: .circuit, rounds: 4, exercises: [
                exercise("Assault Bike", seconds: 180), exercise("Ski Erg", seconds: 180)
            ])
        ]
        let estimate = WorkoutDurationEstimator.estimate(blocks: blocks)
        let result = WorkoutBandGrouping.bands(blocks: blocks, estimate: estimate)
        XCTAssertEqual(result.reduce(0) { $0 + $1.seconds }, estimate.totalSec)
    }

    // MARK: - Prescription grammar

    func testOneGrammarForEveryTargetFamily() {
        func line(_ ex: Exercise) -> String {
            WorkoutBandPrescription.line(for: ex, estimate: nil)
        }

        XCTAssertEqual(line(exercise("Machine Pec Deck", sets: 3)), "3 SETS")
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
        let blocks = [Block(label: "Upper", structure: .straight, rounds: 1, exercises: [strength, timed])]
        let estimate = WorkoutDurationEstimator.estimate(blocks: blocks)

        XCTAssertTrue(
            WorkoutBandPrescription.line(for: strength, estimate: estimate.seconds(forExerciseID: strength.id))
                .hasPrefix("3 × 6 · ≈ ")
        )
        XCTAssertEqual(
            WorkoutBandPrescription.line(for: timed, estimate: estimate.seconds(forExerciseID: timed.id)),
            "3:00",
            "a timed row already shows its duration"
        )
    }

    // MARK: - Empty

    func testWorkoutWithNoExercisesHasNoBands() {
        XCTAssertTrue(bands([]).isEmpty)
        XCTAssertTrue(bands([Block(label: "Empty", structure: .straight, rounds: 1, exercises: [])]).isEmpty)
    }
}
