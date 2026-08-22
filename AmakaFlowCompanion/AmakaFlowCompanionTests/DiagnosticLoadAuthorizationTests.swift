import XCTest
@testable import AmakaFlowCompanion

final class DiagnosticLoadAuthorizationTests: XCTestCase {
    func testInFlightLogsCompletionAfterLockIsRejected() {
        let token = DiagnosticAuthorizationLoadToken.capture(
            state: .authorized(authorization(grantID: grantA, capabilities: [.logsRead])),
            accountID: "account-a",
            requiredCapability: .logsRead
        )

        XCTAssertFalse(DiagnosticLogsPolicy.acceptsLoadedEvents(
            token: token,
            currentState: .locked(.expired),
            currentAccountID: "account-a"
        ))
    }

    func testInFlightPreviewCompletionAfterLockIsRejected() {
        let token = DiagnosticAuthorizationLoadToken.capture(
            state: .authorized(authorization(grantID: grantA, capabilities: [.bundleExport])),
            accountID: "account-a",
            requiredCapability: .bundleExport
        )

        XCTAssertFalse(DiagnosticBundlePreviewPolicy.acceptsLoadedSnapshot(
            token: token,
            currentState: .locked(.accountChanged),
            currentAccountID: "account-a"
        ))
    }

    func testGrantASnapshotIsRejectedUnderGrantB() {
        let snapshot = bundleSnapshot(authorization: authorization(grantID: grantA, capabilities: [.bundleExport]))

        let preview = DiagnosticBundlePreviewPolicy.preview(
            state: .authorized(authorization(grantID: grantB, capabilities: [.bundleExport])),
            snapshot: snapshot
        )

        XCTAssertNil(preview)
    }

    func testAuthorizedToAuthorizedGrantTransitionRequiresReload() {
        let token = DiagnosticAuthorizationLoadToken.capture(
            state: .authorized(authorization(grantID: grantA, capabilities: [.logsRead])),
            accountID: "account-a",
            requiredCapability: .logsRead
        )

        XCTAssertTrue(DiagnosticLogsPolicy.shouldReloadLoadedContent(
            token: token,
            currentState: .authorized(authorization(grantID: grantB, capabilities: [.logsRead])),
            currentAccountID: "account-a",
            requiredCapability: .logsRead
        ))
    }

    func testAuthorizedToAuthorizedAccountTransitionRequiresReload() {
        let token = DiagnosticAuthorizationLoadToken.capture(
            state: .authorized(authorization(grantID: grantA, capabilities: [.logsRead])),
            accountID: "account-a",
            requiredCapability: .logsRead
        )

        XCTAssertTrue(DiagnosticLogsPolicy.shouldReloadLoadedContent(
            token: token,
            currentState: .authorized(authorization(grantID: grantA, capabilities: [.logsRead])),
            currentAccountID: "account-b",
            requiredCapability: .logsRead
        ))
    }

    @MainActor
    func testInjectedActionProviderContributesFrozenActions() async throws {
        let action = DiagnosticActionSnapshot(
            id: "action-1",
            timestamp: date("2026-08-21T20:03:00Z"),
            capability: .syncRetry,
            outcome: .succeeded,
            title: "Retry sync",
            safeContext: ["pending_count": "2"],
            requestID: "req-action-1",
            sentryEventID: "sentry-action-1"
        )
        let actionProvider = MutableActionProvider(actions: [action])
        let provider = LiveDiagnosticBundleSnapshotProvider(
            eventsProvider: StubEventProvider(events: []),
            actionProvider: actionProvider,
            now: { self.date("2026-08-21T20:05:00Z") }
        )

        let snapshot = try await provider.snapshot(
            authorization: authorization(grantID: grantA, capabilities: [.bundleExport])
        )
        actionProvider.actions = []

        XCTAssertEqual(snapshot.actions, [action])
    }

    private var grantA: UUID { UUID(uuidString: "11111111-1111-4111-8111-111111111111")! }
    private var grantB: UUID { UUID(uuidString: "22222222-2222-4222-8222-222222222222")! }

    private func bundleSnapshot(authorization: SupportDiagnosticsAuthorization) -> DiagnosticBundleSnapshot {
        DiagnosticBundleSnapshot(
            createdAt: date("2026-08-21T20:05:00Z"),
            authorization: DiagnosticBundleAuthorizationSnapshot(authorization: authorization),
            status: SupportDiagnosticsSnapshot(generatedAt: date("2026-08-21T20:04:00Z"), results: []),
            events: [],
            actions: []
        )
    }

    private func authorization(
        grantID: UUID,
        capabilities: Set<SupportDiagnosticsCapability>
    ) -> SupportDiagnosticsAuthorization {
        SupportDiagnosticsAuthorization(
            grantID: grantID,
            role: .viewer,
            capabilities: capabilities,
            expiresAt: date("2026-08-22T20:00:00Z"),
            serverTime: date("2026-08-21T20:00:00Z")
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

@MainActor
private final class StubEventProvider: DiagnosticEventSnapshotProviding {
    private let events: [DiagnosticEvent]

    init(events: [DiagnosticEvent]) {
        self.events = events
    }

    func eventsForCurrentAccount() async throws -> [DiagnosticEvent] {
        events
    }
}

@MainActor
private final class MutableActionProvider: DiagnosticActionSnapshotProviding {
    var actions: [DiagnosticActionSnapshot]

    init(actions: [DiagnosticActionSnapshot]) {
        self.actions = actions
    }

    func actionsForCurrentSession() async throws -> [DiagnosticActionSnapshot] {
        actions
    }
}
