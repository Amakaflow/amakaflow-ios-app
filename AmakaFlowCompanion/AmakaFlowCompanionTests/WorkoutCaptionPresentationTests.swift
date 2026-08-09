//
//  WorkoutCaptionPresentationTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2395 — the caption is provenance, not the page body. Collapsed view
//  drops hashtags and engagement bait; expanded is always the untouched
//  original (we never rewrite what the creator wrote).
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutCaptionPresentationTests: XCTestCase {

    /// The real "Erg Workout For Time" caption from the dogfood screenshots.
    private let ergCaption = """
    500m Ski · 500m Row · 1000m Bike × 10 rounds.
    My time: 57.53 — it gets spicy very quick 🔥
    Save it and give it a go!
    Double tap & Save
    #erg #workout #fortime #ski #row #bike
    """

    func testCollapsedDropsHashtagLinesAndCallsToAction() {
        let collapsed = WorkoutCaptionPresentation.collapsed(ergCaption)

        XCTAssertFalse(collapsed.contains("#"), collapsed)
        XCTAssertFalse(collapsed.lowercased().contains("save it and give it a go"), collapsed)
        XCTAssertFalse(collapsed.lowercased().contains("double tap"), collapsed)

        // The part that actually describes the workout survives intact.
        XCTAssertTrue(collapsed.contains("500m Ski · 500m Row · 1000m Bike × 10 rounds."), collapsed)
        XCTAssertTrue(collapsed.contains("My time: 57.53"), collapsed)
    }

    func testExpandedIsAlwaysTheUntouchedOriginal() {
        XCTAssertEqual(
            WorkoutCaptionPresentation.expanded(ergCaption),
            ergCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertTrue(WorkoutCaptionPresentation.expanded(ergCaption).contains("#erg"))
    }

    func testTrailingHashtagsAreTrimmedButMidSentenceOnesSurvive() {
        XCTAssertEqual(
            WorkoutCaptionPresentation.collapsed("Leg day finisher #legday #quads"),
            "Leg day finisher"
        )
        XCTAssertEqual(
            WorkoutCaptionPresentation.collapsed("Try the #hyrox style circuit today"),
            "Try the #hyrox style circuit today"
        )
    }

    func testToggleOnlyOfferedWhenSomethingIsActuallyHidden() {
        XCTAssertTrue(WorkoutCaptionPresentation.hasHiddenDetail(ergCaption))
        XCTAssertFalse(WorkoutCaptionPresentation.hasHiddenDetail("Simple upper body session"))
        XCTAssertFalse(WorkoutCaptionPresentation.hasHiddenDetail(nil))
        XCTAssertFalse(WorkoutCaptionPresentation.hasHiddenDetail(""))
    }

    func testEmptyAndHashtagOnlyCaptionsCollapseToNothing() {
        XCTAssertEqual(WorkoutCaptionPresentation.collapsed(nil), "")
        XCTAssertEqual(WorkoutCaptionPresentation.collapsed("#gym #fit"), "")
    }
}
