//
//  PrescriptionEditorTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2311 Task 6 — editor seed + ingest range handling.
//

import XCTest
@testable import AmakaFlowCompanion

final class PrescriptionEditorTests: XCTestCase {

    func testIngestDoesNotUseRepsRangeAsLoad() throws {
        let json = """
        {
          "title": "Range day",
          "blocks": [{
            "label": "Main",
            "exercises": [{
              "name": "Squat",
              "sets": 3,
              "reps_range": "8-10"
            }]
          }]
        }
        """.data(using: .utf8)!

        let draft = try SocialImportDraft.fromIngestJSON(
            json,
            platform: .instagram,
            sourceURL: nil,
            equipmentEmpty: false,
            equipmentNote: nil
        )

        let exercise = try XCTUnwrap(draft.exercises.first)
        XCTAssertEqual(exercise.repsRange, "8-10")
        XCTAssertNil(exercise.load)
    }

    func testIngestStructuredRepsRangeDict() throws {
        let json = """
        {
          "title": "Range day",
          "blocks": [{
            "exercises": [{
              "name": "Squat",
              "sets": 3,
              "reps_range": {"low": 8, "high": 10}
            }]
          }]
        }
        """.data(using: .utf8)!

        let draft = try SocialImportDraft.fromIngestJSON(
            json,
            platform: .instagram,
            sourceURL: nil,
            equipmentEmpty: false,
            equipmentNote: nil
        )

        XCTAssertEqual(draft.exercises.first?.repsRange, "8-10")
    }

    func testRepsRangeTextValidation() {
        XCTAssertTrue(RepsRange.isValidRangeText("8-10"))
        XCTAssertTrue(RepsRange.isValidRangeText(" 8 – 10 "))
        XCTAssertFalse(RepsRange.isValidRangeText("as many as possible"))
        XCTAssertFalse(RepsRange.isValidRangeText("8-10 each leg"))

        let parsed = RepsRange.fromRangeText("6-8", preservingQualifier: "each leg")
        XCTAssertEqual(parsed, RepsRange(low: 6, high: 8, qualifier: "each leg"))
    }
}
