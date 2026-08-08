//
//  WatchItemViewModelCTATests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2388: Replace CTA is never demo-gated; draft≠delivered lights it.
//

import XCTest
@testable import AmakaFlowCompanion

private struct StubWatchItemReplacer: WatchItemReplacing {
    let result: Result<Void, WatchItemReplaceError>

    func replace(_ request: WatchItemReplaceRequest) async -> Result<Void, WatchItemReplaceError> {
        result
    }
}

@MainActor
final class WatchItemViewModelCTATests: XCTestCase {
    private var readinessStore: WatchItemReadinessStore!
    private let suiteName = "ama2388.cta.tests"

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        readinessStore = WatchItemReadinessStore(defaults: defaults)
    }

    private func makeVM(
        replacer: (any WatchItemReplacing)? = nil
    ) -> WatchItemViewModel {
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
        return WatchItemViewModel(
            device: .apple,
            workoutID: "w-1",
            title: "Full Body",
            stateLine: "SCHEDULED",
            snapshotPills: ["9 STEPS"],
            baseline: baseline,
            config: config,
            libraryWorkoutID: "w-1",
            libraryWorkoutTitle: "Full Body",
            stepSections: [
                PreviewSection(
                    accent: .work,
                    band: "WORK",
                    tag: nil,
                    steps: [
                        PreviewStep(number: 1, title: "Squat", detail: "3×5", restChip: nil)
                    ]
                )
            ],
            replacer: replacer,
            readinessStore: readinessStore,
            prefsPersister: nil
        )
    }

    func testCTAAvailableWithoutDemoFlag() {
        let vm = makeVM()
        XCTAssertFalse(vm.canReplace)
        vm.setEnabled(.cooldown, true)
        XCTAssertTrue(vm.canReplace)
        XCTAssertEqual(vm.replaceCTATitle(), "Replace on watch · 1 change")
        XCTAssertTrue(vm.applyNote.contains("Saved here"))
    }

    func testReplaceSuccessUpdatesCTAAndPills() async {
        let vm = makeVM(replacer: StubWatchItemReplacer(result: .success(())))
        vm.setEnabled(.cooldown, true)
        await vm.replace()
        XCTAssertEqual(vm.replaceCTATitle(), WatchItemCopy.ctaUpToDate)
        XCTAssertTrue(vm.applyNote.contains("exact copy"))
        XCTAssertTrue(vm.justReplaced)
        XCTAssertNil(vm.lastError)
        XCTAssertEqual(vm.snapshotPills.first, "1 STEPS")
    }

    func testReplaceFailureSetsErrorAndKeepsPending() async {
        let vm = makeVM(
            replacer: StubWatchItemReplacer(result: .failure(.underlying("boom")))
        )
        vm.setEnabled(.cooldown, true)
        await vm.replace()
        XCTAssertEqual(vm.lastError, "boom")
        XCTAssertFalse(vm.justReplaced)
        XCTAssertTrue(vm.canReplace)
        XCTAssertEqual(vm.replaceCTATitle(), "Replace on watch · 1 change")
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
