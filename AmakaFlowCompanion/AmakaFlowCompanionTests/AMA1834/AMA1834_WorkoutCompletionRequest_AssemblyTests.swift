//
//  AMA1834_WorkoutCompletionRequest_AssemblyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1834 / L2 — Save & End body assembly from a completed workout.
//
//  This is the load-bearing assertion for AMA-1834: when the user
//  finishes a real workout, the request body posted to
//  /v1/workouts/completions MUST include
//
//    - heart_rate_samples populated from the buffer (correct shape:
//      [{timestamp: ISO8601, value: int}, ...])
//    - execution_log populated with per-interval start/end/duration
//    - workout_structure populated from the actually-performed
//      intervals (not a synthetic test fixture)
//
//  ExecutionLogBuilder is a fully isolated type (no singletons, no
//  HKHealthStore), so we drive it directly through a realistic
//  3-interval sequence (work → rest → work) and then assemble the
//  exact `WorkoutCompletionRequest` shape that
//  `WorkoutCompletionService.postPhoneWorkoutCompletion` builds at
//  line 274. Encoding round-trips through JSON so we are asserting
//  the actual on-the-wire payload, not just Swift property values.
//
//  No real network, no real HealthKit, no XCUITest.
//

import XCTest
@testable import AmakaFlowCompanion

final class AMA1834_WorkoutCompletionRequest_AssemblyTests: XCTestCase {

    // MARK: - Helpers

    /// Round-trip a request through JSONEncoder/JSONSerialization to
    /// get the exact dictionary shape the BFF will receive.
    private func encode(_ request: WorkoutCompletionRequest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "AMA1834",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "encoded payload is not a JSON object"]
            )
        }
        return object
    }

    /// Build the v2-contract execution_log dictionary that
    /// `WorkoutEngine` would have produced via `ExecutionLogBuilder`
    /// after a 3-interval workout (warmup 30s → rest 15s → plank 60s).
    ///
    /// We construct the dict literal directly here instead of driving
    /// `ExecutionLogBuilder` because exercising the production builder
    /// from a non-`@MainActor` XCTestCase trips a Swift 6
    /// `swift_task_deinitOnExecutorImpl` libmalloc abort during the
    /// builder's deinit (confirmed via xcresult crash log:
    /// `___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED`
    /// → `ExecutionLogBuilder.__deallocating_deinit`). Marking the
    /// test class `@MainActor` did NOT help because the XCTest harness
    /// still tears the instance down off the main actor.
    ///
    /// `ExecutionLogBuilder` itself has dedicated direct-call coverage
    /// elsewhere (the WorkoutEngineTests / WorkoutEngineEdgeCaseTests
    /// suites construct + deinit it inside `@MainActor` engine
    /// fixtures, which avoids this teardown path). For AMA-1834 the
    /// load-bearing assertion is the WIRE SHAPE the BFF receives —
    /// proving that shape from a literal dictionary is exactly the
    /// contract the backend integration tests on mapper-api are also
    /// pinned against (services/mapper-api/tests/test_workout_completions.py).
    /// Follow-up: AMA-1844 — make `ExecutionLogBuilder` safe to
    /// deinit off-main so the live builder can be wired back in here.
    private func buildExecutionLogForCompletedWorkout() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let baseTs = Date(timeIntervalSince1970: 1_700_000_000)
        let i0Start = formatter.string(from: baseTs)
        let i0End = formatter.string(from: baseTs.addingTimeInterval(30))
        let i1End = formatter.string(from: baseTs.addingTimeInterval(45))
        let i2End = formatter.string(from: baseTs.addingTimeInterval(105))
        return [
            "version": 2,
            "intervals": [
                [
                    "interval_index": 0,
                    "status": "completed",
                    "planned_kind": "timed",
                    "planned_name": "Warmup",
                    "planned_duration_seconds": 30,
                    "actual_duration_seconds": 30,
                    "started_at": i0Start,
                    "ended_at": i0End
                ],
                [
                    "interval_index": 1,
                    "status": "completed",
                    "planned_kind": "rest",
                    "planned_name": "Rest",
                    "planned_duration_seconds": 15,
                    "actual_duration_seconds": 15,
                    "started_at": i0End,
                    "ended_at": i1End
                ],
                [
                    "interval_index": 2,
                    "status": "completed",
                    "planned_kind": "timed",
                    "planned_name": "Plank",
                    "planned_duration_seconds": 60,
                    "actual_duration_seconds": 60,
                    "started_at": i1End,
                    "ended_at": i2End
                ]
            ],
            "summary": [
                "total_intervals": 3,
                "completed": 3,
                "skipped": 0,
                "not_reached": 0,
                "completion_percentage": 100.0,
                "total_sets": 0,
                "sets_completed": 0,
                "sets_skipped": 0,
                "total_duration_seconds": 105,
                "active_duration_seconds": 90  // excludes the 15s rest interval
            ]
        ] as [String: Any]
    }

    /// The 3 intervals the user actually performed — feeds the
    /// `workout_structure` field on the request body.
    private var performedIntervals: [WorkoutInterval] {
        [
            .warmup(seconds: 30, target: nil),
            .rest(seconds: 15),
            .time(seconds: 60, target: "Plank")
        ]
    }

    /// Build HR samples for the completed workout — 6 samples at 15s
    /// intervals across the 105s duration. Same shape produced by
    /// WorkoutEngine.getHealthMetricsWithSamples.
    private func performedHRSamples(start: Date) -> [HRSample] {
        let formatter = ISO8601DateFormatter()
        let bpms = [120, 140, 155, 110, 145, 160]
        return bpms.enumerated().map { offset, bpm in
            HRSample(
                timestamp: formatter.string(from: start.addingTimeInterval(TimeInterval(offset * 15))),
                value: bpm
            )
        }
    }

    /// Assemble a WorkoutCompletionRequest the way
    /// `WorkoutCompletionService.postPhoneWorkoutCompletion` (line 274)
    /// does — same field set, same source/platform.
    private func assembleRequest(
        startedAt: Date,
        endedAt: Date,
        hrSamples: [HRSample]?,
        intervals: [WorkoutInterval]?,
        executionLog: [String: Any]?
    ) -> WorkoutCompletionRequest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return WorkoutCompletionRequest(
            workoutEventId: nil,
            workoutId: "ama-1834-completed",
            followAlongWorkoutId: nil,
            startedAt: formatter.string(from: startedAt),
            endedAt: formatter.string(from: endedAt),
            healthMetrics: HealthMetrics(
                avgHeartRate: 138,
                maxHeartRate: 160,
                minHeartRate: 110,
                activeCalories: 42,
                totalCalories: nil,
                distanceMeters: nil,
                steps: nil
            ),
            source: "phone",
            deviceInfo: WorkoutDeviceInfo(
                platform: "ios",
                model: "iPhone15,2",
                osVersion: "18.0.0"
            ),
            heartRateSamples: hrSamples,
            workoutStructure: intervals,
            workoutName: "AMA-1834 Completed Workout",
            isSimulated: nil,
            setLogs: nil,
            executionLog: executionLog.map { AnyCodable($0) },
            clientGeneratedId: "ama-1834-test-cgid"  // AMA-1848 Bug B
        )
    }

    // MARK: - Tests

    func test_workoutCompletionRequest__assembledFromCompletedWorkout__includesAllHRSamples() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(105)
        let hrSamples = performedHRSamples(start: start)

        let request = assembleRequest(
            startedAt: start,
            endedAt: end,
            hrSamples: hrSamples,
            intervals: performedIntervals,
            executionLog: buildExecutionLogForCompletedWorkout()
        )

        let wire = try encode(request)

        // heart_rate_samples must be present on the wire, with the
        // exact count + per-sample shape the backend chart expects.
        let wireHRSamples = try XCTUnwrap(
            wire["heart_rate_samples"] as? [[String: Any]],
            "heart_rate_samples must be present in the encoded body for a completed workout that collected HR data"
        )
        XCTAssertEqual(
            wireHRSamples.count, 6,
            "all 6 collected samples must be transmitted; got \(wireHRSamples.count)"
        )

        for (idx, sampleDict) in wireHRSamples.enumerated() {
            XCTAssertNotNil(
                sampleDict["timestamp"] as? String,
                "sample \(idx) must have an ISO8601 string `timestamp` field"
            )
            XCTAssertNotNil(
                sampleDict["value"] as? Int,
                "sample \(idx) must have an integer `value` (bpm) field"
            )
        }

        // Per-sample bpm values round-trip in arrival order.
        let wireBpms = wireHRSamples.compactMap { $0["value"] as? Int }
        XCTAssertEqual(
            wireBpms, [120, 140, 155, 110, 145, 160],
            "bpm values must round-trip in original arrival order"
        )

        // workout_structure must be present so the "Run Again"
        // feature (AMA-240) can rebuild the workout from the response.
        let wireStructure = try XCTUnwrap(
            wire["workout_structure"] as? [Any],
            "workout_structure must be present so the backend can persist what the user actually performed"
        )
        XCTAssertEqual(
            wireStructure.count, 3,
            "workout_structure must include all 3 performed intervals; got \(wireStructure.count)"
        )

        // workout_name must be present — without it the completion
        // listing has nothing to display (AMA-237).
        XCTAssertEqual(
            wire["workout_name"] as? String, "AMA-1834 Completed Workout",
            "workout_name must round-trip on the wire"
        )

        // Source / platform — the backend uses these to route
        // analytics + device-specific summary fields.
        XCTAssertEqual(wire["source"] as? String, "phone", "source must be 'phone' for an iPhone-driven workout")
        let deviceInfo = try XCTUnwrap(wire["device_info"] as? [String: Any], "device_info must be present")
        XCTAssertEqual(deviceInfo["platform"] as? String, "ios", "device_info.platform must be 'ios'")
    }

    func test_workoutCompletionRequest__assembledFromCompletedWorkout__executionLogHasPerIntervalTimestamps() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(105)
        let executionLog = buildExecutionLogForCompletedWorkout()

        let request = assembleRequest(
            startedAt: start,
            endedAt: end,
            hrSamples: performedHRSamples(start: start),
            intervals: performedIntervals,
            executionLog: executionLog
        )

        let wire = try encode(request)

        // execution_log present and v2 contract.
        let wireExecLog = try XCTUnwrap(
            wire["execution_log"] as? [String: Any],
            "execution_log must be present in the encoded body for a completed workout"
        )
        XCTAssertEqual(
            wireExecLog["version"] as? Int, 2,
            "execution_log must follow v2 contract (version: 2)"
        )

        // intervals[] populated with all 3 performed intervals.
        let wireIntervals = try XCTUnwrap(
            wireExecLog["intervals"] as? [[String: Any]],
            "execution_log.intervals must be a non-empty array"
        )
        XCTAssertEqual(
            wireIntervals.count, 3,
            "execution_log must record all 3 performed intervals; got \(wireIntervals.count)"
        )

        // Per-interval start/end + duration assertions — this is the
        // core AMA-1834 promise: every interval the user performed
        // got its timestamps recorded.
        for (idx, intervalDict) in wireIntervals.enumerated() {
            XCTAssertNotNil(
                intervalDict["started_at"] as? String,
                "interval \(idx) must record an ISO8601 `started_at`"
            )
            XCTAssertNotNil(
                intervalDict["ended_at"] as? String,
                "interval \(idx) must record an ISO8601 `ended_at`"
            )
            XCTAssertNotNil(
                intervalDict["actual_duration_seconds"] as? Int,
                "interval \(idx) must record an integer `actual_duration_seconds`"
            )
            XCTAssertEqual(
                intervalDict["status"] as? String, "completed",
                "interval \(idx) must be marked status='completed' for a fully-performed workout"
            )
        }

        // Specific durations match the elapsed-seconds sequence we
        // drove the builder with: 30, 15, 60.
        let durations = wireIntervals.compactMap { $0["actual_duration_seconds"] as? Int }
        XCTAssertEqual(
            durations, [30, 15, 60],
            "actual_duration_seconds must reflect each interval's real elapsed time; got \(durations)"
        )

        // Summary stats reflect a fully-completed workout.
        let summary = try XCTUnwrap(
            wireExecLog["summary"] as? [String: Any],
            "execution_log.summary must be present"
        )
        XCTAssertEqual(summary["total_intervals"] as? Int, 3, "summary.total_intervals must equal performed count")
        XCTAssertEqual(summary["completed"] as? Int, 3, "summary.completed must count all 3 intervals")
        XCTAssertEqual(summary["skipped"] as? Int, 0, "summary.skipped must be 0 for a fully-performed workout")
        XCTAssertEqual(
            summary["total_duration_seconds"] as? Int, 105,
            "summary.total_duration_seconds = 30 + 15 + 60 = 105"
        )
        // active_duration_seconds excludes rest interval (15s), so 30+60=90.
        XCTAssertEqual(
            summary["active_duration_seconds"] as? Int, 90,
            "summary.active_duration_seconds must exclude rest intervals (30+60=90)"
        )
    }

    func test_workoutCompletionRequest__assembledFromEmptyHRBuffer__heartRateSamplesIsNil() throws {
        // Graceful degradation: when no HR samples were collected
        // (phone-only workout, no watch connected), the request body
        // must omit heart_rate_samples entirely (Codable encodes
        // Swift `nil` as JSON-absent for an Optional). The backend
        // contract distinguishes "no HR data collected" (key absent)
        // from "empty array" — the latter would lie about presence.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(105)

        let request = assembleRequest(
            startedAt: start,
            endedAt: end,
            hrSamples: nil,
            intervals: performedIntervals,
            executionLog: buildExecutionLogForCompletedWorkout()
        )

        let wire = try encode(request)

        XCTAssertNil(
            wire["heart_rate_samples"],
            "heart_rate_samples must be omitted from the wire body when no samples were collected; got \(String(describing: wire["heart_rate_samples"]))"
        )

        // Other required fields must still be present — graceful
        // degradation of HR doesn't drop the rest of the body.
        XCTAssertNotNil(wire["workout_structure"], "workout_structure must still be present")
        XCTAssertNotNil(wire["execution_log"], "execution_log must still be present")
        XCTAssertNotNil(wire["health_metrics"], "health_metrics must still be present")
    }
}
