//
//  WatchItemReadinessStoreTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2388: draft survives dismiss; delivered baseline is independent.
//

import XCTest
@testable import AmakaFlowCompanion

final class WatchItemReadinessStoreTests: XCTestCase {
    private var store: WatchItemReadinessStore!
    private let suiteName = "ama2388.readiness.tests"

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = WatchItemReadinessStore(defaults: defaults)
    }

    func testDraftRoundTrip() {
        let snap = WatchItemReadinessSnapshot(
            readiness: WatchItemReadinessState(
                mobilityEnabled: true,
                warmupsEnabled: true,
                restEnabled: true,
                cooldownEnabled: true
            ),
            config: WatchItemConfigState(
                mobilityActivities: [EnrichmentActivityPref(name: "Ski erg")],
                cooldownActivities: [],
                perExerciseRamps: [],
                restOpen: true,
                restSec: 60
            ),
            snapshotPills: ["9 STEPS"],
            updatedAt: Date()
        )
        store.saveDraft(workoutID: "w-1", snapshot: snap)
        let loaded = store.loadDraft(workoutID: "w-1")
        XCTAssertEqual(loaded?.readiness.cooldownEnabled, true)
        XCTAssertEqual(loaded?.config.mobilityActivities.first?.name, "Ski erg")
    }

    func testDeliveredIndependentOfDraft() {
        let delivered = WatchItemReadinessSnapshot(
            readiness: WatchItemReadinessState(
                mobilityEnabled: true,
                warmupsEnabled: true,
                restEnabled: true,
                cooldownEnabled: false
            ),
            config: WatchItemConfigState(
                mobilityActivities: [],
                cooldownActivities: [],
                perExerciseRamps: [],
                restOpen: true,
                restSec: 60
            ),
            snapshotPills: ["6 STEPS"],
            updatedAt: Date()
        )
        var draft = delivered
        draft.readiness.cooldownEnabled = true
        store.saveDelivered(workoutID: "w-1", snapshot: delivered)
        store.saveDraft(workoutID: "w-1", snapshot: draft)
        XCTAssertEqual(store.loadDelivered(workoutID: "w-1")?.readiness.cooldownEnabled, false)
        XCTAssertEqual(store.loadDraft(workoutID: "w-1")?.readiness.cooldownEnabled, true)
    }

    func testMigrateCopiesPlanKeyedSnapshotsOntoLibraryID() {
        let snap = WatchItemReadinessSnapshot(
            readiness: WatchItemReadinessState(
                mobilityEnabled: true,
                warmupsEnabled: true,
                restEnabled: true,
                cooldownEnabled: true
            ),
            config: WatchItemConfigState(
                mobilityActivities: [],
                cooldownActivities: [],
                perExerciseRamps: [],
                restOpen: true,
                restSec: 60
            ),
            snapshotPills: ["9 STEPS"],
            updatedAt: Date()
        )
        store.saveDraft(workoutID: "plan-1", snapshot: snap)
        store.saveDelivered(workoutID: "plan-1", snapshot: snap)
        store.migrate(from: "plan-1", to: "w-9")
        XCTAssertEqual(store.loadDraft(workoutID: "w-9")?.readiness.cooldownEnabled, true)
        XCTAssertEqual(store.loadDelivered(workoutID: "w-9")?.snapshotPills, ["9 STEPS"])
        XCTAssertNil(store.loadDraft(workoutID: "plan-1"))
        XCTAssertNil(store.loadDelivered(workoutID: "plan-1"))
    }
}
