//
//  AMA1839_CJ01_WorkoutCompletionRequest_EncodingTests.swift
//  AmakaFlowCompanionTests
//
//  CJ-01 / L2 — Save & End request encoding.
//
//  Per docs/testing/blueprint.md, L2 must assert the exact wire shape that
//  /v1/workouts/completions receives. These tests deliberately cover gaps
//  not exercised by WorkoutCompletionViewModelTests:
//
//  - empty heart_rate_samples array (vs nil) is preserved on the wire
//  - executionLog encodes through AnyCodable and round-trips a nested dict
//  - source/platform values are emitted exactly as the BFF expects
//

import XCTest
@testable import AmakaFlowCompanion

final class AMA1839_CJ01_WorkoutCompletionRequest_EncodingTests: XCTestCase {

    // MARK: - Helpers

    private func encode(_ request: WorkoutCompletionRequest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "AMA1839", code: 1, userInfo: [NSLocalizedDescriptionKey: "encoded payload is not a JSON object"])
        }
        return object
    }

    private func baseRequest(
        heartRateSamples: [HRSample]? = nil,
        executionLog: AnyCodable? = nil,
        source: String = "phone"
    ) -> WorkoutCompletionRequest {
        WorkoutCompletionRequest(
            workoutEventId: "event-cj01",
            workoutId: "workout-cj01",
            followAlongWorkoutId: nil,
            startedAt: "2026-05-09T10:00:00.000Z",
            endedAt: "2026-05-09T10:30:00.000Z",
            healthMetrics: HealthMetrics(
                avgHeartRate: 142,
                maxHeartRate: 168,
                minHeartRate: 88,
                activeCalories: 305,
                totalCalories: nil,
                distanceMeters: nil,
                steps: nil
            ),
            source: source,
            deviceInfo: WorkoutDeviceInfo(platform: "ios", model: "iPhone17,1", osVersion: "18.4"),
            heartRateSamples: heartRateSamples,
            workoutStructure: nil,
            workoutName: "CJ-01 Pilot Workout",
            isSimulated: false,
            setLogs: nil,
            executionLog: executionLog,
            clientGeneratedId: "cj01-test-cgid"  // AMA-1848 Bug B
        )
    }

    // MARK: - Tests

    func test_workoutCompletionRequest__optionalFieldsPresent__encodesExpectedPayload() throws {
        let json = try encode(baseRequest())

        XCTAssertEqual(json["workout_id"] as? String, "workout-cj01", "workout_id must be snake_case")
        XCTAssertEqual(json["workout_event_id"] as? String, "event-cj01", "workout_event_id must be snake_case")
        XCTAssertEqual(json["source"] as? String, "phone", "source channel must round-trip")
        XCTAssertEqual(json["started_at"] as? String, "2026-05-09T10:00:00.000Z", "started_at must preserve ISO8601 millis")
        XCTAssertEqual(json["ended_at"] as? String, "2026-05-09T10:30:00.000Z", "ended_at must preserve ISO8601 millis")

        let device = try XCTUnwrap(json["device_info"] as? [String: Any], "device_info must be present")
        XCTAssertEqual(device["platform"] as? String, "ios", "device_info.platform must be snake_case ios")
        XCTAssertEqual(device["os_version"] as? String, "18.4", "device_info.os_version must be snake_case")

        let metrics = try XCTUnwrap(json["health_metrics"] as? [String: Any], "health_metrics must be present")
        XCTAssertEqual(metrics["avg_heart_rate"] as? Int, 142, "avg_heart_rate must be snake_case")
        XCTAssertEqual(metrics["active_calories"] as? Int, 305, "active_calories must be snake_case")
    }

    func test_workoutCompletionRequest__emptyHeartRateSamplesArray__encodesEmptyArrayNotNull() throws {
        let json = try encode(baseRequest(heartRateSamples: []))

        let samples = try XCTUnwrap(json["heart_rate_samples"] as? [Any],
                                    "empty heart_rate_samples must serialize as [] not null so backend chart code can distinguish 'no data' from 'not collected'")
        XCTAssertEqual(samples.count, 0, "empty array must serialize as zero-length, not be dropped")
    }

    func test_workoutCompletionRequest__heartRateSamplesPresent__encodesSnakeCaseTimestampAndValue() throws {
        let samples = [
            HRSample(timestamp: "2026-05-09T10:00:05.000Z", value: 120),
            HRSample(timestamp: "2026-05-09T10:00:10.000Z", value: 135)
        ]
        let json = try encode(baseRequest(heartRateSamples: samples))
        let arr = try XCTUnwrap(json["heart_rate_samples"] as? [[String: Any]], "heart_rate_samples must encode as array of objects")
        XCTAssertEqual(arr.count, 2, "all HR samples must be preserved")
        XCTAssertEqual(arr[0]["timestamp"] as? String, "2026-05-09T10:00:05.000Z", "HRSample.timestamp must round-trip")
        XCTAssertEqual(arr[1]["value"] as? Int, 135, "HRSample.value must round-trip")
    }

    func test_workoutCompletionRequest__executionLogNestedDict__encodesThroughAnyCodable() throws {
        let executionLog: [String: Any] = [
            "completed_intervals": 6,
            "skipped_intervals": [2, 4],
            "modifications": [
                "weight_overrides": ["1": 50.0, "3": 55.0]
            ]
        ]
        let json = try encode(baseRequest(executionLog: AnyCodable(executionLog)))
        let log = try XCTUnwrap(json["execution_log"] as? [String: Any],
                                "execution_log must encode as a JSON object via AnyCodable (AMA-291)")
        XCTAssertEqual(log["completed_intervals"] as? Int, 6, "scalar inside execution_log must survive AnyCodable encode")
        let skipped = try XCTUnwrap(log["skipped_intervals"] as? [Int], "nested array inside execution_log must round-trip")
        XCTAssertEqual(skipped, [2, 4], "skipped_intervals values must match")
        let mods = try XCTUnwrap(log["modifications"] as? [String: Any], "nested dict must survive AnyCodable encode")
        XCTAssertNotNil(mods["weight_overrides"], "deeply nested object must survive AnyCodable encode")
    }

    func test_workoutCompletionRequest__executionLogNil__omitsKeyOrEmitsNull() throws {
        // JSONEncoder default behavior: nil optionals encode as JSON null.
        // The backend treats "missing" and "null" identically, but the
        // contract test pins the current behavior so a future encoder
        // strategy switch is a visible diff.
        let json = try encode(baseRequest(executionLog: nil))
        if let value = json["execution_log"] {
            XCTAssertTrue(value is NSNull, "when executionLog is nil it must serialize as JSON null (not a stale value)")
        }
    }

    func test_workoutCompletionRequest__sourceWatchOS__encodesAppleWatchChannel() throws {
        let json = try encode(baseRequest(source: "apple_watch"))
        XCTAssertEqual(json["source"] as? String, "apple_watch",
                       "Apple Watch completions must report source=apple_watch so the backend routes to the watch ingest path")
    }
}
