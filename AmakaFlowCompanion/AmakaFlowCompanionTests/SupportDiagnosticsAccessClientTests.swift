import XCTest
@testable import AmakaFlowCompanion

final class SupportDiagnosticsAccessClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = MockURLProtocol.mockSession()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    func testFetchAccessSendsAuthenticatedVersionedRequestAndIgnoresUnknownCapability() async throws {
        MockURLProtocol.setResponse(data: Data("""
        {
          "enabled": true,
          "grantId": "3b48344d-3d70-4e36-8750-e3caa43f97dc",
          "role": "viewer",
          "capabilities": ["status.read", "logs.read", "future.capability"],
          "expiresAt": "2026-08-22T20:00:00Z",
          "serverTime": "2026-08-21T20:00:00Z"
        }
        """.utf8))
        let client = makeClient()

        let access = try await client.fetchAccess()

        XCTAssertEqual(access.role, .viewer, "The access response must preserve the supported viewer role")
        XCTAssertEqual(access.capabilities, [.statusRead, .logsRead], "Unknown capabilities must be ignored")
        XCTAssertEqual(access.grantID?.uuidString.lowercased(), "3b48344d-3d70-4e36-8750-e3caa43f97dc", "The grant ID must decode unchanged")
        let request = try XCTUnwrap(MockURLProtocol.interceptedRequests.first, "Access fetch must issue one request")
        XCTAssertEqual(request.httpMethod, "GET", "Access fetch must use GET")
        XCTAssertEqual(request.url?.absoluteString, "https://mobile.test/v1/support-diagnostics/access", "Access fetch must use the versioned endpoint")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer clerk-token", "Access fetch must authenticate with Clerk")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-AmakaFlow-App-Version"), "2.4.0 (241)", "Access fetch must identify the app build")
    }

    func testFetchAccessPreservesDisabledContract() async throws {
        MockURLProtocol.setResponse(data: Data("""
        {
          "enabled": false,
          "grantId": null,
          "role": null,
          "capabilities": [],
          "expiresAt": null,
          "serverTime": "2026-08-21T20:00:00Z"
        }
        """.utf8))

        let access = try await makeClient().fetchAccess()

        XCTAssertFalse(access.enabled, "The disabled contract must remain disabled")
        XCTAssertNil(access.grantID, "Disabled access must not invent a grant ID")
        XCTAssertNil(access.role, "Disabled access must not invent a role")
        XCTAssertTrue(access.capabilities.isEmpty, "Disabled access must expose no capabilities")
    }

    func testStartSessionSendsIdempotencyAndCorrelationHeaders() async throws {
        MockURLProtocol.setResponse(data: Data("""
        {
          "auditId": "f17f2970-e829-438f-8591-d72d6f1eeae5",
          "eventType": "session.started",
          "outcome": "succeeded",
          "createdAt": "2026-08-21T20:00:01Z"
        }
        """.utf8))

        let event = try await makeClient().startSession(
            idempotencyKey: "session-key",
            requestID: "request-123"
        )

        XCTAssertEqual(event.eventType, .sessionStarted, "Session start must decode the audit event type")
        XCTAssertEqual(event.outcome, .succeeded, "Session start must decode the audit outcome")
        let request = try XCTUnwrap(MockURLProtocol.interceptedRequests.first, "Session start must issue one request")
        XCTAssertEqual(request.httpMethod, "POST", "Session start must use POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://mobile.test/v1/support-diagnostics/sessions/start",
            "Session start must use the versioned endpoint"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "session-key", "Session start must send its idempotency key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), "request-123", "Session start must send its correlation ID")
    }

    func testFetchAccessRejectsUnauthorizedResponseWithoutDecodingDependencyBody() async throws {
        MockURLProtocol.setResponse(
            statusCode: 401,
            data: Data(#"{"detail":"token contents must not be surfaced"}"#.utf8)
        )

        do {
            _ = try await makeClient().fetchAccess()
            XCTFail("Expected authentication failure")
        } catch SupportDiagnosticsClientError.authenticationRequired {
            // Expected boundary error.
        } catch {
            XCTFail("Expected authenticationRequired, got \(error)")
        }
    }

    private func makeClient() -> SupportDiagnosticsAccessClient {
        SupportDiagnosticsAccessClient(
            baseURL: URL(string: "https://mobile.test/v1")!,
            session: session,
            appVersion: "2.4.0 (241)",
            bearerTokenProvider: { "clerk-token" }
        )
    }
}
