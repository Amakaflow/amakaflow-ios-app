//
//  EditorV2WheelLayoutTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2443 slice 5 — TRACK selector, wheel columns, distance target family.
//

import XCTest
@testable import AmakaFlowCompanion

final class EditorV2WheelLayoutTests: XCTestCase {

    // MARK: - The three-wheel rule

    func testNoTrackAndWeightCombinationExceedsThreeWheels() {
        for track in EditorV2EditTargetKind.allCases {
            for weightOn in [false, true] {
                let columns = EditorV2WheelLayout.columns(track: track, weightOn: weightOn)
                XCTAssertLessThanOrEqual(
                    columns.count,
                    EditorV2WheelLayout.maxColumns,
                    "\(track) weight=\(weightOn) produced \(columns.count) wheels"
                )
            }
        }
    }

    func testWeightColumnAppearsExactlyWhenWeightIsOn() {
        for track in EditorV2EditTargetKind.allCases {
            XCTAssertFalse(
                EditorV2WheelLayout.columns(track: track, weightOn: false).contains(.weight),
                "\(track) showed a weight wheel with weight off"
            )
            XCTAssertEqual(
                EditorV2WheelLayout.columns(track: track, weightOn: true).last,
                .weight,
                "\(track) did not put weight last"
            )
        }
    }

    func testColumnsPerTrack() {
        XCTAssertEqual(EditorV2WheelLayout.columns(track: .reps, weightOn: false), [.sets, .reps])
        XCTAssertEqual(EditorV2WheelLayout.columns(track: .timed, weightOn: false), [.sets, .seconds])
        XCTAssertEqual(EditorV2WheelLayout.columns(track: .cals, weightOn: false), [.sets, .calories])
        XCTAssertEqual(EditorV2WheelLayout.columns(track: .range, weightOn: false), [.sets, .range])
        XCTAssertEqual(EditorV2WheelLayout.columns(track: .open, weightOn: false), [])
    }

    /// A 400 m row is one effort, not four — distance drops SETS (rig line 606).
    func testDistanceDropsTheSetsWheelSoWeightStillFits() {
        XCTAssertEqual(EditorV2WheelLayout.columns(track: .distance, weightOn: false), [.meters])
        XCTAssertEqual(
            EditorV2WheelLayout.columns(track: .distance, weightOn: true),
            [.meters, .weight]
        )
    }

    /// Maestro (`e2e/maestro/ama-2379-edit-sheet-v2.yaml`) addresses these by name,
    /// so the stepper→wheel swap must not rename them.
    func testAccessibilityIdentifiersSurviveTheStepperToWheelSwap() {
        XCTAssertEqual(EditorV2WheelColumn.sets.accessibilityIdentifier, "af_exsheet_sets")
        XCTAssertEqual(EditorV2WheelColumn.reps.accessibilityIdentifier, "af_exsheet_reps")
        XCTAssertEqual(EditorV2WheelColumn.seconds.accessibilityIdentifier, "af_exsheet_work")
        XCTAssertEqual(EditorV2WheelColumn.calories.accessibilityIdentifier, "af_exsheet_calories")
        XCTAssertEqual(EditorV2WheelColumn.weight.accessibilityIdentifier, "af_exsheet_weight")
        XCTAssertEqual(EditorV2WheelColumn.meters.accessibilityIdentifier, "af_exsheet_meters")
        XCTAssertEqual(EditorV2WheelColumn.range.accessibilityIdentifier, "af_exsheet_range")
    }

    // MARK: - A wheel always offers the value it is bound to

    func testOffGridSelectionJoinsTheOfferedValues() {
        let grid = Array(stride(from: 5, through: 100, by: 5))
        let offered = EditorV2WheelValues.offering(grid, including: 47)
        XCTAssertTrue(offered.contains(47), "an off-grid saved value had no row to select")
        XCTAssertEqual(offered, offered.sorted(), "inserting 47 broke wheel order")
        XCTAssertEqual(offered.count, grid.count + 1)
    }

    func testSelectionAboveAndBelowTheGridStillGetsARow() {
        let grid = Array(stride(from: 20, through: 2_000, by: 20))
        XCTAssertEqual(EditorV2WheelValues.offering(grid, including: 5_000).last, 5_000)
        XCTAssertEqual(EditorV2WheelValues.offering(grid, including: 5).first, 5)
    }

    func testOnGridSelectionIsNotDuplicated() {
        let grid = Array(stride(from: 5, through: 100, by: 5))
        XCTAssertEqual(EditorV2WheelValues.offering(grid, including: 45), grid)
    }

    func testFractionalWeightOffTheTwoPointFiveGridStillGetsARow() {
        let grid = stride(from: 0.0, through: 300.0, by: 2.5).map { $0 }
        let offered = EditorV2WheelValues.offering(grid, including: 61.0)
        XCTAssertTrue(offered.contains(61.0))
        XCTAssertEqual(offered, offered.sorted())
    }

    // MARK: - Distance target family

    func testDistanceExerciseOpensOnTheDistanceTrack() {
        let exercise = EditorV2Exercise(name: "Ski", distanceMeters: 1_000)
        let memory = EditorV2EditTargetMemory(exercise: exercise)
        XCTAssertEqual(memory.kind, .distance)
        XCTAssertEqual(memory.meters, 1_000)
    }

    func testCommittingDistanceWritesMetersAndClearsOtherFamilies() {
        var exercise = EditorV2Exercise(name: "Ski", sets: 3, reps: 10)
        var memory = EditorV2EditTargetMemory(exercise: exercise)
        memory.select(.distance)
        memory.setMeters(500)
        memory.apply(to: &exercise)

        XCTAssertEqual(exercise.distanceMeters, 500)
        XCTAssertNil(exercise.reps)
        XCTAssertNil(exercise.repsRange)
        XCTAssertNil(exercise.durationSeconds)
        XCTAssertNil(exercise.calories)
        XCTAssertFalse(exercise.openGoal)
        XCTAssertEqual(exercise.fieldProvenance["distance_meters"], .user)
    }

    func testSwitchingTrackAwayAndBackKeepsEachFamilysValue() {
        let exercise = EditorV2Exercise(name: "Row", sets: 3, reps: 12)
        var memory = EditorV2EditTargetMemory(exercise: exercise)
        memory.setReps(15)
        memory.select(.distance)
        memory.setMeters(800)
        memory.select(.timed)
        memory.setWorkSeconds(90)
        memory.select(.reps)

        XCTAssertEqual(memory.reps, 15)
        XCTAssertEqual(memory.meters, 800)
        XCTAssertEqual(memory.workSeconds, 90)

        var committed = exercise
        memory.apply(to: &committed)
        XCTAssertEqual(committed.reps, 15)
        XCTAssertNil(committed.distanceMeters)
        XCTAssertNil(committed.durationSeconds)
    }

    // MARK: - Which chips a given exercise offers

    func testPlainExerciseOffersOnlyTheCalmFourChips() {
        let memory = EditorV2EditTargetMemory(
            exercise: EditorV2Exercise(name: "Bench Press", sets: 4, reps: 8)
        )
        XCTAssertEqual(memory.visibleKinds, [.reps, .timed, .distance, .open])
    }

    func testLegacyFamiliesStayReachableForTheExercisesThatUseThem() {
        var ranged = EditorV2Exercise(name: "Curls", sets: 3)
        ranged.repsRange = RepsRange(low: 8, high: 12)
        XCTAssertTrue(EditorV2EditTargetMemory(exercise: ranged).visibleKinds.contains(.range))

        let burned = EditorV2Exercise(name: "Assault Bike", calories: 20)
        XCTAssertTrue(EditorV2EditTargetMemory(exercise: burned).visibleKinds.contains(.cals))
    }

    func testALegacyFamilyStaysOfferedAfterSwitchingAwayFromIt() {
        var ranged = EditorV2Exercise(name: "Curls", sets: 3)
        ranged.repsRange = RepsRange(low: 8, high: 12)
        var memory = EditorV2EditTargetMemory(exercise: ranged)
        memory.select(.reps)
        XCTAssertTrue(
            memory.visibleKinds.contains(.range),
            "switching away from Range hid the only way back to it"
        )
    }
}
