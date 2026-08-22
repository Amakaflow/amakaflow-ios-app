import Combine
import XCTest
@testable import AmakaFlowCompanion

final class DebugLogServiceDiagnosticScopeTests: DiagnosticEventStoreTestCase {
    @MainActor
    func testDiagnosticEventsForCurrentAccountRecomputesScopeWhenCachedHashIsStale() async throws {
        let store = makeStore()
        let redactor = DiagnosticRedactor()
        let accountAHash = try XCTUnwrap(redactor.hashAccountIdentifier("account-a"))
        let accountBHash = try XCTUnwrap(redactor.hashAccountIdentifier("account-b"))
        try await store.append(event("account-a", at: now, message: "account-a-detail", accountHash: accountAHash))
        try await store.append(event(
            "account-b",
            at: now.addingTimeInterval(1),
            message: "account-b-detail",
            accountHash: accountBHash
        ))

        var currentAccount: String? = "account-a"
        let authChanges = CurrentValueSubject<String?, Never>("account-a")
        let service = DebugLogService(
            store: store,
            redactor: redactor,
            accountIdentifierProvider: { currentAccount },
            accountIdentifierPublisher: { authChanges.eraseToAnyPublisher() }
        )
        await service.waitForPendingWrites()
        XCTAssertEqual(service.currentAccountHash, accountAHash)

        currentAccount = "account-b"

        let events = try await service.diagnosticEventsForCurrentAccount()

        XCTAssertEqual(events.map(\.message), ["account-b-detail"])
        XCTAssertEqual(service.currentAccountHash, accountBHash)
    }
}
