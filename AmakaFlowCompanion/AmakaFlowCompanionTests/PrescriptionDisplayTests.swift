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

    // MARK: - AMA-2395 section restyle (1 block = 1 section, no reshape)

    func testSectionsKeepOneBlockPerSectionInSourceOrder() {
        let workout = Workout(
            id: "w1",
            name: "Import",
            sport: .strength,
            duration: 60,
            blocks: [
                Block(label: "Warm-up", structure: .straight, rounds: 1, exercises: [makeExercise(name: "Band", reps: "10")]),
                Block(label: nil, structure: .straight, rounds: 1, exercises: [makeExercise(name: "A", reps: "8")]),
                Block(label: "Block 2", structure: .straight, rounds: 1, exercises: [makeExercise(name: "B", reps: "8")])
            ],
            source: .instagram
        )
        let sections = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].title, "WARM-UP")
        XCTAssertTrue(sections[1].title.isEmpty, "Got title: \(sections[1].title)")
        XCTAssertTrue(sections[2].title.isEmpty, "Placeholder Block N must not render — got \(sections[2].title)")
        XCTAssertEqual(sections.map { $0.exercises.map(\.name) }, [["Band"], ["A"], ["B"]])
        for section in sections {
            XCTAssertFalse(section.note.contains("~"), "Got note: \(section.note)")
        }
    }

    func testSectionsDoNotMutateStoredWorkoutBlocks() {
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
        _ = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(workout.blocks.count, 2)
        XCTAssertNil(workout.blocks[0].label)
        XCTAssertEqual(workout.blocks[1].label, "Block 2")
    }

    func testCircuitTitleUsesStoredStructureNotInventedRotateCopy() {
        let workout = Workout(
            id: "w3",
            name: "Bike ski row",
            sport: .cardio,
            duration: 60,
            blocks: [
                Block(
                    label: nil,
                    structure: .circuit,
                    rounds: 8,
                    exercises: [
                        makeExercise(name: "Assault Bike", reps: nil),
                        makeExercise(name: "Ski Erg", reps: nil),
                    ]
                )
            ],
            source: .manual
        )
        let sections = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "CIRCUIT · 8 ROUNDS")
        XCTAssertFalse(sections[0].title.contains("ROTATE"))
        XCTAssertFalse(sections[0].note.contains("~"))
    }
}
