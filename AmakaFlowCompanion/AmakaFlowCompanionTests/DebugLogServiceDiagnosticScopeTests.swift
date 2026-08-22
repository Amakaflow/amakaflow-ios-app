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

    @MainActor
    func testDiagnosticEventsForCurrentAccountFailsClosedWhenAccountChangesDuringSnapshotRead() async throws {
        let redactor = DiagnosticRedactor()
        let accountAHash = try XCTUnwrap(redactor.hashAccountIdentifier("account-a"))
        let accountBHash = try XCTUnwrap(redactor.hashAccountIdentifier("account-b"))
        let oldAccountEvent = event(
            "account-a",
            at: now,
            message: "account-a-detail",
            accountHash: accountAHash
        )
        var currentAccount: String? = "account-a"
        let authChanges = CurrentValueSubject<String?, Never>("account-a")
        let suspendedReader = SuspendedDiagnosticSnapshotReader()
        defer { suspendedReader.cancelOutstandingWaiters() }
        let service = DebugLogService(
            store: makeStore(),
            redactor: redactor,
            accountIdentifierProvider: { currentAccount },
            accountIdentifierPublisher: { authChanges.eraseToAnyPublisher() },
            diagnosticSnapshotReader: suspendedReader.snapshot
        )
        await service.waitForPendingWrites()
        XCTAssertEqual(service.currentAccountHash, accountAHash)

        let readTask = Task { try await service.diagnosticEventsForCurrentAccount() }
        await suspendedReader.waitUntilSnapshotStarted()
        XCTAssertEqual(suspendedReader.requestedScope, .account(accountAHash))

        currentAccount = "account-b"
        suspendedReader.resume(returning: [oldAccountEvent])

        let events = try await readTask.value

        XCTAssertEqual(events, [])
        XCTAssertEqual(service.currentAccountHash, accountBHash)
    }
}

@MainActor
private final class SuspendedDiagnosticSnapshotReader {
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var snapshotContinuation: CheckedContinuation<[DiagnosticEvent], Error>?
    private(set) var requestedScope: DiagnosticSnapshotScope?

    func snapshot(_ scope: DiagnosticSnapshotScope) async throws -> [DiagnosticEvent] {
        requestedScope = scope
        return try await withCheckedThrowingContinuation { continuation in
            snapshotContinuation = continuation
            startContinuation?.resume()
            startContinuation = nil
        }
    }

    func waitUntilSnapshotStarted() async {
        guard snapshotContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func resume(returning events: [DiagnosticEvent]) {
        snapshotContinuation?.resume(returning: events)
        snapshotContinuation = nil
    }

    func cancelOutstandingWaiters() {
        startContinuation?.resume()
        startContinuation = nil
        snapshotContinuation?.resume(throwing: CancellationError())
        snapshotContinuation = nil
    }
}
