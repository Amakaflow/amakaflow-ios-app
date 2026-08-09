//
//  ActualsSyncProgressTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: honest backfill counter — never fake increments.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ActualsSyncProgressTests: XCTestCase {

    func testDisplayStringMatchesHandoffFormat() {
        let progress = ActualsSyncProgress(ingested: 3, total: 12)
        XCTAssertEqual(
            progress.displayString,
            "PULLING YOUR LAST 30 DAYS… 3 OF 12 SESSIONS ▍"
        )
    }

    func testRecordIngestedWithoutBeginDoesNothing() {
        let store = ActualsSyncProgressStore()
        store.recordIngestedSession()
        store.recordIngestedSession()
        XCTAssertNil(store.progress, "Must never invent a counter without a real backfill total")
    }

    func testBeginThenRecordIncrementsHonestly() {
        let store = ActualsSyncProgressStore()
        store.beginBackfill(total: 4)
        XCTAssertEqual(store.progress?.ingested, 0)
        XCTAssertTrue(store.progress?.shouldShowBanner == true)

        store.recordIngestedSession()
        store.recordIngestedSession()
        XCTAssertEqual(store.progress?.ingested, 2)
        XCTAssertEqual(
            store.progress?.displayString,
            "PULLING YOUR LAST 30 DAYS… 2 OF 4 SESSIONS ▍"
        )
    }

    func testBeginWithZeroTotalIsIgnored() {
        let store = ActualsSyncProgressStore()
        store.beginBackfill(total: 0)
        XCTAssertNil(store.progress)
    }

    func testBeginPullingShowsLookbackBeforeTotalKnown() {
        let store = ActualsSyncProgressStore()
        store.beginPulling()
        XCTAssertTrue(store.progress?.shouldShowBanner == true)
        XCTAssertTrue(store.progress?.isAwaitingTotal == true)
        XCTAssertEqual(
            store.progress?.displayString,
            "PULLING YOUR LAST 30 DAYS… ▍"
        )
        store.beginBackfill(total: 3)
        XCTAssertFalse(store.progress?.isAwaitingTotal == true)
        XCTAssertEqual(
            store.progress?.displayString,
            "PULLING YOUR LAST 30 DAYS… 0 OF 3 SESSIONS ▍"
        )
    }

    func testDoesNotExceedTotal() {
        let store = ActualsSyncProgressStore()
        store.beginBackfill(total: 2)
        store.recordIngestedSession()
        store.recordIngestedSession()
        store.recordIngestedSession()
        XCTAssertEqual(store.progress?.ingested, 2)
        XCTAssertTrue(store.progress?.isComplete == true)
        XCTAssertFalse(store.progress?.shouldShowBanner == true)
    }

    func testLinkedToastLineAndBadgeCopy() {
        XCTAssertEqual(
            ActualsLinkFeedback.linkedToastLine(for: .strava),
            "Strava linked — pulling your last 30 days…"
        )
        XCTAssertEqual(ActualsCopy.linkedJustNowBadge, "LINKED ✓ JUST NOW")
        XCTAssertEqual(ActualsCopy.syncPullingSub, "PULLING YOUR LAST 30 DAYS…")
        XCTAssertEqual(ActualsCopy.syncCounterAccessibilityID, "af_actuals_sync_counter")
    }

    func testMarkConnectedSetsFreshlyLinked() {
        let suite = "ActualsSyncFresh.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        defer { ud.removePersistentDomain(forName: suite) }

        let store = ActualsSourceConnectionStore(defaults: ud)
        store.markConnected(.strava)
        XCTAssertTrue(store.isFreshlyLinked(.strava))
        store.clearFreshLink(.strava)
        XCTAssertFalse(store.isFreshlyLinked(.strava))
        XCTAssertTrue(store.isConnected(.strava))
    }
}
