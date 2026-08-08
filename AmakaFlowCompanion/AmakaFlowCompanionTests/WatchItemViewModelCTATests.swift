//
//  WatchItemViewModelCTATests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2388: Replace CTA is never demo-gated; draft≠delivered lights it.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WatchItemViewModelCTATests: XCTestCase {
    func testCTAAvailableWithoutDemoFlag() {
        let baseline = WatchItemReadinessState(
            mobilityEnabled: true,
            warmupsEnabled: true,
            restEnabled: true,
            cooldownEnabled: false
        )
        let config = WatchItemConfigState(
            mobilityActivities: [],
            cooldownActivities: [],
            perExerciseRamps: [],
            restOpen: true,
            restSec: 60
        )
        let vm = WatchItemViewModel(
            device: .apple,
            workoutID: "w-1",
            title: "Full Body",
            stateLine: "SCHEDULED",
            snapshotPills: ["9 STEPS"],
            baseline: baseline,
            config: config,
            libraryWorkoutID: "w-1",
            libraryWorkoutTitle: "Full Body",
            prefsPersister: nil
        )
        XCTAssertFalse(vm.canReplace)
        vm.setEnabled(.cooldown, true)
        XCTAssertTrue(vm.canReplace)
        XCTAssertEqual(vm.replaceCTATitle(), "Replace on watch · 1 change")
        XCTAssertTrue(vm.applyNote.contains("Saved here"))
    }

    func testTrackerDraftSeedCountsAsEdited() {
        let baseline = WatchItemReadinessState(
            mobilityEnabled: true,
            warmupsEnabled: true,
            restEnabled: true,
            cooldownEnabled: false
        )
        var draft = baseline
        draft.cooldownEnabled = true
        let config = WatchItemConfigState(
            mobilityActivities: [],
            cooldownActivities: [],
            perExerciseRamps: [],
            restOpen: true,
            restSec: 60
        )
        var tracker = WatchItemChangeTracker(
            baseline: baseline,
            config: config,
            draft: draft,
            draftConfig: config
        )
        XCTAssertEqual(tracker.changeCount, 1)
        XCTAssertTrue(tracker.isChanged(.cooldown))
    }
}
