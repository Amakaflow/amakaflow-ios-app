//
//  AcceptedSuggestionsStoreTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1751: ensures accepted Suggest-Workout results survive a fresh
//  loadWorkouts() (which overwrites incomingWorkouts from the API).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class AcceptedSuggestionsStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AcceptedSuggestionsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_save_then_all_returns_workout() {
        let store = AcceptedSuggestionsStore(defaults: defaults)
        let workout = TestFixtures.workout(id: "w-1", name: "AI Suggested")

        store.save(workout)

        let stored = store.all()
        XCTAssertEqual(stored.map(\.id), ["w-1"])
        XCTAssertEqual(stored.first?.name, "AI Suggested")
    }

    func test_save_is_idempotent_by_id() {
        let store = AcceptedSuggestionsStore(defaults: defaults)
        let workout = TestFixtures.workout(id: "w-1")

        store.save(workout)
        store.save(workout)
        store.save(workout)

        XCTAssertEqual(store.all().count, 1)
    }

    func test_remove_clears_workout() {
        let store = AcceptedSuggestionsStore(defaults: defaults)
        store.save(TestFixtures.workout(id: "w-1"))
        store.save(TestFixtures.workout(id: "w-2"))

        store.remove(id: "w-1")

        XCTAssertEqual(store.all().map(\.id), ["w-2"])
    }

    func test_persists_across_store_instances() {
        // Same UserDefaults suite -> a fresh store sees prior writes.
        // This is the core guarantee: accepted workouts survive a re-init.
        let first = AcceptedSuggestionsStore(defaults: defaults)
        first.save(TestFixtures.workout(id: "w-persist", name: "Persisted"))

        let second = AcceptedSuggestionsStore(defaults: defaults)
        XCTAssertEqual(second.all().map(\.id), ["w-persist"])
        XCTAssertEqual(second.all().first?.name, "Persisted")
    }
}
