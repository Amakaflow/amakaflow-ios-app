//
//  AppDependenciesTests.swift
//  AmakaFlowCompanionTests
//
//  Regression tests for AppDependencies seam enforcement (issue #314).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class AppDependenciesTests: XCTestCase {

    func testFixtureSyncEngineIsNotShared() {
        // .fixture must use an isolated SyncEngine, not the shared singleton.
        // If this fails, fixture-mode tests can read/mutate production sync state.
        XCTAssertFalse(
            AppDependencies.fixture.syncEngine === SyncEngine.shared,
            ".fixture.syncEngine must be a fresh isolated instance, not SyncEngine.shared"
        )
    }

    func testLiveSyncEngineIsShared() {
        // Sanity: .live should use the shared singleton (the one real handler is wired to).
        XCTAssertTrue(
            AppDependencies.live.syncEngine === SyncEngine.shared,
            ".live.syncEngine must be SyncEngine.shared"
        )
    }

    func testFixtureAndLiveSyncEnginesAreDistinct() {
        XCTAssertFalse(
            AppDependencies.fixture.syncEngine === AppDependencies.live.syncEngine,
            ".fixture and .live must use distinct SyncEngine instances"
        )
    }
}
