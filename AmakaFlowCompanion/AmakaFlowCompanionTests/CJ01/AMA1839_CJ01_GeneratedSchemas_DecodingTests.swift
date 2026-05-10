//
//  AMA1839_CJ01_GeneratedSchemas_DecodingTests.swift
//  AmakaFlowCompanionTests
//
//  CJ-01 / L2 — Response mapping for the Verify-persistence step.
//
//  After Save & End the app re-fetches /v1/workouts/planned (typed
//  PlannedListResponse) and inspects the WorkoutCompletionResponse from
//  the POST. These tests pin the wire shapes so a future BFF schema
//  regeneration that drops a key fails at L2 instead of CJ-01 L3/L4.
//
//  Note: per AMA-1826 / AMA-1828 the generated client lives in
//  AmakaFlow/Generated and exposes Components.Schemas.* publicly.
//

import XCTest
@testable import AmakaFlowCompanion

final class AMA1839_CJ01_GeneratedSchemas_DecodingTests: XCTestCase {

    private func decoder() -> JSONDecoder { JSONDecoder() }

    // MARK: - PlannedListResponse (used during Verify step)

    func test_plannedListResponse__nonEmptyList__decodesAllPlannedWorkouts() throws {
        let json = """
        {
          "workouts": [
            {"id": "wk-1", "userId": "user-cj01"},
            {"id": "wk-2", "userId": "user-cj01"}
          ]
        }
        """.data(using: .utf8)!

        let decoded = try decoder().decode(Components.Schemas.PlannedListResponse.self, from: json)
        XCTAssertEqual(decoded.workouts.count, 2, "PlannedListResponse must decode every planned workout in the array")
        XCTAssertEqual(decoded.workouts.first?.id, "wk-1", "first planned workout id must round-trip")
        XCTAssertEqual(decoded.workouts.first?.userId, "user-cj01",
                       "PlannedWorkout.userId is camelCase on the wire (AMA-1826 — preserved alias from mapper-api)")
    }

    func test_plannedListResponse__emptyList__decodesAsEmptyArray() throws {
        let json = #"{"workouts": []}"#.data(using: .utf8)!
        let decoded = try decoder().decode(Components.Schemas.PlannedListResponse.self, from: json)
        XCTAssertEqual(decoded.workouts.count, 0,
                       "empty workouts array must decode as zero-length, not throw — covers fresh-account Reopen path")
    }

    func test_plannedListResponse__missingWorkoutsKey__throwsDecodingError() {
        let json = "{}".data(using: .utf8)!
        XCTAssertThrowsError(try decoder().decode(Components.Schemas.PlannedListResponse.self, from: json),
                             "PlannedListResponse.workouts is required; missing key must throw, not silently return empty")
    }

    // MARK: - WorkoutCompletionResponse (returned by POST /v1/workouts/completions)

    func test_workoutCompletionResponse__successTrue__decodesSuccessFlag() throws {
        let json = #"{"success": true}"#.data(using: .utf8)!
        let decoded = try decoder().decode(Components.Schemas.WorkoutCompletionResponse.self, from: json)
        XCTAssertTrue(decoded.success, "WorkoutCompletionResponse.success must round-trip true")
    }

    func test_workoutCompletionResponse__successFalse__decodesSuccessFlag() throws {
        let json = #"{"success": false}"#.data(using: .utf8)!
        let decoded = try decoder().decode(Components.Schemas.WorkoutCompletionResponse.self, from: json)
        XCTAssertFalse(decoded.success, "WorkoutCompletionResponse.success must round-trip false")
    }

    func test_workoutCompletionResponse__missingSuccessKey__throwsDecodingError() {
        let json = "{}".data(using: .utf8)!
        XCTAssertThrowsError(try decoder().decode(Components.Schemas.WorkoutCompletionResponse.self, from: json),
                             "success is non-optional in the generated schema; missing key must throw")
    }

    // MARK: - WorkoutCompletionSummary (echoed back after Save & End)

    func test_workoutCompletionSummary__durationFormattedPresent__decodes() throws {
        let json = #"{"duration_formatted": "32:14"}"#.data(using: .utf8)!
        let decoded = try decoder().decode(Components.Schemas.WorkoutCompletionSummary.self, from: json)
        XCTAssertEqual(decoded.durationFormatted, "32:14",
                       "WorkoutCompletionSummary.duration_formatted (snake_case wire / camelCase Swift) must round-trip")
    }

    // MARK: - Hand-coded WorkoutCompletionResponse (still in use per AMA-1831)

    func test_handCodedWorkoutCompletionResponse__bothCompletionIdAndId__resolvesPreferringCompletionId() throws {
        let json = #"{"completion_id": "cmp-1", "id": "fallback", "status": "ok", "success": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkoutCompletionResponse.self, from: json)
        XCTAssertEqual(decoded.resolvedCompletionId, "cmp-1",
                       "resolvedCompletionId must prefer completion_id over id when both are present")
        XCTAssertEqual(decoded.success, true, "success flag must round-trip on the hand-coded response")
    }

    func test_handCodedWorkoutCompletionResponse__onlyIdField__fallsBackToId() throws {
        let json = #"{"id": "alt-completion-id"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkoutCompletionResponse.self, from: json)
        XCTAssertEqual(decoded.resolvedCompletionId, "alt-completion-id",
                       "when completion_id is missing, resolvedCompletionId must fall back to id")
    }

    func test_handCodedWorkoutCompletionResponse__neitherIdField__resolvesToUnknownSentinel() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkoutCompletionResponse.self, from: json)
        XCTAssertEqual(decoded.resolvedCompletionId, "unknown",
                       "when both id fields are missing, resolvedCompletionId must return the documented \"unknown\" sentinel")
    }
}
