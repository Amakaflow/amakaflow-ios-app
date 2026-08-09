//
//  PrescriptionDisplayTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2311 Task 7 — detail chrome, collapse, shared formatter parity.
//

import XCTest
@testable import AmakaFlowCompanion

final class PrescriptionDisplayTests: XCTestCase {

    // MARK: - Shared formatter parity (AMA-2312: shared resolver, per-surface adornment)

    private func makeExercise(
        name: String = "Squat",
        sets: Int? = 3,
        reps: String? = "8-10",
        distance: Double? = nil,
        restSeconds: Int? = 60,
        load: ExerciseLoad? = nil,
        notes: String? = nil
    ) -> Exercise {
        Exercise(
            name: name,
            canonicalName: nil,
            sets: sets,
            reps: reps,
            durationSeconds: nil,
            load: load,
            restSeconds: restSeconds,
            distance: distance,
            notes: notes,
            supersetGroup: nil
        )
    }

    func testDetailLineUsesPrimaryPlusLoadNotNotesOrRest() {
        let exercise = makeExercise(
            sets: 2,
            reps: "6",
            restSeconds: 90,
            load: ExerciseLoad(value: 0, unit: "bodyweight"),
            notes: "Use a 30 to 45 degree incline and squeeze your upper pecs hard"
        )
        let line = exercise.ddDetailLine
        XCTAssertTrue(line.contains("2 × 6"), line)
        XCTAssertTrue(line.contains("BODYWEIGHT"), line)
        XCTAssertFalse(line.contains("INCLINE"), line)
        XCTAssertFalse(line.contains("REST"), line)
        XCTAssertFalse(line.contains("PECS"), line)
    }

    func testDetailAndEditorSharePrimaryResolverNotFullStringEquality() {
        let exercise = makeExercise(
            name: "Pull-Up",
            sets: 3,
            reps: "10",
            restSeconds: 60,
            load: ExerciseLoad(value: 20, unit: "kg"),
            notes: "Dead hang briefly between reps"
        )
        let editorExercise = EditorV2Exercise(
            name: "Pull-Up",
            sets: 3,
            reps: 10,
            weightKg: 20,
            restSeconds: 60
        )
        XCTAssertEqual(
            PrescriptionFormatter.resolvedPrimaryText(from: exercise),
            PrescriptionFormatter.resolvedPrimaryText(from: editorExercise)
        )
        XCTAssertEqual(
            PrescriptionFormatter.resolvedLoadText(from: exercise)?.uppercased(),
            PrescriptionFormatter.resolvedLoadText(from: editorExercise)?.uppercased()
        )
        // Full assembled strings intentionally diverge (detail omits rest/notes).
        XCTAssertNotEqual(
            exercise.ddDetailLine,
            editorExercise.summaryLine.uppercased()
        )
        XCTAssertFalse(exercise.ddDetailLine.contains("REST"))
        XCTAssertTrue(editorExercise.summaryLine.uppercased().contains("REST"))
    }

    func testClarifySummaryMatchesPrescriptionFormatter() {
        let model = StructureExerciseModel(name: "Ski Erg", sets: 3, reps: nil, distanceM: 500)
        let expected = PrescriptionFormatter.clarifyLine(for: model)
        XCTAssertEqual(StructureClarifyExercise.summary(for: model), expected)
        XCTAssertEqual(expected, "3 × 500 M")
    }

    func testExerciseInfoKeepsCuesOutOfPrescriptionLine() {
        let exercise = makeExercise(
            notes: "Brace hard and drive through the floor"
        )
        let info = exercise.ddInfoPrescriptionLine
        XCTAssertFalse(info.contains("BRACE"), info)
        XCTAssertFalse(info.contains("FLOOR"), info)
    }

    func testExerciseInfoKeepsRangeQualifier() {
        let exercise = Exercise(
            name: "Lunge",
            canonicalName: nil,
            sets: 3,
            reps: "8-10 each leg",
            durationSeconds: nil,
            load: nil,
            restSeconds: 60,
            distance: nil,
            notes: nil,
            focus: nil,
            supersetGroup: nil
        )
        let info = exercise.ddInfoPrescriptionLine
        XCTAssertTrue(info.contains("8–10") || info.contains("8-10"), info)
        XCTAssertTrue(info.uppercased().contains("EACH LEG"), info)
        XCTAssertTrue(info.contains("60S REST") || info.contains("60S"), info)
        XCTAssertFalse(exercise.ddDetailLine.uppercased().contains("EACH LEG"))
    }

    func testRepsRangeKeepsHyphenForStorageButUsesEnDashInSummary() {
        let range = RepsRange(low: 8, high: 12)
        let exercise = EditorV2Exercise(name: "Squat", sets: 3, repsRange: range)

        XCTAssertEqual(range.display, "8-12")
        XCTAssertEqual(exercise.summaryLine, "3 × 8–12")
        XCTAssertEqual(RepsRange.parse("8–12"), range)
    }

    // MARK: - Preview duration

    func testPreviewWorkoutUsesZeroNotExerciseHeuristic() {
        let draft = SocialImportDraft(
            title: "Leg Day",
            sport: "strength",
            platform: .instagram,
            sourceURL: nil,
            exercises: [
                SocialImportExercise(name: "A", sets: 3, reps: 8),
                SocialImportExercise(name: "B", sets: 3, reps: 8),
                SocialImportExercise(name: "C", sets: 3, reps: 8),
                SocialImportExercise(name: "D", sets: 3, reps: 8)
            ],
            blocks: [],
            equipmentEmpty: false
        )
        let preview = draft.toPreviewWorkout()
        XCTAssertEqual(preview.duration, 0)
    }

    // MARK: - Display grouping (read-time, non-mutating)
    //
    // AMA-2395 moved these from DDWorkoutDisplayGrouping to the section layer.
    // The old grouping COLLAPSED consecutive singleton blocks into one section;
    // that is reshaping, and the section layer no longer does it. What still
    // holds: stored blocks are never mutated, named sections survive, and no
    // section invents a duration.

    func testLegacySingletonBlocksEachKeepTheirOwnSection() {
        let bands = bandsFor([
            Block(label: nil, structure: .straight, rounds: 1, exercises: [makeExercise(name: "A", reps: "8")]),
            Block(label: "Block 2", structure: .straight, rounds: 1, exercises: [makeExercise(name: "B", reps: "8")]),
            Block(label: "Block 3", structure: .straight, rounds: 1, exercises: [makeExercise(name: "C", reps: "8")])
        ])
        XCTAssertEqual(bands.count, 3, "three stored blocks render as three sections")
        XCTAssertEqual(bands.map { $0.rows.map(\.name) }, [["A"], ["B"], ["C"]])
        XCTAssertTrue(bands.allSatisfy { !$0.hasHeader }, "generic labels render no heading")
    }

    func testGroupingPreservesNamedSoftSection() {
        let bands = bandsFor([
            Block(label: nil, structure: .straight, rounds: 1, exercises: [makeExercise(name: "A", reps: "8")]),
            Block(
                label: "Finisher",
                structure: .circuit,
                rounds: 5,
                exercises: [makeExercise(name: "Ski", reps: nil, distance: 500)]
            ),
            Block(label: "Cool-down", structure: .straight, rounds: 1, exercises: [makeExercise(name: "B", reps: "8")])
        ])
        XCTAssertEqual(bands.count, 3)
        XCTAssertEqual(bands[0].rows.map(\.name), ["A"])
        // One station is not a circuit, so the label stands on its own.
        XCTAssertEqual(bands[1].title, "FINISHER")
        XCTAssertEqual(bands[2].title, "COOLDOWN")
        XCTAssertEqual(bands[2].kind, .cooldown)
    }

    func testWarmupBlockKeepsItsOwnBandAheadOfTheWork() {
        let bands = bandsFor([
            Block(label: "Warm-up", structure: .straight, rounds: 1, exercises: [makeExercise(name: "Band", reps: "10")]),
            Block(label: nil, structure: .straight, rounds: 1, exercises: [makeExercise(name: "A", reps: "8")]),
            Block(label: "Block 2", structure: .straight, rounds: 1, exercises: [makeExercise(name: "B", reps: "8")])
        ])
        XCTAssertEqual(bands.count, 3, "the two loose blocks stay separate")
        XCTAssertEqual(bands[0].title, "WARM-UP")
        XCTAssertEqual(bands.map { $0.rows.count }, [1, 1, 1])
    }

    func testGroupingDoesNotMutateStoredWorkoutBlocks() {
        let blocks = [
            Block(label: nil, structure: .straight, rounds: 1, exercises: [makeExercise(name: "A", reps: "8")]),
            Block(label: "Block 2", structure: .straight, rounds: 1, exercises: [makeExercise(name: "B", reps: "8")])
        ]
        let workout = Workout(
            id: "w2",
            name: "Legacy",
            sport: .strength,
            duration: 0,
            blocks: blocks,
            source: .instagram
        )
        _ = WorkoutBandGrouping.bands(for: workout)
        XCTAssertEqual(workout.blocks.count, 2)
        XCTAssertNil(workout.blocks[0].label)
        XCTAssertEqual(workout.blocks[1].label, "Block 2")
    }

    /// The old grouping split `workout.duration` across blocks and printed
    /// "~N min". Bands only ever show what the estimator actually derived.
    func testBandTimeIgnoresTheStoredDurationAndNeverPrintsATilde() {
        let workout = Workout(
            id: "w3",
            name: "Legacy",
            sport: .strength,
            duration: 1800,
            blocks: [
                Block(label: nil, structure: .straight, rounds: 1, exercises: [makeExercise(name: "A", reps: "8")]),
                Block(label: "Block 2", structure: .straight, rounds: 1, exercises: [makeExercise(name: "B", reps: "8")])
            ],
            source: .instagram
        )
        let bands = WorkoutBandGrouping.bands(for: workout)
        XCTAssertEqual(bands.count, 2)
        XCTAssertFalse(bands[0].timeLabel.contains("~"), bands[0].timeLabel)
        XCTAssertNil(
            bands[0].title.range(of: #"BLOCK\s*\d"#, options: [.regularExpression, .caseInsensitive]),
            bands[0].title
        )
    }

    private func bandsFor(_ blocks: [Block]) -> [WorkoutBand] {
        WorkoutBandGrouping.bands(
            blocks: blocks,
            estimate: WorkoutDurationEstimator.estimate(blocks: blocks)
        )
    }
}
