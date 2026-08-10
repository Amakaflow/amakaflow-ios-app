//
//  ActualsProviderAuthTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: Strava/Garmin OAuth scope copy + cancel/success linking.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ActualsProviderAuthTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ActualsProviderAuthTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    // MARK: - Scope copy (never request upload)

    func testStravaScopesLockUploadAsNotRequested() {
        let scopes = ActualsCopy.oauthScopes(for: .strava)
        XCTAssertEqual(scopes.count, 3)
        XCTAssertTrue(scopes[0].granted)
        XCTAssertTrue(scopes[1].granted)
        XCTAssertFalse(scopes[2].granted)
        XCTAssertEqual(scopes[2].title, "Upload or edit your activities")
        XCTAssertTrue(scopes[2].subtitle.contains("NOT REQUESTED"))
        XCTAssertFalse(
            scopes.contains(where: {
                let title = $0.title.lowercased()
                let uploadSemantics = title.contains("write")
                    || title.contains("upload")
                    || title.contains("edit")
                return uploadSemantics && $0.granted
            }),
            "Must never request activity:write / upload"
        )
    }

    func testGarminScopesMirrorStravaShape() {
        let scopes = ActualsCopy.oauthScopes(for: .garmin)
        XCTAssertEqual(scopes.count, 3)
        XCTAssertFalse(scopes[2].granted)
        XCTAssertTrue(scopes[2].subtitle.contains("NOT REQUESTED"))
    }

    func testOAuthHostChromePerProvider() {
        XCTAssertTrue(ActualsCopy.oauthHostChrome(for: .strava).contains("strava.com"))
        XCTAssertTrue(ActualsCopy.oauthHostChrome(for: .garmin).contains("garmin.com"))
    }

    // MARK: - Success → markConnected

    func testAuthorizeSuccessMarksProviderConnected() async {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        let auth = MockActualsProviderAuth(outcomes: [.strava: .success(grantedWrite: false)])

        let outcome = await auth.authorize(.strava)
        ActualsProviderAuthAction.apply(outcome: outcome, provider: .strava, store: store)

        XCTAssertEqual(outcome, .success(grantedWrite: false))
        XCTAssertTrue(store.isConnected(.strava))
        XCTAssertFalse(store.isConnected(.garmin))
    }

    func testWriteBackReconnectRequestsEditScopeCopy() {
        let scopes = ActualsCopy.oauthScopes(for: .strava, includeWrite: true)
        XCTAssertTrue(scopes[2].granted)
        XCTAssertTrue(scopes[2].subtitle.contains("REQUESTED"))
    }

    // MARK: - Cancel → nothing linked

    func testAuthorizeCancelledLeavesDisconnected() async {
        let store = ActualsSourceConnectionStore(defaults: defaults)
        let auth = MockActualsProviderAuth(outcomes: [.garmin: .cancelled])

        let outcome = await auth.authorize(.garmin)
        ActualsProviderAuthAction.apply(outcome: outcome, provider: .garmin, store: store)

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(store.isConnected(.garmin))
        XCTAssertFalse(store.hasAnySourceConnected)
    }

    func testStubAuthorizeDefaultsToSuccess() async {
        let stub = StubActualsProviderAuth()
        let outcome = await stub.authorize(.strava)
        XCTAssertEqual(outcome, .success(grantedWrite: false))
    }

    func testStubAuthorizeIncludeWriteReportsGrantedWrite() async {
        let stub = StubActualsProviderAuth()
        let outcome = await stub.authorize(.strava, includeWrite: true)
        XCTAssertEqual(outcome, .success(grantedWrite: true))
    }

    func testStubNextOutcomeOverrideCancel() async {
        let stub = StubActualsProviderAuth()
        stub.nextOutcome = .cancelled
        let cancelled = await stub.authorize(.strava)
        XCTAssertEqual(cancelled, .cancelled)
        // Consumed — next call returns default success.
        let success = await stub.authorize(.strava)
        XCTAssertEqual(success, .success(grantedWrite: false))
    }
}
