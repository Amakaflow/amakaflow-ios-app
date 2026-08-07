//
//  WatchWorkoutTitlePolicyTests.swift
//  AmakaFlowCompanionTests
//

import XCTest
@testable import AmakaFlowCompanion

final class WatchWorkoutTitlePolicyTests: XCTestCase {
    func testIntentionalCopySuffix() {
        XCTAssertTrue(WatchWorkoutTitlePolicy.isIntentionalCopy("Engine EMOM (1)"))
        XCTAssertTrue(WatchWorkoutTitlePolicy.isIntentionalCopy("For time (12)"))
        XCTAssertFalse(WatchWorkoutTitlePolicy.isIntentionalCopy("Engine EMOM"))
        XCTAssertFalse(WatchWorkoutTitlePolicy.isIntentionalCopy("Engine EMOM(1)"))
        XCTAssertFalse(WatchWorkoutTitlePolicy.isIntentionalCopy("Home gym"))
    }

    func testSameScheduledTitleExactMatchOnly() {
        XCTAssertTrue(WatchWorkoutTitlePolicy.isSameScheduledTitle("Engine EMOM", "engine emom"))
        XCTAssertFalse(WatchWorkoutTitlePolicy.isSameScheduledTitle("Engine EMOM", "Engine EMOM (1)"))
        XCTAssertTrue(WatchWorkoutTitlePolicy.isSameScheduledTitle("Engine EMOM (1)", "engine emom (1)"))
    }
}

@MainActor
final class GarminWatchQueueStoreTitleTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: GarminWatchQueueStore!

    override func setUp() {
        suiteName = "GarminWatchQueueStoreTitleTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = GarminWatchQueueStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRecordPushUsesWorkoutTitleNotGymAndCollapsesSameName() {
        store.recordPush(workoutID: "a", title: "Home gym")
        store.recordPush(workoutID: "b", title: "Engine EMOM")
        store.recordPush(workoutID: "c", title: "Engine EMOM")

        let items = store.load()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.title).sorted(), ["Engine EMOM", "Home gym"])
        XCTAssertEqual(items.first { $0.title == "Engine EMOM" }?.workoutID, "c")
    }

    func testIntentionalCopyKeepsBothEntries() {
        store.recordPush(workoutID: "a", title: "Engine EMOM")
        store.recordPush(workoutID: "b", title: "Engine EMOM (1)")

        let items = store.load()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.title)), Set(["Engine EMOM", "Engine EMOM (1)"]))
    }
}
