import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class SupportDiagnosticsSessionTests: XCTestCase {
    func testCheckAndStartAuthorizesOnlyAfterSessionAuditSucceeds() async {
        let access = authorizedAccess()
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(access),
            sessionResult: .success(sessionEvent())
        )
        let session = SupportDiagnosticsSession(
            client: client,
            idempotencyKeyProvider: { "stable-session-key" },
            requestIDProvider: { "request-123" }
        )

        await session.checkAndStart()

        XCTAssertEqual(session.state, .authorized(access.authorization!))
        XCTAssertEqual(client.startedSessions, [
            .init(idempotencyKey: "stable-session-key", requestID: "request-123")
        ])
    }

    func testCheckAndStartKeepsDisabledAccountLockedWithoutStartingAudit() async {
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(disabledAccess()),
            sessionResult: .success(sessionEvent())
        )
        let session = SupportDiagnosticsSession(client: client)

        await session.checkAndStart()

        XCTAssertEqual(session.state, .locked(.notGranted))
        XCTAssertTrue(client.startedSessions.isEmpty)
    }

    func testCheckAndStartRejectsGrantExpiredAtServerTime() async {
        let access = SupportDiagnosticsAccess(
            enabled: true,
            grantID: UUID(uuidString: "3b48344d-3d70-4e36-8750-e3caa43f97dc"),
            role: .viewer,
            capabilities: [.statusRead],
            expiresAt: date("2026-08-21T20:00:00Z"),
            serverTime: date("2026-08-21T20:00:00Z")
        )
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(access),
            sessionResult: .success(sessionEvent())
        )
        let session = SupportDiagnosticsSession(client: client)

        await session.checkAndStart()

        XCTAssertEqual(session.state, .locked(.expired))
        XCTAssertTrue(client.startedSessions.isEmpty)
    }

    func testCheckAndStartFailsClosedWhenSessionAuditCannotStart() async {
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(authorizedAccess()),
            sessionResult: .failure(.transport)
        )
        let session = SupportDiagnosticsSession(client: client)

        await session.checkAndStart()

        XCTAssertEqual(session.state, .failed(.sessionStartFailed))
        XCTAssertFalse(session.isAuthorized)
    }

    func testRetryingSessionAuditReusesOneIdempotencyKey() async {
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(authorizedAccess()),
            sessionResult: .failure(.transport)
        )
        var generatedKeys = ["session-key", "wrong-second-key"]
        let session = SupportDiagnosticsSession(
            client: client,
            idempotencyKeyProvider: { generatedKeys.removeFirst() }
        )

        await session.checkAndStart()
        await session.checkAndStart()

        XCTAssertEqual(
            client.startedSessions.map(\.idempotencyKey),
            ["session-key", "session-key"]
        )
    }

    func testRefreshLocksAnOpenSessionWhenAccessCheckFails() async {
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(authorizedAccess()),
            sessionResult: .success(sessionEvent())
        )
        let session = SupportDiagnosticsSession(client: client)
        await session.checkAndStart()
        client.accessResult = .failure(.transport)

        await session.refreshAccess()

        XCTAssertEqual(session.state, .failed(.accessCheckFailed))
        XCTAssertFalse(session.isAuthorized)
    }

    func testResetImmediatelyLocksAuthorizedSession() async {
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(authorizedAccess()),
            sessionResult: .success(sessionEvent())
        )
        let session = SupportDiagnosticsSession(client: client)
        await session.checkAndStart()

        session.reset(reason: .signedOut)

        XCTAssertEqual(session.state, .locked(.signedOut))
    }

    private func authorizedAccess() -> SupportDiagnosticsAccess {
        SupportDiagnosticsAccess(
            enabled: true,
            grantID: UUID(uuidString: "3b48344d-3d70-4e36-8750-e3caa43f97dc"),
            role: .viewer,
            capabilities: [.statusRead, .logsRead, .bundleExport],
            expiresAt: date("2026-08-22T20:00:00Z"),
            serverTime: date("2026-08-21T20:00:00Z")
        )
    }

    private func disabledAccess() -> SupportDiagnosticsAccess {
        SupportDiagnosticsAccess(
            enabled: false,
            grantID: nil,
            role: nil,
            capabilities: [],
            expiresAt: nil,
            serverTime: date("2026-08-21T20:00:00Z")
        )
    }

    private func sessionEvent() -> SupportDiagnosticsAuditEvent {
        SupportDiagnosticsAuditEvent(
            auditID: UUID(uuidString: "f17f2970-e829-438f-8591-d72d6f1eeae5")!,
            eventType: .sessionStarted,
            outcome: .succeeded,
            createdAt: date("2026-08-21T20:00:01Z")
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private final class StubSupportDiagnosticsAccessClient: SupportDiagnosticsAccessProviding, @unchecked Sendable {
    struct StartedSession: Equatable {
        let idempotencyKey: String
        let requestID: String?
    }

    var accessResult: Result<SupportDiagnosticsAccess, StubError>
    var sessionResult: Result<SupportDiagnosticsAuditEvent, StubError>
    private(set) var startedSessions: [StartedSession] = []

    init(
        accessResult: Result<SupportDiagnosticsAccess, StubError>,
        sessionResult: Result<SupportDiagnosticsAuditEvent, StubError>
    ) {
        self.accessResult = accessResult
        self.sessionResult = sessionResult
    }

    func fetchAccess() async throws -> SupportDiagnosticsAccess {
        try accessResult.get()
    }

    func startSession(
        idempotencyKey: String,
        requestID: String?
    ) async throws -> SupportDiagnosticsAuditEvent {
        startedSessions.append(.init(idempotencyKey: idempotencyKey, requestID: requestID))
        return try sessionResult.get()
    }
}

private enum StubError: Error {
    case transport
}
