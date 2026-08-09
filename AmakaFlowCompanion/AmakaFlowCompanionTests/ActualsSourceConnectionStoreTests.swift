//
//  ActualsSourceConnectionStoreTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: source connection store for teach-card gating.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ActualsSourceConnectionStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ActualsSourceConnectionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testStartsWithNoSourcesConnected() {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        XCTAssertFalse(store.hasAnySourceConnected)
        for provider in ActualsSourceProvider.allCases {
            XCTAssertFalse(store.isConnected(provider))
        }
    }

    func testMarkConnectedFlipsProviderAndHasAny() {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        store.markConnected(.strava)
        XCTAssertTrue(store.isConnected(.strava))
        XCTAssertFalse(store.isConnected(.appleHealth))
        XCTAssertTrue(store.hasAnySourceConnected)
    }

    func testHasAnyRemainsTrueAfterDisconnectIfEverConnected() {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        store.markConnected(.garmin)
        store.markDisconnected(.garmin)
        XCTAssertFalse(store.isConnected(.garmin))
        // Teach card is gone forever after first connect — hasEverConnected stays true.
        XCTAssertTrue(store.hasEverConnected)
        XCTAssertFalse(store.hasAnySourceConnected)
    }

    func testPersistsAcrossInstances() {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        store.markConnected(.appleHealth)
        let reloaded = ActualsSourceConnectionStore(defaults: defaults)
        XCTAssertTrue(reloaded.isConnected(.appleHealth))
        XCTAssertTrue(reloaded.hasEverConnected)
    }
}
