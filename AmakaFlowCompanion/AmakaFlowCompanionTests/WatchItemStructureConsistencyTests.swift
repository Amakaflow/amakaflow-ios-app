//
//  WatchItemStructureConsistencyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2390: Watch Item steps/pills match scheduled plan structure; no ghost
//  EDITED from demo placeholders when the user has not changed readiness.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WatchItemStructureConsistencyTests: XCTestCase {
    private var readinessStore: WatchItemReadinessStore!
    private var linkStore: AppleScheduledWorkoutLinkStore!
    private var readinessSuite: String!
    private var linkSuite: String!

    override func setUp() {
        super.setUp()
        readinessSuite = "ama2390.readiness.\(UUID().uuidString)"
        linkSuite = "ama2390.links.\(UUID().uuidString)"
        let readinessDefaults = UserDefaults(suiteName: readinessSuite)!
        let linkDefaults = UserDefaults(suiteName: linkSuite)!
        readinessDefaults.removePersistentDomain(forName: readinessSuite)
        linkDefaults.removePersistentDomain(forName: linkSuite)
        readinessStore = WatchItemReadinessStore(defaults: readinessDefaults)
        linkStore = AppleScheduledWorkoutLinkStore(defaults: linkDefaults)
    }

    override func tearDown() {
        if let readinessSuite {
            UserDefaults(suiteName: readinessSuite)?.removePersistentDomain(forName: readinessSuite)
        }
        if let linkSuite {
            UserDefaults(suiteName: linkSuite)?.removePersistentDomain(forName: linkSuite)
        }
        readinessStore = nil
        linkStore = nil
        super.tearDown()
    }

    private var bikeSkiRowPlanJSON: Data {
        Data("""
        {
          "title": "Bike ski row",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            {
              "kind": "repeat",
              "reps": 8,
              "intervals": [
                { "kind": "work", "name": "Assault Bike", "seconds": 180 },
                { "kind": "work", "name": "Ski Erg", "seconds": 180 },
                { "kind": "work", "name": "Rowing Machine", "seconds": 180 },
                { "kind": "work", "name": "Spin / Indoor Bike", "seconds": 180 }
              ]
            }
          ]
        }
        """.utf8)
    }

    func testAppleFactoryUsesCachedPlanJSONNotDemoSteps() {
        linkStore.record(
            planID: "plan-bike",
            workoutID: "lib-bike",
            title: "Bike ski row",
            planJSON: bikeSkiRowPlanJSON
        )
        let row = WorkoutScheduleRow(
            id: WorkoutScheduleRowID(
                planID: "plan-bike",
                date: DateComponents(year: 2026, month: 8, day: 8, hour: 17, minute: 35)
            ),
            title: "Bike ski row",
            dateComponents: DateComponents(year: 2026, month: 8, day: 8, hour: 17, minute: 35),
            scheduledAt: Date(),
            isComplete: false
        )
        let vm = WatchItemViewModel.apple(
            row: row,
            linkStore: linkStore,
            readinessStore: readinessStore,
            library: [("lib-bike", "Bike ski row")],
            prefs: .defaults
        )
        XCTAssertEqual(vm.stepSections.count, 1)
        XCTAssertEqual(vm.stepSections[0].band, "Circuit")
        XCTAssertEqual(vm.stepSections[0].tag, "8 ROUNDS")
        XCTAssertEqual(vm.stepSections[0].steps.count, 4)
        XCTAssertFalse(vm.stepSections.flatMap(\.steps).contains { $0.title.contains("Bench") })
        XCTAssertEqual(vm.snapshotPills.first, WatchItemCopy.stepsPill(count: 4))
        XCTAssertEqual(vm.workoutID, "lib-bike")
        XCTAssertEqual(vm.applePlanID, "plan-bike")
        XCTAssertEqual(vm.changeCount, 0)
    }

    /// Send-as-is / no prefs → Watch Item must not invent MOBILITY / TIMED REST.
    func testAppleFactoryWithoutPrefsMirrorsPlanNotStandingDefaults() {
        let sections = WatchItemViewModel.resolvedStepSections(
            stepSections: [],
            planJSON: bikeSkiRowPlanJSON,
            title: "Bike ski row"
        )
        let seeded = WatchItemViewModel.seed(
            storeKey: "lib-bike",
            title: "Bike ski row",
            isApple: true,
            prefs: nil,
            readinessStore: readinessStore,
            deliveredStepTotal: sections.reduce(0) { $0 + $1.steps.count },
            stepSections: sections
        )
        XCTAssertEqual(sections[0].tag, "8 ROUNDS")
        XCTAssertFalse(seeded.draft.mobilityEnabled)
        XCTAssertFalse(seeded.draft.warmupsEnabled)
        XCTAssertFalse(seeded.draft.restEnabled)
        XCTAssertFalse(seeded.draft.cooldownEnabled)
        XCTAssertEqual(seeded.pills, [WatchItemCopy.stepsPill(count: 4)])
        let tracker = WatchItemChangeTracker(
            baseline: seeded.baseline,
            config: seeded.baselineConfig,
            draft: seeded.draft,
            draftConfig: seeded.draftConfig
        )
        XCTAssertEqual(tracker.changeCount, 0)
    }

    func testSeedWithDeliveredAndNilDraftHasNoGhostEdits() {
        let prefsConfig = WatchItemViewModel.config(from: .defaults)
        let prefsReadiness = WatchItemViewModel.readiness(from: .defaults)
        readinessStore.saveDelivered(
            workoutID: "lib-bike",
            snapshot: WatchItemReadinessSnapshot(
                readiness: prefsReadiness,
                config: prefsConfig,
                snapshotPills: ["4 STEPS"],
                updatedAt: Date()
            )
        )
        // No draft — previously fell back to demo config → 3 ghost EDITED rows.
        let seeded = WatchItemViewModel.seed(
            storeKey: "lib-bike",
            title: "Bike ski row",
            isApple: true,
            prefs: nil,
            readinessStore: readinessStore,
            deliveredStepTotal: 4
        )
        let tracker = WatchItemChangeTracker(
            baseline: seeded.baseline,
            config: seeded.baselineConfig,
            draft: seeded.draft,
            draftConfig: seeded.draftConfig
        )
        XCTAssertEqual(tracker.changeCount, 0)
        XCTAssertEqual(seeded.draftConfig, prefsConfig)
        XCTAssertNotEqual(
            seeded.draftConfig,
            WatchItemViewModel.demoConfig(isApple: true, title: "Bike ski row")
        )
    }

    func testStaleDemoDraftDiscardedAgainstPrefsBaseline() {
        let demo = WatchItemViewModel.demoConfig(isApple: true, title: "Bike ski row")
        readinessStore.saveDelivered(
            workoutID: "lib-bike",
            snapshot: WatchItemReadinessSnapshot(
                readiness: WatchItemViewModel.readiness(from: .defaults),
                config: WatchItemViewModel.config(from: .defaults),
                snapshotPills: ["4 STEPS"],
                updatedAt: Date()
            )
        )
        readinessStore.saveDraft(
            workoutID: "lib-bike",
            snapshot: WatchItemReadinessSnapshot(
                readiness: WatchItemReadinessState(
                    mobilityEnabled: true,
                    warmupsEnabled: true,
                    restEnabled: true,
                    cooldownEnabled: false
                ),
                config: demo,
                snapshotPills: ["9 STEPS"],
                updatedAt: Date()
            )
        )
        let seeded = WatchItemViewModel.seed(
            storeKey: "lib-bike",
            title: "Bike ski row",
            isApple: true,
            prefs: .defaults,
            readinessStore: readinessStore,
            deliveredStepTotal: 4
        )
        let tracker = WatchItemChangeTracker(
            baseline: seeded.baseline,
            config: seeded.baselineConfig,
            draft: seeded.draft,
            draftConfig: seeded.draftConfig
        )
        XCTAssertEqual(tracker.changeCount, 0)
        XCTAssertNotEqual(seeded.draftConfig, demo)
    }

    func testLinkStorePreservesPlanJSONAcrossTitleOnlyRecord() {
        let planJSON = bikeSkiRowPlanJSON
        linkStore.record(
            planID: "plan-1",
            workoutID: "w-1",
            title: "Bike ski row",
            planJSON: planJSON
        )
        linkStore.record(planID: "plan-1", workoutID: "w-1", title: "Bike ski row")
        XCTAssertEqual(linkStore.planJSON(forPlanID: "plan-1"), planJSON)
    }

    func testProductionResolvedSectionsEmptyWithoutPlanOrDemo() {
        // Demo flag off in unit tests → no Bench/Squat hardcode.
        let sections = WatchItemViewModel.resolvedStepSections(
            stepSections: [],
            planJSON: nil,
            title: "Bike ski row"
        )
        XCTAssertTrue(sections.isEmpty)
    }

    /// Library workout deleted after schedule — cached planJSON still drives sections.
    func testAppleFactoryKeepsPlanJSONWhenLibraryWorkoutDeleted() {
        let planJSON = bikeSkiRowPlanJSON
        linkStore.record(
            planID: "plan-bike",
            workoutID: "lib-deleted",
            title: "Bike ski row",
            planJSON: planJSON
        )
        // Library no longer contains lib-deleted — resolve drops the binding but
        // planJSON must remain for Watch Item sections.
        let linked = linkStore.resolve(
            planID: "plan-bike",
            title: "Bike ski row",
            library: [("lib-other", "Different workout")]
        )
        XCTAssertNil(linked)
        XCTAssertEqual(linkStore.planJSON(forPlanID: "plan-bike"), planJSON)
        let sections = WatchItemViewModel.resolvedStepSections(
            stepSections: [],
            planJSON: linkStore.planJSON(forPlanID: "plan-bike"),
            title: "Bike ski row"
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].band, "Circuit")
        XCTAssertEqual(sections[0].tag, "8 ROUNDS")
        XCTAssertEqual(sections[0].steps.count, 4)
    }

    /// Prior demo delivered snapshot must not stick as production baseline/pills.
    func testProductionMigratesStaleDemoDeliveredSnapshot() {
        let demo = WatchItemViewModel.demoConfig(isApple: true, title: "Bike ski row")
        readinessStore.saveDelivered(
            workoutID: "lib-bike",
            snapshot: WatchItemReadinessSnapshot(
                readiness: WatchItemReadinessState(
                    mobilityEnabled: true,
                    warmupsEnabled: true,
                    restEnabled: true,
                    cooldownEnabled: false
                ),
                config: demo,
                snapshotPills: WatchItemViewModel.demoPills(isApple: true, title: "Bike ski row"),
                updatedAt: Date()
            )
        )
        let seeded = WatchItemViewModel.seed(
            storeKey: "lib-bike",
            title: "Bike ski row",
            isApple: true,
            prefs: .defaults,
            readinessStore: readinessStore,
            deliveredStepTotal: 4
        )
        let prefsConfig = WatchItemViewModel.config(from: .defaults)
        let prefsReadiness = WatchItemViewModel.readiness(from: .defaults)
        XCTAssertEqual(seeded.baselineConfig, prefsConfig)
        XCTAssertEqual(seeded.baseline, prefsReadiness)
        XCTAssertEqual(seeded.draftConfig, prefsConfig)
        XCTAssertEqual(seeded.draft, prefsReadiness)
        XCTAssertNotEqual(seeded.baselineConfig, demo)
        XCTAssertEqual(seeded.pills.first, WatchItemCopy.stepsPill(count: 4))
        XCTAssertNotEqual(
            seeded.pills,
            WatchItemViewModel.demoPills(isApple: true, title: "Bike ski row")
        )
        let persisted = readinessStore.loadDelivered(workoutID: "lib-bike")
        XCTAssertEqual(persisted?.config, prefsConfig)
        XCTAssertEqual(persisted?.readiness, prefsReadiness)
        XCTAssertEqual(persisted?.snapshotPills.first, WatchItemCopy.stepsPill(count: 4))
    }

    /// Replace path: unchecking Rest must clear prior rest chips from the overlay.
    func testSectionsReflectingDeliveredClearsRestChipsWhenRestDisabled() {
        let prior = [
            PreviewSection(
                accent: .work,
                band: "Circuit",
                tag: "6 ROUNDS",
                steps: [
                    PreviewStep(number: 1, title: "Bike", detail: "3:00", restChip: nil),
                    PreviewStep(number: 2, title: "Ski", detail: "3:00", restChip: "REST 60S")
                ]
            )
        ]
        let rebuilt = WatchItemViewModel.sectionsReflectingDelivered(
            readiness: WatchItemReadinessState(
                mobilityEnabled: false,
                warmupsEnabled: false,
                restEnabled: false,
                cooldownEnabled: false
            ),
            config: WatchItemConfigState(
                mobilityActivities: [],
                cooldownActivities: [],
                perExerciseRamps: [],
                restOpen: false,
                restSec: 60
            ),
            priorSections: prior
        )
        XCTAssertTrue(rebuilt.flatMap(\.steps).allSatisfy { $0.restChip == nil })
    }

    /// Replace path: Rest edits must regenerate chips from delivered config.
    func testSectionsReflectingDeliveredRebuildsRestChipsFromConfig() {
        let prior = [
            PreviewSection(
                accent: .work,
                band: "Circuit",
                tag: "6 ROUNDS",
                steps: [
                    PreviewStep(number: 1, title: "Bike", detail: "3:00", restChip: "REST 60S"),
                    PreviewStep(number: 2, title: "Ski", detail: "3:00", restChip: "REST 60S")
                ]
            )
        ]
        let open = WatchItemViewModel.sectionsReflectingDelivered(
            readiness: WatchItemReadinessState(
                mobilityEnabled: false,
                warmupsEnabled: false,
                restEnabled: true,
                cooldownEnabled: false
            ),
            config: WatchItemConfigState(
                mobilityActivities: [],
                cooldownActivities: [],
                perExerciseRamps: [],
                restOpen: true,
                restSec: 90
            ),
            priorSections: prior
        )
        XCTAssertNil(open[0].steps[0].restChip)
        XCTAssertEqual(open[0].steps[1].restChip, "REST · YOU END IT")

        let timed = WatchItemViewModel.sectionsReflectingDelivered(
            readiness: WatchItemReadinessState(
                mobilityEnabled: false,
                warmupsEnabled: false,
                restEnabled: true,
                cooldownEnabled: false
            ),
            config: WatchItemConfigState(
                mobilityActivities: [],
                cooldownActivities: [],
                perExerciseRamps: [],
                restOpen: false,
                restSec: 120
            ),
            priorSections: prior
        )
        XCTAssertNil(timed[0].steps[0].restChip)
        XCTAssertEqual(timed[0].steps[1].restChip, "REST 120S")
    }
}
