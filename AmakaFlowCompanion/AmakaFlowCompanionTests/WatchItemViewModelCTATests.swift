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
    private var toast: DDToastCenter!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ama2388.cta.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        readinessStore = WatchItemReadinessStore(defaults: defaults)
        toast = DDToastCenter()
    }

    override func tearDown() {
        if let suiteName {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        readinessStore = nil
        toast = nil
        suiteName = nil
        super.tearDown()
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
            toast: toast,
            readinessStore: readinessStore,
            prefsPersister: nil
        )
    }

    func testCTAAvailableWithoutDemoFlag() async {
        let vm = makeVM()
        XCTAssertFalse(vm.canReplace)
        XCTAssertEqual(vm.changeCount, 0)
        vm.setEnabled(.cooldown, true)
        XCTAssertEqual(vm.changeCount, 1)
        XCTAssertTrue(vm.canReplace)
        XCTAssertEqual(vm.replaceCTATitle(), WatchItemCopy.replaceCTA(changeCount: 1))
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
        // Cooldown was toggled on → delivered preview rebuilds (WORK + COOLDOWN).
        XCTAssertEqual(vm.snapshotPills.first, WatchItemCopy.stepsPill(count: vm.stepCount))
        XCTAssertGreaterThanOrEqual(vm.stepCount, 2)
        XCTAssertTrue(vm.stepSections.contains { $0.accent == .cooldown })
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
        XCTAssertEqual(vm.replaceCTATitle(), WatchItemCopy.replaceCTA(changeCount: 1))
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
