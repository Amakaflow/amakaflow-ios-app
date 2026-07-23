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

    // MARK: - AMA-2312 always-editable + user provenance

    func testSetsOnlyDraftShowsStrengthEditors() {
        let draft = EditorV2Exercise(name: "Triceps Press Downs", sets: 2, reps: nil)
        XCTAssertTrue(draft.showsStrengthPrescriptionEditors)
    }

    func testFirstNilRepsInteractionStampsUserProvenance() {
        var draft = EditorV2Exercise(name: "Triceps Press Downs", sets: 2, reps: nil)
        XCTAssertNil(draft.reps)
        draft.reps = PrescriptionDefaults.defaultReps
        draft.stampUser("reps")
        XCTAssertEqual(draft.reps, 10)
        XCTAssertEqual(draft.fieldProvenance["reps"], .user)

        let social = EditorV2Session(title: "t", groups: [:], exercises: [draft])
            .toSocialImportBlocks()
            .flatMap(\.exercises)
            .first
        XCTAssertEqual(social?.fieldProvenance?["reps"], "user")
        XCTAssertEqual(social?.reps, 10)

        let encoded = APIService.provenanceExercise(from: social!)
        let provenance = encoded["field_provenance"] as? [String: String]
        XCTAssertEqual(provenance?["reps"], "user")
    }

    func testCommittedRangeDoesNotStampWhenUnchanged() {
        let original = RepsRange(low: 8, high: 10, qualifier: nil)
        var draft = EditorV2Exercise(
            name: "Squat",
            sets: 3,
            repsRange: original,
            fieldProvenance: ["reps_range": .inferred]
        )
        draft.commitRepRange(from: "8-10", useRangeMode: true)
        XCTAssertEqual(draft.repsRange, original)
        XCTAssertEqual(draft.fieldProvenance["reps_range"], .inferred)
    }

    func testCommittedRangeStampsOnlyWhenChanged() {
        var draft = EditorV2Exercise(
            name: "Squat",
            sets: 3,
            repsRange: RepsRange(low: 8, high: 10),
            fieldProvenance: ["reps_range": .inferred]
        )
        draft.commitRepRange(from: "6-8", useRangeMode: true)
        XCTAssertEqual(draft.repsRange, RepsRange(low: 6, high: 8))
        XCTAssertNil(draft.reps)
        XCTAssertEqual(draft.fieldProvenance["reps_range"], .user)
    }

    func testCommittedRangeKeepsPrescriptionOnInvalidInput() {
        let original = RepsRange(low: 8, high: 10)
        var draft = EditorV2Exercise(
            name: "Squat",
            sets: 3,
            reps: 10,
            repsRange: original,
            fieldProvenance: ["reps_range": .inferred]
        )
        draft.commitRepRange(from: "", useRangeMode: true)
        XCTAssertEqual(draft.repsRange, original)
        XCTAssertEqual(draft.reps, 10)
        XCTAssertEqual(draft.fieldProvenance["reps_range"], .inferred)
    }
}
