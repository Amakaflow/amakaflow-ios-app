//
//  AMA1834_HKInjectionHelper.swift
//  AmakaFlowCompanionTests
//
//  AMA-1834 — HealthKit heart-rate injection helper for L4 Maestro E2E.
//
//  This is NOT a product test — it is a test-process fixture that seeds
//  the iOS Simulator's HealthKit store with heart-rate samples so that
//  the AmakaFlow app, running concurrently in a Maestro-driven session,
//  sees realistic HR data during a full-workout E2E flow.
//
//  Why XCUITest and not a Swift CLI / healthd_write:
//    - `xcrun simctl spawn <udid> healthd_write` does not exist in
//      Xcode 26 (CoreSimulator 1051.x). There is no public command-line
//      API for writing to the sim's HealthKit store.
//    - HKHealthStore.save() requires a process that (a) has the
//      HealthKit entitlement and (b) has requested HK authorization.
//      In the test process, authorization can be granted imperatively;
//      in a plain Swift CLI it requires a UI permission dialog.
//    - XCTHealthKit (Stanford BDHGroup, already an SPM dep) provides
//      the correct authorization flow for the test process.
//
//  Usage (from hk-inject.sh):
//    xcodebuild test-without-building \
//      -scheme AmakaFlowCompanion \
//      -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj \
//      -destination "platform=iOS Simulator,id=87AA26D0-..." \
//      -only-testing:AmakaFlowCompanionTests/AMA1834_HKInjectionHelper \
//      HK_WORK_SECONDS=15 HK_REST_SECONDS=10 HK_INTERVALS=3 \
//      -parallel-testing-enabled NO
//
//  Configuration via env vars (passed as xcodebuild build settings which
//  flow into ProcessInfo.environment in the test process):
//    HK_WORK_SECONDS  — work interval duration per interval (default: 15)
//    HK_REST_SECONDS  — rest interval duration per interval (default: 10)
//    HK_INTERVALS     — number of intervals (default: 3)
//

import XCTest
import HealthKit

final class AMA1834_HKInjectionHelper: XCTestCase {

    // MARK: - Config from env

    private var workSeconds: Int {
        Int(ProcessInfo.processInfo.environment["HK_WORK_SECONDS"] ?? "15") ?? 15
    }
    private var restSeconds: Int {
        Int(ProcessInfo.processInfo.environment["HK_REST_SECONDS"] ?? "10") ?? 10
    }
    private var intervals: Int {
        Int(ProcessInfo.processInfo.environment["HK_INTERVALS"] ?? "3") ?? 3
    }

    // MARK: - HKHealthStore

    private let store = HKHealthStore()

    // MARK: - Authorization

    override func setUpWithError() throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw XCTSkip("HealthKit not available on this device/sim")
        }
        // Authorization is handled non-fatally in the test body.
        // We do NOT wait on requestAuthorization here because on a fresh sim
        // the callback is never invoked (no UI to present, no prior grant).
        // The test proceeds and save() returns a graceful auth error.
    }

    // MARK: - Main injection test

    /// Seeds the sim HealthKit store with a realistic HR ramp for the
    /// full-workout Maestro flow. Work intervals ramp 60→160 BPM;
    /// rest intervals ramp 160→90 BPM.
    ///
    /// This test is intended to run CONCURRENTLY with the Maestro flow
    /// (hk-inject.sh fires it in the background before the flow starts).
    func testInjectWorkoutHeartRateSamples() throws {
        let hrType = HKQuantityType(.heartRate)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        var allSamples: [HKQuantitySample] = []
        var elapsed: TimeInterval = 0
        let now = Date()

        for i in 1...intervals {
            // Work interval: 60 → 160 BPM
            let workStart = now.addingTimeInterval(elapsed)
            for s in 0..<workSeconds {
                let bpm = 60.0 + (160.0 - 60.0) * Double(s) / Double(max(workSeconds - 1, 1))
                let sampleStart = workStart.addingTimeInterval(Double(s))
                let sampleEnd = sampleStart.addingTimeInterval(1)
                let quantity = HKQuantity(unit: bpmUnit, doubleValue: bpm)
                let sample = HKQuantitySample(
                    type: hrType,
                    quantity: quantity,
                    start: sampleStart,
                    end: sampleEnd,
                    metadata: [
                        HKMetadataKeyWasUserEntered: false,
                        "AMA1834_interval": i,
                        "AMA1834_phase": "work"
                    ]
                )
                allSamples.append(sample)
                print("[AMA1834-HKInject] WORK interval=\(i) t=+\(s)s bpm=\(Int(bpm.rounded()))")
            }
            elapsed += TimeInterval(workSeconds)

            // Rest interval: 160 → 90 BPM
            let restStart = now.addingTimeInterval(elapsed)
            for s in 0..<restSeconds {
                let bpm = 160.0 + (90.0 - 160.0) * Double(s) / Double(max(restSeconds - 1, 1))
                let sampleStart = restStart.addingTimeInterval(Double(s))
                let sampleEnd = sampleStart.addingTimeInterval(1)
                let quantity = HKQuantity(unit: bpmUnit, doubleValue: bpm)
                let sample = HKQuantitySample(
                    type: hrType,
                    quantity: quantity,
                    start: sampleStart,
                    end: sampleEnd,
                    metadata: [
                        HKMetadataKeyWasUserEntered: false,
                        "AMA1834_interval": i,
                        "AMA1834_phase": "rest"
                    ]
                )
                allSamples.append(sample)
                print("[AMA1834-HKInject] REST interval=\(i) t=+\(s)s bpm=\(Int(bpm.rounded()))")
            }
            elapsed += TimeInterval(restSeconds)
        }

        // Request authorization inline (fire-and-forget) then immediately
        // attempt save. On a fresh sim requestAuthorization may never call
        // back (no UI), so we don't wait for it — we let save() tell us
        // the real status. This is intentionally best-effort for L4 evidence.
        store.requestAuthorization(toShare: [HKQuantityType(.heartRate)], read: []) { _, _ in }

        // Save all samples in one batch.
        // Non-fatal on authorization errors: on a fresh sim the test runner
        // process may not have HK write access (the permission is per-bundle-ID
        // and requires prior user interaction). The injection is best-effort for
        // L4 evidence — the Maestro flow continues regardless, and subsequent
        // runs on a sim that has previously granted access will succeed.
        let saveExpectation = expectation(description: "HK save \(allSamples.count) samples")
        store.save(allSamples) { success, error in
            if let error = error {
                // Code 5 = authorization not determined, Code 4 = missing entitlement.
                // Both are expected on a fresh sim; log and continue.
                let nsError = error as NSError
                if nsError.domain == "com.apple.healthkit" && (nsError.code == 4 || nsError.code == 5) {
                    print("[AMA1834-HKInject] WARN: HK auth not granted for test bundle (code=\(nsError.code)). " +
                          "Grant HealthKit access to AmakaFlowCompanionTests in the Health app on the sim, " +
                          "then re-run. Samples were prepared but not persisted to the HK store.")
                } else {
                    XCTFail("HK save failed with unexpected error: \(error)")
                }
            } else {
                XCTAssertTrue(success, "HKHealthStore.save should succeed when authorized")
                print("[AMA1834-HKInject] DONE. Saved \(allSamples.count) samples over \(Int(elapsed))s (\(self.intervals) intervals)")
            }
            saveExpectation.fulfill()
        }
        wait(for: [saveExpectation], timeout: 30)
    }
}
