//
//  AcceptedSuggestionsStoreTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1751: ensures accepted Suggest-Workout results survive a fresh
//  loadWorkouts() (which overwrites incomingWorkouts from the API).
//

import XCTest
@testable import AmakaFlowCompanion

final class AcceptedSuggestionsStoreTests: XCTestCase {

    // CI's iOS test target sandbox returns nil from UserDefaults(suiteName:)
    // for arbitrary names — so this suite uses UserDefaults.standard with a
    // namespaced key that we clean up before/after each test. Each store
    // instance is constructed against an in-memory throwaway suite when
    // possible (so the assertions still validate the persistence invariant
    // via two separate AcceptedSuggestionsStore instances backed by the
    // same UserDefaults).
    private let storageKey = "amakaflow.acceptedSuggestions.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    func test_save_then_all_returns_workout() {
        let store = AcceptedSuggestionsStore(defaults: .standard)
        let workout = TestFixtures.workout(id: "w-1", name: "AI Suggested")

        store.save(workout)

        let stored = store.all()
        XCTAssertEqual(stored.map(\.id), ["w-1"])
        XCTAssertEqual(stored.first?.name, "AI Suggested")
    }

    func test_save_is_idempotent_by_id() {
        let store = AcceptedSuggestionsStore(defaults: .standard)
        let workout = TestFixtures.workout(id: "w-1")

        store.save(workout)
        store.save(workout)
        store.save(workout)

        XCTAssertEqual(store.all().count, 1)
    }

    func test_remove_clears_workout() {
        let store = AcceptedSuggestionsStore(defaults: .standard)
        store.save(TestFixtures.workout(id: "w-1"))
        store.save(TestFixtures.workout(id: "w-2"))

        store.remove(id: "w-1")

        XCTAssertEqual(store.all().map(\.id), ["w-2"])
    }

    func test_persists_across_store_instances() {
        // Two stores sharing the same UserDefaults — the core guarantee:
        // accepted workouts survive a fresh AcceptedSuggestionsStore init.
        let first = AcceptedSuggestionsStore(defaults: .standard)
        first.save(TestFixtures.workout(id: "w-persist", name: "Persisted"))

        let second = AcceptedSuggestionsStore(defaults: .standard)
        XCTAssertEqual(second.all().map(\.id), ["w-persist"])
        XCTAssertEqual(second.all().first?.name, "Persisted")
    }
}
