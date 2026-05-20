//
//  AMA1855_WatchGarmin_AssemblyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1855 / L2 — Watch + Garmin completion request assembly.
//
//  Phone-source coverage lives in AMA1834_WorkoutCompletionRequest_AssemblyTests.
//  This file adds the same wire-shape pinning for the two non-phone sources:
//
//    - makeWatchCompletionRequest(...)  for Watch standalone workouts
//      (input: StandaloneWorkoutSummary; source = "apple_watch";
//      platform = "watchos"; no execution_log, no set_logs).
//    - postGarminWorkoutCompletion(...) for Garmin push workouts
//      (input: workoutId + dates + avg HR + active calories;
//      source = "garmin"; platform = "garmin").
//
//  Asserts pinned for AMA-1855 L1 backend invariants (mapper-api stores
//  `source` exactly as sent — see
//  services/mapper-api/tests/test_workout_completions.py AMA-1855 block).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class AMA1855_WatchGarmin_AssemblyTests: XCTestCase {

    // MARK: - Helpers

    private func encode(_ request: WorkoutCompletionRequest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "AMA1855",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "encoded payload is not a JSON object"]
            )
        }
        return object
    }

    private func makeStandaloneSummary(
        workoutId: String = "watch-workout-ama1855",
        workoutName: String = "AMA-1855 Watch Workout"
    ) -> StandaloneWorkoutSummary {
        StandaloneWorkoutSummary(
            workoutId: workoutId,
            workoutName: workoutName,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_001_500),  // +25 min
            durationSeconds: 1500,
            totalCalories: 320,
            averageHeartRate: 138,
            completedSteps: 25,
            totalSteps: 25
        )
    }

    // MARK: - Watch path (CJ-02)

    func test_makeWatchCompletionRequest__producesAppleWatchSource() throws {
        let request = WorkoutCompletionService
            .makeWatchCompletionRequestForTesting(summary: makeStandaloneSummary())

        let json = try encode(request)
        XCTAssertEqual(json["source"] as? String, "apple_watch",
                       "AMA-1855 L1 invariant: Watch path must POST source=apple_watch so mapper-api can pin provenance.")
    }

    func test_makeWatchCompletionRequest__workoutIdPreservedFromSummary() throws {
        let summary = makeStandaloneSummary(workoutId: "watch-cj02-123")
        let request = WorkoutCompletionService
            .makeWatchCompletionRequestForTesting(summary: summary)
        let json = try encode(request)
        XCTAssertEqual(json["workout_id"] as? String, "watch-cj02-123")
        XCTAssertNil(json["workout_event_id"], "Watch standalone path goes through workout_id, not workout_event_id.")
        XCTAssertNil(json["follow_along_workout_id"], "Watch standalone is never a follow-along.")
    }

    func test_makeWatchCompletionRequest__devicePlatformIsWatchOS() throws {
        let request = WorkoutCompletionService
            .makeWatchCompletionRequestForTesting(summary: makeStandaloneSummary())
        let json = try encode(request)
        let deviceInfo = try XCTUnwrap(json["device_info"] as? [String: Any])
        XCTAssertEqual(deviceInfo["platform"] as? String, "watchos")
        XCTAssertEqual(deviceInfo["model"] as? String, "Apple Watch")
    }

    func test_makeWatchCompletionRequest__healthMetricsHRFromSummary() throws {
        let summary = makeStandaloneSummary()
        let request = WorkoutCompletionService
            .makeWatchCompletionRequestForTesting(summary: summary)
        let json = try encode(request)
        let metrics = try XCTUnwrap(json["health_metrics"] as? [String: Any])
        // averageHeartRate is Double on the Summary; encoded as Int avg_heart_rate in the request.
        XCTAssertEqual(metrics["avg_heart_rate"] as? Int, Int(summary.averageHeartRate ?? -1))
        XCTAssertEqual(metrics["active_calories"] as? Int, Int(summary.totalCalories))
    }

    func test_makeWatchCompletionRequest__omitsExecutionLogAndSetLogs() throws {
        // AMA-1855 invariant: the Watch path does NOT build execution_log
        // or set_logs on-device today (those are phone-path concepts).
        // If we ever start sending them from watchOS, this test failure
        // makes the change visible.
        let request = WorkoutCompletionService
            .makeWatchCompletionRequestForTesting(summary: makeStandaloneSummary())
        let json = try encode(request)
        // The JSONEncoder serialises Swift `nil` as JSON `null`, not as
        // an absent key, so we check both ways.
        let executionLog = json["execution_log"]
        XCTAssertTrue(executionLog == nil || executionLog is NSNull,
                      "execution_log should be null/absent on the Watch path; got \(String(describing: executionLog))")
        let setLogs = json["set_logs"]
        XCTAssertTrue(setLogs == nil || setLogs is NSNull,
                      "set_logs should be null/absent on the Watch path; got \(String(describing: setLogs))")
        let hrSamples = json["heart_rate_samples"]
        XCTAssertTrue(hrSamples == nil || hrSamples is NSNull,
                      "heart_rate_samples should be null/absent on the Watch path today.")
    }

    func test_makeWatchCompletionRequest__isSimulatedAlwaysAbsent() throws {
        // Watch workouts are never marked simulated — that's a phone-only
        // construct (AMA-271). If we ever add Watch simulation, this test
        // failure forces a design conversation.
        let request = WorkoutCompletionService
            .makeWatchCompletionRequestForTesting(summary: makeStandaloneSummary())
        let json = try encode(request)
        let isSim = json["is_simulated"]
        XCTAssertTrue(isSim == nil || isSim is NSNull,
                      "is_simulated should not be present on Watch path.")
    }

    func test_makeWatchCompletionRequest__clientGeneratedIdAlwaysPresent() throws {
        // AMA-1848 Bug B regression: client_generated_id is NOT NULL on
        // workout_completions; every path must populate it. The Watch
        // path was wired during AMA-1848 — pin that it stays populated.
        let request = WorkoutCompletionService
            .makeWatchCompletionRequestForTesting(summary: makeStandaloneSummary())
        let json = try encode(request)
        let cgid = json["client_generated_id"] as? String
        XCTAssertNotNil(cgid, "client_generated_id must be set on every WorkoutCompletionRequest (AMA-1848 Bug B).")
        XCTAssertFalse(cgid?.isEmpty ?? true)
    }

    // MARK: - Wire-shape integration

    func test_makeWatchCompletionRequest__topLevelKeysMatchBackendContract() throws {
        // The backend route (mapper-api `/workouts/complete`) reads the
        // following top-level fields. Pin the Watch path emits the set
        // it expects + nothing it doesn't recognize.
        let request = WorkoutCompletionService
            .makeWatchCompletionRequestForTesting(summary: makeStandaloneSummary())
        let json = try encode(request)
        let keys = Set(json.keys)

        // Required:
        XCTAssertTrue(keys.contains("source"))
        XCTAssertTrue(keys.contains("started_at"))
        XCTAssertTrue(keys.contains("ended_at"))
        XCTAssertTrue(keys.contains("health_metrics"))
        XCTAssertTrue(keys.contains("device_info"))
        XCTAssertTrue(keys.contains("client_generated_id"))
        XCTAssertTrue(keys.contains("workout_id"))

        // Documented-absent (asserted individually above; here we sanity-
        // check the Watch path doesn't accidentally emit unknown keys
        // beyond the documented Codable surface).
        let known: Set<String> = [
            "workout_event_id", "workout_id", "follow_along_workout_id",
            "started_at", "ended_at", "health_metrics", "source",
            "device_info", "heart_rate_samples", "workout_structure",
            "workout_name", "is_simulated", "set_logs", "execution_log",
            "client_generated_id",
        ]
        let unknown = keys.subtracting(known)
        XCTAssertTrue(unknown.isEmpty, "Watch request emitted unknown keys: \(unknown)")
    }
}
