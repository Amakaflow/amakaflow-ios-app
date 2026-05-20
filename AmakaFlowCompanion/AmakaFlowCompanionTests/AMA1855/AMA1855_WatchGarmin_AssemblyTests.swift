//
//  AMA1855_WatchGarmin_AssemblyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1855 / L2 — Watch + Garmin completion request assembly.
//
//  Phone-source coverage lives in AMA1834_WorkoutCompletionRequest_AssemblyTests.
//  This file adds the same wire-shape pinning for the Watch path today:
//
//    - makeWatchCompletionRequest(...)  for Watch standalone workouts
//      (input: StandaloneWorkoutSummary; source = "apple_watch";
//      platform = "watchos"; no execution_log, no set_logs).
//
//  Garmin path: AMA-1855 follow-up exposed
//  `makeGarminCompletionRequestForTesting` as a DEBUG-only seam
//  mirroring the Watch helper. The Garmin tests below pin the same
//  wire-shape invariants for the "garmin" / "garmin" source/platform
//  combo, including the AMA-1867 `workout_name` round-trip.
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
        // The fixture always sets averageHeartRate non-nil — unwrap explicitly so a
        // future fixture change to nil fails LOUDLY here rather than silently passing
        // against a `?? -1` sentinel. The nil-HR encoding path is its own (TODO) test.
        let avgHR = try XCTUnwrap(summary.averageHeartRate, "fixture must set averageHeartRate non-nil for this test")
        XCTAssertEqual(metrics["avg_heart_rate"] as? Int, Int(avgHR))
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
        // Whether an optional encodes as JSON `null` or is omitted
        // depends on each type's Encodable impl (some properties on
        // WorkoutCompletionRequest are omitted when nil; others encode
        // as null). Accept either for these fields.
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
        let cgid = try XCTUnwrap(
            json["client_generated_id"] as? String,
            "client_generated_id must be set on every WorkoutCompletionRequest (AMA-1848 Bug B)."
        )
        XCTAssertFalse(cgid.isEmpty)
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

        // started_at / ended_at must serialise as ISO8601 UTC strings
        // (mapper-api parses with `datetime.fromisoformat`, which
        // accepts the trailing `Z` only on Python ≥ 3.11).
        let isoPattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$"#
        let startedAt = try XCTUnwrap(json["started_at"] as? String)
        let endedAt = try XCTUnwrap(json["ended_at"] as? String)
        XCTAssertNotNil(startedAt.range(of: isoPattern, options: .regularExpression),
                        "started_at must be ISO8601 UTC; got \(startedAt)")
        XCTAssertNotNil(endedAt.range(of: isoPattern, options: .regularExpression),
                        "ended_at must be ISO8601 UTC; got \(endedAt)")

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

    // MARK: - Garmin path (CJ-03)

    private func makeGarminRequest(
        workoutId: String = "garmin-workout-ama1855",
        avgHeartRate: Int? = 142,
        activeCalories: Int? = 410,
        workoutName: String? = nil,
        deviceModel: String? = "Garmin Forerunner 965"
    ) -> WorkoutCompletionRequest {
        WorkoutCompletionService.makeGarminCompletionRequestForTesting(
            workoutId: workoutId,
            startedAt: Date(timeIntervalSince1970: 1_700_010_000),
            endedAt: Date(timeIntervalSince1970: 1_700_011_800),  // +30 min
            avgHeartRate: avgHeartRate,
            activeCalories: activeCalories,
            workoutStructure: nil,
            workoutName: workoutName,
            deviceModel: deviceModel
        )
    }

    func test_makeGarminCompletionRequest__producesGarminSource() throws {
        let json = try encode(makeGarminRequest())
        XCTAssertEqual(json["source"] as? String, "garmin",
                       "AMA-1855 L1 invariant: Garmin path must POST source=garmin so mapper-api pins provenance.")
    }

    func test_makeGarminCompletionRequest__devicePlatformIsGarmin() throws {
        let json = try encode(makeGarminRequest(deviceModel: "Garmin Forerunner 965"))
        let deviceInfo = try XCTUnwrap(json["device_info"] as? [String: Any])
        XCTAssertEqual(deviceInfo["platform"] as? String, "garmin")
        XCTAssertEqual(deviceInfo["model"] as? String, "Garmin Forerunner 965")
    }

    func test_makeGarminCompletionRequest__workoutIdPreserved() throws {
        let json = try encode(makeGarminRequest(workoutId: "garmin-cj03-789"))
        XCTAssertEqual(json["workout_id"] as? String, "garmin-cj03-789")
        // iOS today only drives Garmin via workout_id; event_id / follow_along
        // are server-resolved if needed. Pin "iOS sends workout_id only" so a
        // future change becomes visible.
        let evt = json["workout_event_id"]
        XCTAssertTrue(evt == nil || evt is NSNull,
                      "iOS Garmin path should not send workout_event_id; got \(String(describing: evt))")
        let follow = json["follow_along_workout_id"]
        XCTAssertTrue(follow == nil || follow is NSNull)
    }

    func test_makeGarminCompletionRequest__healthMetricsFromArgs() throws {
        let request = makeGarminRequest(avgHeartRate: 150, activeCalories: 560)
        let json = try encode(request)
        let metrics = try XCTUnwrap(json["health_metrics"] as? [String: Any])
        XCTAssertEqual(metrics["avg_heart_rate"] as? Int, 150)
        XCTAssertEqual(metrics["active_calories"] as? Int, 560)
    }

    func test_makeGarminCompletionRequest__omitsExecutionLogAndSetLogs() throws {
        // Garmin watches don't surface phone-side execution_log / set_logs.
        // If we ever start sending them, this test failure forces a design
        // conversation about how Garmin will track per-set weight (AMA-288).
        let json = try encode(makeGarminRequest())
        let executionLog = json["execution_log"]
        XCTAssertTrue(executionLog == nil || executionLog is NSNull)
        let setLogs = json["set_logs"]
        XCTAssertTrue(setLogs == nil || setLogs is NSNull)
        let hrSamples = json["heart_rate_samples"]
        XCTAssertTrue(hrSamples == nil || hrSamples is NSNull,
                      "Garmin path doesn't ship time-series HR samples today (AMA-1855).")
    }

    func test_makeGarminCompletionRequest__isSimulatedAlwaysAbsent() throws {
        // Garmin workouts are never marked simulated (phone-only construct).
        let json = try encode(makeGarminRequest())
        let isSim = json["is_simulated"]
        XCTAssertTrue(isSim == nil || isSim is NSNull,
                      "is_simulated should not be present on Garmin path.")
    }

    func test_makeGarminCompletionRequest__clientGeneratedIdAlwaysPresent() throws {
        // AMA-1848 Bug B regression guard — same as Watch path.
        let json = try encode(makeGarminRequest())
        let cgid = try XCTUnwrap(
            json["client_generated_id"] as? String,
            "client_generated_id must be set on every WorkoutCompletionRequest (AMA-1848 Bug B)."
        )
        XCTAssertFalse(cgid.isEmpty)
    }

    func test_makeGarminCompletionRequest__workoutNameRoundTripsWhenProvided() throws {
        // AMA-1867 round-trip: when iOS supplies a workout_name (Garmin push
        // with a recognizable title), the field must reach the wire so
        // mapper-api can persist it into workout_completions.workout_name.
        let json = try encode(makeGarminRequest(workoutName: "Sunday long run"))
        XCTAssertEqual(json["workout_name"] as? String, "Sunday long run",
                       "AMA-1867: client-supplied workout_name must reach the wire.")
    }

    func test_makeGarminCompletionRequest__workoutNameAbsentWhenNotProvided() throws {
        // Pin the negative side: when iOS doesn't supply a name (the common
        // path), the field is null/absent so mapper-api falls back to the
        // join-resolved name on read.
        let json = try encode(makeGarminRequest(workoutName: nil))
        let name = json["workout_name"]
        XCTAssertTrue(name == nil || name is NSNull,
                      "workout_name should be null/absent when not supplied; got \(String(describing: name))")
    }

    func test_makeGarminCompletionRequest__topLevelKeysMatchBackendContract() throws {
        let json = try encode(makeGarminRequest(workoutName: "Sunday long run"))
        let keys = Set(json.keys)

        // Required:
        XCTAssertTrue(keys.contains("source"))
        XCTAssertTrue(keys.contains("started_at"))
        XCTAssertTrue(keys.contains("ended_at"))
        XCTAssertTrue(keys.contains("health_metrics"))
        XCTAssertTrue(keys.contains("device_info"))
        XCTAssertTrue(keys.contains("client_generated_id"))
        XCTAssertTrue(keys.contains("workout_id"))
        XCTAssertTrue(keys.contains("workout_name"))

        // ISO8601 timestamps (same shape as Watch path; mapper-api parses
        // with datetime.fromisoformat).
        let isoPattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$"#
        let startedAt = try XCTUnwrap(json["started_at"] as? String)
        let endedAt = try XCTUnwrap(json["ended_at"] as? String)
        XCTAssertNotNil(startedAt.range(of: isoPattern, options: .regularExpression),
                        "started_at must be ISO8601 UTC; got \(startedAt)")
        XCTAssertNotNil(endedAt.range(of: isoPattern, options: .regularExpression),
                        "ended_at must be ISO8601 UTC; got \(endedAt)")

        // Sanity: no unknown keys beyond the documented Codable surface.
        let known: Set<String> = [
            "workout_event_id", "workout_id", "follow_along_workout_id",
            "started_at", "ended_at", "health_metrics", "source",
            "device_info", "heart_rate_samples", "workout_structure",
            "workout_name", "is_simulated", "set_logs", "execution_log",
            "client_generated_id",
        ]
        let unknown = keys.subtracting(known)
        XCTAssertTrue(unknown.isEmpty, "Garmin request emitted unknown keys: \(unknown)")
    }
}
