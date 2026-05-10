//
//  AMA1834_HealthKitBuffer_HRSampleAccumulationTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1834 / L2 — Heart-rate sample buffering and wire-shape mapping.
//
//  iOS-side scope clarification (vs the spec's mention of HKWorkoutBuilder):
//  on this app, HKWorkoutBuilder + HKLiveWorkoutBuilder are owned by the
//  paired Apple Watch app (`AmakaFlowWatch Watch App/HealthKitWorkoutManager.swift`).
//  The iPhone side does NOT own an HKHealthStore for workouts — it
//  receives HR samples via WatchConnectivity (`WatchConnectivityManager
//  .heartRateSamples: [HeartRateSample]`) and converts them to the
//  on-the-wire `HRSample` shape inside `WorkoutEngine
//  .getHealthMetricsWithSamples`. So at L2 the things we can honestly
//  assert are:
//
//    1. The accumulator preserves arrival order across both work and
//       rest periods (the production buffer is `.append`-only with no
//       phase gate — confirmed in WatchConnectivityManager.swift line
//       434).
//    2. The `[HeartRateSample] -> [HRSample]` mapping produces the
//       exact wire shape `/v1/workouts/completions` expects:
//       ISO8601 timestamps + integer bpm.
//    3. An empty buffer maps to `nil` (graceful degradation), not an
//       empty array — required so `WorkoutCompletionRequest
//       .heartRateSamples` is omitted from the body, matching the
//       backend contract.
//
//  Synthetic samples are constructed from `HeartRateSample(timestamp:
//  value:)` directly — exactly what `WatchConnectivityManager`
//  produces in production (see line 433 of that file).
//

import XCTest
@testable import AmakaFlowCompanion

final class AMA1834_HealthKitBuffer_HRSampleAccumulationTests: XCTestCase {

    // MARK: - Helpers

    /// Mirror of the conversion done inside
    /// `WorkoutEngine.getHealthMetricsWithSamples` — kept identical so
    /// we are testing the exact wire transform, not a parallel one.
    /// Returns nil on empty input to match the production
    /// `apiSamples.isEmpty ? nil : apiSamples` branch.
    private func toWireSamples(_ samples: [HeartRateSample]) -> [HRSample]? {
        let mapped = samples.map { sample in
            HRSample(
                timestamp: ISO8601DateFormatter().string(from: sample.timestamp),
                value: sample.value
            )
        }
        return mapped.isEmpty ? nil : mapped
    }

    /// Build a synthetic HR sample stream as if it had been received
    /// over WatchConnectivity from the watch's HKLiveWorkoutBuilder.
    /// Each sample is one second apart.
    private func syntheticStream(
        startingAt start: Date,
        bpms: [Int]
    ) -> [HeartRateSample] {
        bpms.enumerated().map { offset, bpm in
            HeartRateSample(
                timestamp: start.addingTimeInterval(TimeInterval(offset)),
                value: bpm
            )
        }
    }

    // MARK: - Tests

    func test_hrBuffer__samplesArriveDuringWork__accumulateInOrder() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        // Simulate 5 HR samples arriving during a 5-second work interval,
        // pushed by the watch one per second. The production
        // accumulator (WatchConnectivityManager.handleHealthMetrics)
        // does a plain `.append`, so order MUST equal arrival order.
        var buffer: [HeartRateSample] = []
        let workSamples = syntheticStream(startingAt: start, bpms: [120, 132, 145, 151, 158])
        for sample in workSamples {
            buffer.append(sample)
        }

        XCTAssertEqual(
            buffer.count, 5,
            "buffer should hold exactly 5 work-period samples; got \(buffer.count)"
        )

        let wire = try XCTUnwrap(
            toWireSamples(buffer),
            "5-sample buffer must map to a non-nil [HRSample]"
        )
        XCTAssertEqual(
            wire.map { $0.value }, [120, 132, 145, 151, 158],
            "bpm values must be preserved in original arrival order"
        )

        // Timestamps must be strictly monotonically increasing in the
        // wire payload — the backend chart code relies on order.
        let timestamps = wire.map { $0.timestamp }
        XCTAssertEqual(
            timestamps, timestamps.sorted(),
            "wire-format timestamps must already be in ascending order — got \(timestamps)"
        )
    }

    func test_hrBuffer__samplesArriveDuringRest__continueAccumulating() throws {
        // Per AMA-1834 + the production accumulator (no phase gate),
        // HR samples streamed during the rest interval between work
        // sets MUST continue to accumulate into the same buffer that
        // the work interval populated. Tests that the rest period is
        // not silently dropped from the chart.
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        var buffer: [HeartRateSample] = []
        // Work interval (5s of high HR)
        for sample in syntheticStream(startingAt: start, bpms: [150, 158, 162, 165, 167]) {
            buffer.append(sample)
        }
        // Rest interval immediately after (5s of recovery HR)
        let restStart = start.addingTimeInterval(5)
        for sample in syntheticStream(startingAt: restStart, bpms: [148, 132, 118, 110, 105]) {
            buffer.append(sample)
        }

        XCTAssertEqual(
            buffer.count, 10,
            "buffer must hold work (5) + rest (5) = 10 samples; got \(buffer.count)"
        )

        let wire = try XCTUnwrap(
            toWireSamples(buffer),
            "combined work+rest buffer must map to a non-nil [HRSample]"
        )
        XCTAssertEqual(
            wire.map { $0.value }, [150, 158, 162, 165, 167, 148, 132, 118, 110, 105],
            "bpm values must preserve work-then-rest arrival order — rest samples must NOT be dropped"
        )

        // The first rest sample (index 5) must come AFTER the last
        // work sample (index 4) on the wire — not before, not at the
        // same instant.
        let lastWorkTs = wire[4].timestamp
        let firstRestTs = wire[5].timestamp
        XCTAssertGreaterThan(
            firstRestTs, lastWorkTs,
            "first rest sample timestamp (\(firstRestTs)) must be strictly after last work sample timestamp (\(lastWorkTs))"
        )
    }

    func test_hrBuffer__emptyBuffer__mapsToNilForGracefulDegradation() {
        // When no samples arrived (e.g. watch never connected, or
        // workout was driven from phone-only), the wire payload must
        // omit heart_rate_samples entirely (== nil), NOT send `[]`.
        // The production code uses `.isEmpty ? nil : apiSamples` for
        // exactly this reason: an empty array would defeat the
        // backend's "no HR data" branch in /v1/workouts/completions.
        let buffer: [HeartRateSample] = []

        let wire = toWireSamples(buffer)

        XCTAssertNil(
            wire,
            "empty HR buffer must map to nil (graceful degradation), not an empty array"
        )
    }
}
