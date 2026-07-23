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

    // MARK: - Display collapse (read-time, non-mutating)

    func testCollapseLegacySingletonBlocksIntoOneSection() {
        let blocks = [
            Block(label: nil, structure: .straight, rounds: 1, exercises: [makeExercise(name: "A", reps: "8")]),
            Block(label: "Block 2", structure: .straight, rounds: 1, exercises: [makeExercise(name: "B", reps: "8")]),
            Block(label: "Block 3", structure: .straight, rounds: 1, exercises: [makeExercise(name: "C", reps: "8")])
        ]
        let collapsed = DDWorkoutDisplayGrouping.collapseStraightSetSingletons(blocks)
        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed[0].label, "Main")
        XCTAssertEqual(collapsed[0].exercises.map(\.name), ["A", "B", "C"])
    }

    func testCollapsePreservesNamedSoftSection() {
        let finisher = Block(
            label: "Finisher",
            structure: .circuit,
            rounds: 5,
            exercises: [makeExercise(name: "Ski", reps: nil, distance: 500)]
        )
        let blocks = [
            Block(label: nil, structure: .straight, rounds: 1, exercises: [makeExercise(name: "A", reps: "8")]),
            finisher,
            Block(label: "Cool-down", structure: .straight, rounds: 1, exercises: [makeExercise(name: "B", reps: "8")])
        ]
        let collapsed = DDWorkoutDisplayGrouping.collapseStraightSetSingletons(blocks)
        XCTAssertEqual(collapsed.count, 3)
        XCTAssertEqual(collapsed[0].exercises.map(\.name), ["A"])
        XCTAssertEqual(collapsed[1].label, "Finisher")
        XCTAssertEqual(collapsed[2].label, "Cool-down")
    }

    func testSectionsSuppressMainTitleWhenSoleStraightSetContainer() {
        let workout = Workout(
            id: "w1",
            name: "Import",
            sport: .strength,
            duration: 0,
            blocks: [
                Block(label: "Warm-up", structure: .straight, rounds: 1, exercises: [makeExercise(name: "Band", reps: "10")]),
                Block(label: nil, structure: .straight, rounds: 1, exercises: [makeExercise(name: "A", reps: "8")]),
                Block(label: "Block 2", structure: .straight, rounds: 1, exercises: [makeExercise(name: "B", reps: "8")])
            ],
            source: .instagram
        )
        let sections = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title.lowercased(), "warm-up")
        XCTAssertTrue(sections[1].title.isEmpty, "Got title: \(sections[1].title)")
        XCTAssertTrue(sections[1].note.isEmpty)
        XCTAssertEqual(sections[1].exercises.count, 2)
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

    func testSectionNoteOmitsFakeMinutesForStraightMain() {
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
        let sections = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(sections.count, 1)
        XCTAssertFalse(sections[0].note.contains("MIN"))
        XCTAssertFalse(sections[0].note.contains("min"))
    }
}
