//
//  WorkoutCaptionPresentationTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2395 — display-only caption collapse (never mutates stored text).
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutCaptionPresentationTests: XCTestCase {

    func testCollapsedStripsHashtagsAndCTALines() {
        let raw = """
        Here's the 45-minute high intensity upper body workout I do every week.
        Save it and give it a go!
        Double tap & Save
        #upperbody #jeffnippard #minmax
        """
        let presented = WorkoutCaptionPresentation.present(raw)
        XCTAssertNotNil(presented)
        XCTAssertEqual(presented?.expanded, raw.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(presented?.collapsed.contains("#upperbody") ?? true)
        XCTAssertFalse(presented?.collapsed.lowercased().contains("save it and give it a go") ?? true)
        XCTAssertFalse(presented?.collapsed.lowercased().contains("double tap") ?? true)
        XCTAssertTrue(presented?.collapsed.contains("45-minute") ?? false)
        XCTAssertTrue(presented?.hasHiddenDetail == true)
    }

    func testExpandedAlwaysPreservesRawCaption() {
        let raw = "Work hard 🔥\n#erg #ski"
        let presented = WorkoutCaptionPresentation.present(raw)
        XCTAssertEqual(presented?.expanded, raw)
        XCTAssertTrue(presented?.hasHiddenDetail == true)
    }

    func testCreatorTimeParsedFromMyTime() {
        let raw = "500m Ski · 500m Row · 1000m Bike × 10. My time: 57.53 — save it and give it a go"
        XCTAssertEqual(WorkoutCaptionPresentation.creatorTimeLabel(from: raw), "57:53")
    }

    func testNilAndBlankYieldNil() {
        XCTAssertNil(WorkoutCaptionPresentation.present(nil))
        XCTAssertNil(WorkoutCaptionPresentation.present("   "))
    }

    func testJeffFixtureCaptionKeepsCreatorTimeSentence() throws {
        #if DEBUG
        let workout = try FixtureLoader.loadFixture(named: "jeff_nippard_upper_body")
        let presented = try XCTUnwrap(WorkoutCaptionPresentation.present(workout.description))
        XCTAssertTrue(presented.collapsed.contains("45-minute"))
        XCTAssertTrue(presented.collapsed.contains("Min-Max Program") || presented.expanded.contains("Min-Max Program"))
        XCTAssertFalse(presented.collapsed.contains("#upperbody"))
        XCTAssertEqual(presented.expanded, workout.description?.trimmingCharacters(in: .whitespacesAndNewlines))
        #else
        throw XCTSkip("FixtureLoader is DEBUG-only")
        #endif
    }
}
