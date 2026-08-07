//
//  WatchItemChangeTrackerTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2386: distinct-row change counter.
//

import XCTest
@testable import AmakaFlowCompanion

final class WatchItemChangeTrackerTests: XCTestCase {
    private let baseline = WatchItemReadinessState(
        mobilityEnabled: true,
        warmupsEnabled: true,
        restEnabled: true,
        cooldownEnabled: false
    )

    private let config = WatchItemConfigState(
        mobilityActivities: [EnrichmentActivityPref(name: "Jump rope", durationSec: 120)],
        cooldownActivities: WorkoutEnrichmentMutations.defaultCooldownActivities(),
        perExerciseRamps: [],
        restOpen: true,
        restSec: 60
    )

    func testUntouchedIsZero() {
        let tracker = WatchItemChangeTracker(baseline: baseline, config: config)
        XCTAssertEqual(tracker.changeCount, 0)
        XCTAssertFalse(tracker.hasChanges)
    }

    func testToggleIncrementsAndRevertDecrements() {
        var tracker = WatchItemChangeTracker(baseline: baseline, config: config)
        tracker.setEnabled(.cooldown, true)
        XCTAssertEqual(tracker.changeCount, 1)
        tracker.setEnabled(.mobility, false)
        XCTAssertEqual(tracker.changeCount, 2)
        tracker.setEnabled(.cooldown, false)
        XCTAssertEqual(tracker.changeCount, 1)
        tracker.setEnabled(.mobility, true)
        XCTAssertEqual(tracker.changeCount, 0)
    }

    func testConfigEditCountsAsChange() {
        var tracker = WatchItemChangeTracker(baseline: baseline, config: config)
        tracker.updateConfig { $0.restOpen = false }
        XCTAssertEqual(tracker.changeCount, 1)
        tracker.updateConfig { $0.restOpen = true }
        XCTAssertEqual(tracker.changeCount, 0)
    }

    func testMarkSucceededResetsBaseline() {
        var tracker = WatchItemChangeTracker(baseline: baseline, config: config)
        tracker.setEnabled(.cooldown, true)
        tracker.updateConfig {
            $0.mobilityActivities.append(EnrichmentActivityPref(name: "Rower"))
        }
        XCTAssertEqual(tracker.changeCount, 2)
        tracker.markSucceeded()
        XCTAssertEqual(tracker.changeCount, 0)
        XCTAssertTrue(tracker.draft.cooldownEnabled)
        XCTAssertTrue(tracker.baseline.cooldownEnabled)
        XCTAssertEqual(tracker.draftConfig.mobilityActivities.count, 2)
    }
}
