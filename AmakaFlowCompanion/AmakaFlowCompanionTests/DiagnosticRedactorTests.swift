import XCTest
@testable import AmakaFlowCompanion

final class DiagnosticRedactorTests: XCTestCase {
    func testFreeFormDisplayTitleIsRedactedAndStoredUnderStableEventName() {
        let unsafeTitle = """
        jane@example.com Bearer redaction-fixture-token \
        eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJyZWRhY3Rpb24ifQ.signature \
        https://example.test/profile?token=query-secret
        """
        let event = DiagnosticRedactor().redact(
            category: .general,
            severity: .info,
            name: "general.event",
            displayTitle: unsafeTitle,
            message: "Details for jane@example.com with Authorization: Bearer details-token",
            metadata: ["Context": "https://example.test/path?email=jane@example.com"],
            timestamp: Self.fixedDate
        )

        XCTAssertEqual(event.name, "general.event")
        XCTAssertFalse(event.name.contains("jane@example.com"))
        XCTAssertFalse(event.name.contains("redaction-fixture-token"))
        XCTAssertFalse(event.name.contains("eyJhbGci"))
        XCTAssertFalse(event.name.contains("query-secret"))

        let projection = event.projectedDebugLogEntry
        XCTAssertFalse(projection.copyableText.contains("jane@example.com"))
        XCTAssertFalse(projection.copyableText.contains("redaction-fixture-token"))
        XCTAssertFalse(projection.copyableText.contains("eyJhbGci"))
        XCTAssertFalse(projection.copyableText.contains("query-secret"))
        XCTAssertFalse(projection.copyableText.contains("details-token"))
    }

    func testAPIRedactionDropsBodiesQueriesAndSensitiveMetadataWhileKeepingCorrelationFields() {
        let event = DiagnosticRedactor().redact(
            category: .api,
            severity: .error,
            name: "api.request.failed",
            message: """
            Authorization: Bearer super-secret-token \
            user david@example.com called https://api.test/v1/workouts?token=abc&email=david@example.com \
            jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.signature
            """,
            metadata: [
                "Endpoint": "/v1/workouts?token=abc&email=david@example.com",
                "Method": "POST",
                "Status": "500",
                "Response": #"{"access_token":"raw-body"}"#,
                "Authorization": "Bearer raw-token",
                "request_id": "req-safe-1",
                "duration_ms": "42",
                "retry_count": "2",
                "response_size": "128"
            ],
            requestID: "req-safe-1",
            sentryEventID: "sentry-safe-1",
            accountIdentifier: "user_raw_123",
            timestamp: Self.fixedDate
        )

        XCTAssertEqual(event.category, .api)
        XCTAssertEqual(event.severity, .error)
        XCTAssertEqual(event.name, "api.request.failed")
        XCTAssertEqual(event.metadata["Endpoint"], "/v1/workouts")
        XCTAssertEqual(event.metadata["Method"], "POST")
        XCTAssertEqual(event.metadata["Status"], "500")
        XCTAssertEqual(event.metadata["request_id"], "req-safe-1")
        XCTAssertEqual(event.metadata["duration_ms"], "42")
        XCTAssertEqual(event.metadata["retry_count"], "2")
        XCTAssertEqual(event.metadata["response_size"], "128")
        XCTAssertNil(event.metadata["Response"])
        XCTAssertNil(event.metadata["Authorization"])
        XCTAssertEqual(event.requestID, "req-safe-1")
        XCTAssertEqual(event.sentryEventID, "sentry-safe-1")
        XCTAssertTrue(event.accountHash?.hasPrefix("sha256:") == true)
        XCTAssertFalse(event.accountHash?.contains("user_raw_123") == true)

        let persistedText = event.message + event.metadata.description
        XCTAssertFalse(persistedText.contains("super-secret-token"))
        XCTAssertFalse(persistedText.contains("david@example.com"))
        XCTAssertFalse(persistedText.contains("access_token"))
        XCTAssertFalse(persistedText.contains("eyJhbGci"))
        XCTAssertFalse(persistedText.contains("token=abc"))
    }

    func testFallbackTextRedactsCookiesKnownSecretsEmailsAndURLQueryValues() {
        let event = DiagnosticRedactor().redact(
            category: .auth,
            severity: .error,
            name: "auth.refresh.failed",
            message: "Cookie: session=abc; clerk_secret_12345 emailed jane@example.com using https://example.test/path?secret=value",
            metadata: [
                "Context": "Authorization Bearer hidden-token",
                "email": "jane@example.com",
                "token": "hidden-token",
                "unknown": "drop-me"
            ],
            timestamp: Self.fixedDate
        )

        XCTAssertEqual(event.metadata["Context"], "Authorization Bearer [REDACTED]")
        XCTAssertNil(event.metadata["email"])
        XCTAssertNil(event.metadata["token"])
        XCTAssertNil(event.metadata["unknown"])
        XCTAssertFalse(event.message.contains("session=abc"))
        XCTAssertFalse(event.message.contains("clerk_secret_12345"))
        XCTAssertFalse(event.message.contains("jane@example.com"))
        XCTAssertFalse(event.message.contains("secret=value"))
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_777_000_000)
}
