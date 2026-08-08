//
//  AppleScheduledWorkoutLinkStoreTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2388: planID → Library workoutID index + title backfill.
//

import XCTest
@testable import AmakaFlowCompanion

final class AppleScheduledWorkoutLinkStoreTests: XCTestCase {
    private var store: AppleScheduledWorkoutLinkStore!
    private let suiteName = "ama2388.linkstore.tests"

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = AppleScheduledWorkoutLinkStore(defaults: defaults)
    }

    func testRecordAndLookup() {
        store.record(planID: "plan-1", workoutID: "w-1", title: "Full Body")
        XCTAssertEqual(store.workoutID(forPlanID: "plan-1"), "w-1")
    }

    func testTitleBackfillWhenPlanMissing() {
        let library = [("w-9", "Engine EMOM")]
        let resolved = store.resolve(planID: "new-plan", title: "Engine EMOM", library: library)
        XCTAssertEqual(resolved, "w-9")
        XCTAssertEqual(store.workoutID(forPlanID: "new-plan"), "w-9")
    }

    func testAmbiguousTitleDoesNotBackfill() {
        let library = [("a", "Push"), ("b", "Push")]
        let resolved = store.resolve(planID: "p", title: "Push", library: library)
        XCTAssertNil(resolved)
        XCTAssertNil(store.workoutID(forPlanID: "p"))
    }

    func testIntentionalCopyDoesNotMatchBase() {
        let library = [("w-1", "Engine EMOM")]
        let resolved = store.resolve(planID: "p", title: "Engine EMOM (1)", library: library)
        XCTAssertNil(resolved)
    }

    func testStaleLinkDroppedWhenWorkoutMissingFromLibrary() {
        store.record(planID: "plan-1", workoutID: "deleted", title: "Gone")
        let resolved = store.resolve(
            planID: "plan-1",
            title: "Gone",
            library: [("w-2", "Other")]
        )
        XCTAssertNil(resolved)
        XCTAssertNil(store.workoutID(forPlanID: "plan-1"))
    }

    func testEmptyLibraryKeepsExistingLink() {
        store.record(planID: "plan-1", workoutID: "w-1", title: "Full Body")
        let resolved = store.resolve(planID: "plan-1", title: "Full Body", library: [])
        XCTAssertEqual(resolved, "w-1")
    }

    func testRecordCachesPlanJSONAndPreservesOnTitleOnlyUpdate() {
        let json = Data(#"{"title":"Bike ski row","intervals":[]}"#.utf8)
        store.record(planID: "plan-1", workoutID: "w-1", title: "Bike ski row", planJSON: json)
        XCTAssertEqual(store.planJSON(forPlanID: "plan-1"), json)
        store.record(planID: "plan-1", workoutID: "w-1", title: "Bike ski row")
        XCTAssertEqual(store.planJSON(forPlanID: "plan-1"), json)
    }
}
