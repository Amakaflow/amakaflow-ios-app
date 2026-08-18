//
//  BuilderV3DescribeItTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2450 — "Describe it" natural-language entry in the exercise picker.
//

import XCTest
@testable import AmakaFlowCompanion

final class BuilderV3DescribeItTests: XCTestCase {

    private func makeSheet(
        mode: BuilderV3ExercisePickerSheet.Mode,
        onAskAmaka: ((String) -> Void)?
    ) -> BuilderV3ExercisePickerSheet {
        BuilderV3ExercisePickerSheet(
            mode: mode,
            onAddExercises: { _ in },
            onDone: {},
            onAskAmaka: onAskAmaka
        )
    }

    func testDescribeItIsOfferedWhenAddingWithAHandler() {
        let sheet = makeSheet(mode: .add, onAskAmaka: { _ in })
        XCTAssertTrue(
            sheet.showsDescribeIt,
            "browse-stage add mode is where the rig puts the NL entry"
        )
    }

    /// Replace is a single swap of one named exercise — describing a workout
    /// there has nothing to attach to.
    func testDescribeItIsHiddenInReplaceMode() {
        let sheet = makeSheet(
            mode: .replace(exerciseID: "abc", exerciseName: "Bench Press"),
            onAskAmaka: { _ in }
        )
        XCTAssertFalse(sheet.showsDescribeIt, "replace mode must not offer Describe it")
    }

    func testDescribeItIsHiddenWithoutAHandlerSoItIsNeverADeadTap() {
        let sheet = makeSheet(mode: .add, onAskAmaka: nil)
        XCTAssertFalse(
            sheet.showsDescribeIt,
            "with no handler wired the card would be a dead tap"
        )
    }

    /// `presentCoachWithQuery` prefills without sending, so an empty seed opens
    /// the coach ready for input. A non-empty seed would put words in the
    /// athlete's mouth.
    func testDescribeItSeedsTheCoachWithNothingToSend() {
        XCTAssertEqual(
            BuilderV3ExercisePickerSheet.describeItSeed,
            "",
            "Describe it must open the coach empty, not pre-typed"
        )
    }
}
