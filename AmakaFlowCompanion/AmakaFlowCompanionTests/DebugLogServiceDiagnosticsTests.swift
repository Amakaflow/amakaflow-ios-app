import Combine
import XCTest
@testable import AmakaFlowCompanion

final class DebugLogServiceDiagnosticsTests: DiagnosticEventStoreTestCase {
    @MainActor
    func testDebugLogServiceFacadeProjectsSanitizedEventsAndPreservesStatusAndRequestCorrelation() async throws {
        let store = makeStore()
        let authChanges = CurrentValueSubject<String?, Never>("debug-account")
        let service = DebugLogService(
            store: store,
            accountIdentifierProvider: { "debug-account" },
            accountIdentifierPublisher: { authChanges.eraseToAnyPublisher() }
        )

        service.logAPIError(
            endpoint: "/v1/coach?token=abc",
            method: "POST",
            statusCode: 503,
            response: #"{"access_token":"raw-body"}"#,
            error: nil,
            requestID: "req-debug-1"
        )

        await service.waitForPendingWrites()

        let entry = try XCTUnwrap(service.entries.first)
        XCTAssertEqual(entry.type, .apiError)
        XCTAssertEqual(entry.metadata?["Status"], "503")
        XCTAssertEqual(entry.metadata?["request_id"], "req-debug-1")
        XCTAssertNil(entry.metadata?["Response"])
        XCTAssertFalse(entry.copyableText.contains("raw-body"))
        XCTAssertFalse(entry.copyableText.contains("token=abc"))
        XCTAssertEqual(SupportDiagnosticsCorrelationIdentifiers.fromDebugLogEntries(service.entries).requestID, "req-debug-1")
    }

    @MainActor
    func testDebugLogServiceScopesDisplayedCopiedAndPersistedEntriesToCurrentAccount() async throws {
        let store = makeStore()
        var currentAccount: String? = "account-a"
        let authChanges = CurrentValueSubject<String?, Never>("account-a")
        let service = DebugLogService(
            store: store,
            accountIdentifierProvider: { currentAccount },
            accountIdentifierPublisher: { authChanges.eraseToAnyPublisher() }
        )

        service.log("Account A title", details: "account-a-only-detail")
        await service.waitForPendingWrites()
        XCTAssertTrue(service.getAllEntriesAsText().contains("account-a-only-detail"))

        currentAccount = "account-b"
        authChanges.send("account-b")
        await service.waitForPendingWrites()
        XCTAssertFalse(service.getAllEntriesAsText().contains("account-a-only-detail"))
        XCTAssertTrue(service.entries.isEmpty)

        service.log("Account B title", details: "account-b-only-detail")
        await service.waitForPendingWrites()
        XCTAssertTrue(service.getAllEntriesAsText().contains("account-b-only-detail"))
        XCTAssertFalse(service.getAllEntriesAsText().contains("account-a-only-detail"))

        currentAccount = "account-a"
        authChanges.send("account-a")
        await service.waitForPendingWrites()
        XCTAssertTrue(service.getAllEntriesAsText().contains("account-a-only-detail"))
        XCTAssertFalse(service.getAllEntriesAsText().contains("account-b-only-detail"))
    }

    @MainActor
    func testDebugLogServiceAuthChangesScopeAutomaticallyAndFailClosed() async throws {
        let store = makeStore()
        let redactor = DiagnosticRedactor()
        try await store.append(event("legacy-nil", at: now, message: "legacy-nil-detail"))
        try await store.append(event(
            "account-a",
            at: now.addingTimeInterval(1),
            message: "account-a-detail",
            accountHash: redactor.hashAccountIdentifier("account-a")
        ))
        try await store.append(event(
            "account-b",
            at: now.addingTimeInterval(2),
            message: "account-b-detail",
            accountHash: redactor.hashAccountIdentifier("account-b")
        ))

        var currentAccount: String?
        let authChanges = CurrentValueSubject<String?, Never>(nil)
        let service = DebugLogService(
            store: store,
            accountIdentifierProvider: { currentAccount },
            accountIdentifierPublisher: { authChanges.eraseToAnyPublisher() }
        )

        await service.waitForPendingWrites()
        XCTAssertTrue(service.entries.isEmpty)
        XCTAssertFalse(service.getAllEntriesAsText().contains("legacy-nil-detail"))
        XCTAssertFalse(service.getAllEntriesAsText().contains("account-a-detail"))
        XCTAssertFalse(service.getAllEntriesAsText().contains("account-b-detail"))

        currentAccount = "account-b"
        authChanges.send("account-b")
        await service.waitForPendingWrites()
        XCTAssertEqual(service.entries.map(\.details), ["account-b-detail"])
        XCTAssertFalse(service.getAllEntriesAsText().contains("legacy-nil-detail"))
        XCTAssertFalse(service.getAllEntriesAsText().contains("account-a-detail"))

        currentAccount = nil
        authChanges.send(nil)
        XCTAssertTrue(service.entries.isEmpty)
        XCTAssertFalse(service.getAllEntriesAsText().contains("account-b-detail"))

        currentAccount = "account-a"
        authChanges.send("account-a")
        await service.waitForPendingWrites()
        XCTAssertEqual(service.entries.map(\.details), ["account-a-detail"])

        currentAccount = "account-b"
        authChanges.send("account-b")
        XCTAssertTrue(service.entries.isEmpty)
        XCTAssertFalse(service.getAllEntriesAsText().contains("account-a-detail"))
        await service.waitForPendingWrites()
        XCTAssertEqual(service.entries.map(\.details), ["account-b-detail"])
    }

    @MainActor
    func testDebugLogServiceCurrentNonAPIBodyLikeMessagesAreOmittedAcrossFacades() async throws {
        let store = makeStore()
        let redactor = DiagnosticRedactor()
        let account = "body-redaction-account"
        let authChanges = CurrentValueSubject<String?, Never>(account)
        let service = DebugLogService(
            store: store,
            accountIdentifierProvider: { account },
            accountIdentifierPublisher: { authChanges.eraseToAnyPublisher() }
        )

        service.log(
            "General import failed",
            details: """
            {
              "customer": "Jane Athlete",
              "profile": {"name": "Jane Athlete"},
              "health": {"hrv": 42},
              "location": {"lat": 37.7, "lng": -122.4}
            }
            """,
            metadata: ["Context": "manual import"]
        )
        service.logNetworkError(
            error: NSError(
                domain: "network",
                code: 502,
                userInfo: [
                    NSLocalizedDescriptionKey: "Raw response body carried customer profile payload for Jane Athlete"
                ]
            ),
            context: "sync"
        )
        service.logAuthError(
            details: "Auth request body contained profile, health, and location payload for Jane Athlete",
            context: "session refresh"
        )
        await service.waitForPendingWrites()

        let accountHash = try XCTUnwrap(redactor.hashAccountIdentifier(account))
        let events = try await store.snapshot(.account(accountHash))
        XCTAssertEqual(Set(events.map(\.name)), ["auth.error", "network.error", "general.event"])
        XCTAssertEqual(Set(events.map(\.message)), [DiagnosticRedactor.omittedBodyMessage])
        XCTAssertEqual(Set(service.entries.map(\.details)), [DiagnosticRedactor.omittedBodyMessage])

        let persistedText = events.map { event in
            event.message + event.metadata.description
        }.joined(separator: "\n")
        let copyText = service.getAllEntriesAsText()
        for unsafeValue in ["Jane Athlete", "\"customer\"", "\"profile\"", "\"health\"", "\"location\"", "37.7", "-122.4"] {
            XCTAssertFalse(persistedText.contains(unsafeValue))
            XCTAssertFalse(copyText.contains(unsafeValue))
        }
    }

    @MainActor
    func testDebugLogServiceCurrentSafeNonAPIMessageSurvivesSanitization() async throws {
        let store = makeStore()
        let redactor = DiagnosticRedactor()
        let account = "safe-message-account"
        let authChanges = CurrentValueSubject<String?, Never>(account)
        let service = DebugLogService(
            store: store,
            accountIdentifierProvider: { account },
            accountIdentifierPublisher: { authChanges.eraseToAnyPublisher() }
        )

        service.log(
            "Sync retry scheduled",
            details: "Workout sync retry scheduled after transient timeout",
            metadata: ["Context": "background sync"]
        )
        await service.waitForPendingWrites()

        let accountHash = try XCTUnwrap(redactor.hashAccountIdentifier(account))
        let events = try await store.snapshot(.account(accountHash))
        XCTAssertEqual(events.map(\.name), ["general.event"])
        XCTAssertEqual(events.first?.message, "Workout sync retry scheduled after transient timeout")
        XCTAssertEqual(service.entries.first?.details, "Workout sync retry scheduled after transient timeout")
        XCTAssertTrue(service.getAllEntriesAsText().contains("Workout sync retry scheduled after transient timeout"))
    }

    @MainActor
    func testClearLogIsOrderedAfterEarlierPendingAppends() async throws {
        let store = makeStore(maxBytes: 100_000)
        let account = "clear-log-account"
        let authChanges = CurrentValueSubject<String?, Never>(account)
        let service = DebugLogService(
            store: store,
            accountIdentifierProvider: { account },
            accountIdentifierPublisher: { authChanges.eraseToAnyPublisher() }
        )

        for index in 0..<200 {
            service.log(
                "Clear race \(index)",
                details: String(repeating: "payload-\(index)", count: 100)
            )
        }
        service.clearLog()
        await service.waitForPendingWrites()

        let persisted = try await store.snapshot(.unscopedForMigrationOnly)
        XCTAssertEqual(persisted, [])
        XCTAssertTrue(service.entries.isEmpty)
    }
}
