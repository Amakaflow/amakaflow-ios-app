import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class SupportDiagnosticsSessionTests: XCTestCase {
    func testCheckAndStartAuthorizesOnlyAfterSessionAuditSucceeds() async throws {
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

        let authorization = try XCTUnwrap(access.authorization, "The enabled fixture must contain authorization")
        XCTAssertEqual(session.state, .authorized(authorization), "A successful audit must authorize the returned grant")
        XCTAssertEqual(client.startedSessions, [
            .init(idempotencyKey: "stable-session-key", requestID: "request-123")
        ], "Session start must forward one stable idempotency key and request ID")
    }

    func testCheckAndStartKeepsDisabledAccountLockedWithoutStartingAudit() async {
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(disabledAccess()),
            sessionResult: .success(sessionEvent())
        )
        let session = SupportDiagnosticsSession(client: client)

        await session.checkAndStart()

        XCTAssertEqual(session.state, .locked(.notGranted), "A disabled grant must remain locked")
        XCTAssertTrue(client.startedSessions.isEmpty, "Disabled access must not start an audit session")
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

        XCTAssertEqual(session.state, .locked(.expired), "A grant expired at server time must remain locked")
        XCTAssertTrue(client.startedSessions.isEmpty, "Expired access must not start an audit session")
    }

    func testCheckAndStartFailsClosedWhenSessionAuditCannotStart() async {
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(authorizedAccess()),
            sessionResult: .failure(.transport)
        )
        let session = SupportDiagnosticsSession(client: client)

        await session.checkAndStart()

        XCTAssertEqual(session.state, .failed(.sessionStartFailed), "Audit transport failure must fail closed")
        XCTAssertFalse(session.isAuthorized, "An audit transport failure must not authorize diagnostics")
    }

    func testCheckAndStartRejectsUnsuccessfulSessionAuditEvent() async {
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(authorizedAccess()),
            sessionResult: .success(sessionEvent(outcome: .failed))
        )
        let session = SupportDiagnosticsSession(client: client)

        await session.checkAndStart()

        XCTAssertEqual(
            session.state,
            .failed(.sessionStartFailed),
            "A failed session-start audit event must not authorize diagnostics"
        )
        XCTAssertFalse(
            session.isAuthorized,
            "Diagnostics must remain locked when the server reports a failed session audit"
        )
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
            ["session-key", "session-key"],
            "Retries must reuse the original idempotency key"
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

        XCTAssertEqual(session.state, .failed(.accessCheckFailed), "A failed refresh must revoke the open session")
        XCTAssertFalse(session.isAuthorized, "Refresh failure must fail closed")
    }

    func testResetImmediatelyLocksAuthorizedSession() async {
        let client = StubSupportDiagnosticsAccessClient(
            accessResult: .success(authorizedAccess()),
            sessionResult: .success(sessionEvent())
        )
        let session = SupportDiagnosticsSession(client: client)
        await session.checkAndStart()

        session.reset(reason: .signedOut)

        XCTAssertEqual(session.state, .locked(.signedOut), "Sign-out reset must lock an authorized session immediately")
    }

    func testResetPreventsPendingAccessCheckFromReauthorizingSession() async {
        let client = GatedSupportDiagnosticsAccessClient(
            access: authorizedAccess(),
            sessionEvent: sessionEvent()
        )
        let session = SupportDiagnosticsSession(client: client)
        let accessCheck = Task { await session.checkAndStart() }
        while await client.fetchCount == 0 {
            await Task.yield()
        }

        session.reset(reason: .signedOut)
        await client.releaseFetch()
        await accessCheck.value

        XCTAssertEqual(
            session.state,
            .locked(.signedOut),
            "A completed access request must not override a newer sign-out lock"
        )
    }

    func testResetPreventsPendingRefreshFromReauthorizingSession() async {
        let client = GatedSupportDiagnosticsAccessClient(
            access: authorizedAccess(),
            sessionEvent: sessionEvent(),
            isFetchReleased: true
        )
        let session = SupportDiagnosticsSession(client: client)
        await session.checkAndStart()
        await client.blockFetch()
        let refresh = Task { await session.refreshAccess() }
        while await client.fetchCount < 2 {
            await Task.yield()
        }

        session.reset(reason: .accountChanged)
        await client.releaseFetch()
        await refresh.value

        XCTAssertEqual(
            session.state,
            .locked(.accountChanged),
            "A completed refresh must not override a newer account-change lock"
        )
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

    private func sessionEvent(
        outcome: SupportDiagnosticsAuditOutcome = .succeeded
    ) -> SupportDiagnosticsAuditEvent {
        SupportDiagnosticsAuditEvent(
            auditID: UUID(uuidString: "f17f2970-e829-438f-8591-d72d6f1eeae5")!,
            eventType: .sessionStarted,
            outcome: outcome,
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

private actor GatedSupportDiagnosticsAccessClient: SupportDiagnosticsAccessProviding {
    private let access: SupportDiagnosticsAccess
    private let sessionEvent: SupportDiagnosticsAuditEvent
    private var isFetchReleased: Bool
    private(set) var fetchCount = 0

    init(
        access: SupportDiagnosticsAccess,
        sessionEvent: SupportDiagnosticsAuditEvent,
        isFetchReleased: Bool = false
    ) {
        self.access = access
        self.sessionEvent = sessionEvent
        self.isFetchReleased = isFetchReleased
    }

    func fetchAccess() async throws -> SupportDiagnosticsAccess {
        fetchCount += 1
        while !isFetchReleased {
            await Task.yield()
        }
        return access
    }

    func startSession(
        idempotencyKey: String,
        requestID: String?
    ) async throws -> SupportDiagnosticsAuditEvent {
        sessionEvent
    }

    func blockFetch() {
        isFetchReleased = false
    }

    func releaseFetch() {
        isFetchReleased = true
    }
}
