//
//  ActualsAppleHealthConnectTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: Apple Health primer copy + grant / deny → Settings paths.
//

import UIKit
import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ActualsAppleHealthConnectTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ActualsAppleHealthConnectTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    // MARK: - Primer copy (JSX lock)

    func testPrimerLeadAndTurnOnAllCoachMatchHandoff() {
        XCTAssertEqual(
            ActualsCopy.appleHealthPrimerLead,
            "iOS will ask next. We request read only — three things:"
        )
        XCTAssertTrue(ActualsCopy.appleHealthPrimerLead.contains("read only"))
        XCTAssertEqual(
            ActualsCopy.appleHealthTurnOnAllCoach,
            "Apple's sheet starts with everything off — tap “Turn On All”, then Allow."
        )
    }

    func testPrimerReadTypeWhyTagsExact() {
        XCTAssertEqual(ActualsCopy.appleHealthReadTypes.count, 3)
        XCTAssertEqual(ActualsCopy.appleHealthReadTypes[0].title, "Workouts")
        XCTAssertEqual(ActualsCopy.appleHealthReadTypes[0].why, "THE SESSIONS THEMSELVES")
        XCTAssertEqual(ActualsCopy.appleHealthReadTypes[1].title, "Heart rate")
        XCTAssertEqual(ActualsCopy.appleHealthReadTypes[1].why, "EFFORT — SHOWN ON YOUR SESSION CARDS")
        XCTAssertEqual(ActualsCopy.appleHealthReadTypes[2].title, "Active energy")
        XCTAssertEqual(ActualsCopy.appleHealthReadTypes[2].why, "CALORIES ON YOUR CARDS")
    }

    func testPrimerAccessibilityIDs() {
        XCTAssertEqual(ActualsCopy.appleHealthPrimerAccessibilityID, "af_actuals_apple_primer")
        XCTAssertEqual(ActualsCopy.appleHealthContinueAccessibilityID, "af_actuals_apple_continue")
    }

    // MARK: - Grant → markConnected

    func testGrantMarksAppleHealthConnected() async {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        let healthKit = MockActualsHealthKitConnector(connectOutcomes: [.granted])

        let outcome = await healthKit.connect()
        ActualsAppleHealthConnectAction.apply(
            outcome: outcome,
            store: store,
            openSettings: { healthKit.openHealthSettings() }
        )

        XCTAssertEqual(outcome, .granted)
        XCTAssertTrue(store.isConnected(.appleHealth))
        XCTAssertFalse(healthKit.didOpenHealthSettings)
    }

    // MARK: - Prompt completed → stay disconnected

    func testPromptCompletedDoesNotMarkConnected() async {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        let healthKit = MockActualsHealthKitConnector(connectOutcomes: [.promptCompleted])

        let outcome = await healthKit.connect()
        ActualsAppleHealthConnectAction.apply(
            outcome: outcome,
            store: store,
            openSettings: { healthKit.openHealthSettings() }
        )

        XCTAssertEqual(outcome, .promptCompleted)
        XCTAssertFalse(store.isConnected(.appleHealth))
        XCTAssertEqual(healthKit.authorizationState, .promptCompleted)
    }

    // MARK: - Deny → stay disconnected

    func testDenyLeavesDisconnected() async {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        let healthKit = MockActualsHealthKitConnector(connectOutcomes: [.denied])

        let outcome = await healthKit.connect()
        ActualsAppleHealthConnectAction.apply(
            outcome: outcome,
            store: store,
            openSettings: { healthKit.openHealthSettings() }
        )

        XCTAssertEqual(outcome, .denied)
        XCTAssertFalse(store.isConnected(.appleHealth))
        XCTAssertEqual(healthKit.authorizationState, .denied)
        XCTAssertFalse(healthKit.didOpenHealthSettings)
    }

    // MARK: - Retry after deny → Settings deep-link

    func testRetryAfterDenyOpensHealthSettingsAndDoesNotConnect() async {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        let healthKit = MockActualsHealthKitConnector(
            authorizationState: .denied,
            connectOutcomes: [.needsSettings]
        )

        let outcome = await healthKit.connect()
        ActualsAppleHealthConnectAction.apply(
            outcome: outcome,
            store: store,
            openSettings: { healthKit.openHealthSettings() }
        )

        XCTAssertEqual(outcome, .needsSettings)
        XCTAssertFalse(store.isConnected(.appleHealth))
        XCTAssertTrue(healthKit.didOpenHealthSettings)
        XCTAssertEqual(healthKit.openedURLs.first?.absoluteString, UIApplication.openSettingsURLString)
    }

    func testLiveConnectorSecondConnectAfterDeniedNeedsSettings() async {
        let connector = LiveActualsHealthKitConnector(defaults: defaults)
        connector.markDeniedForTesting()
        XCTAssertEqual(connector.authorizationState, .denied)

        var opened: [URL] = []
        let live = LiveActualsHealthKitConnector(
            defaults: defaults,
            openURL: { opened.append($0) }
        )
        XCTAssertEqual(live.authorizationState, .denied)

        let outcome = await live.connect()
        XCTAssertEqual(outcome, .needsSettings)
        live.openHealthSettings()
        XCTAssertEqual(opened.first?.absoluteString, UIApplication.openSettingsURLString)
    }
}
