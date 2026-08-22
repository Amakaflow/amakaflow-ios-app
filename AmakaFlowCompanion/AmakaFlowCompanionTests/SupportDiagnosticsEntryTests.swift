import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class SupportDiagnosticsEntryTests: XCTestCase {
    func testSevenTapsInsideFixedTwoSecondWindowTriggersEntry() {
        var sequence = SupportDiagnosticsTapSequence()
        let start = Date(timeIntervalSince1970: 1_000)

        for offset in [0.0, 0.3, 0.6, 0.9, 1.2, 1.5] {
            XCTAssertFalse(sequence.registerTap(at: start.addingTimeInterval(offset)))
        }

        XCTAssertTrue(sequence.registerTap(at: start.addingTimeInterval(1.8)))
    }

    func testTapWindowDoesNotSlideForwardAfterEachTap() {
        var sequence = SupportDiagnosticsTapSequence()
        let start = Date(timeIntervalSince1970: 1_000)

        for offset in [0.0, 0.35, 0.7, 1.05, 1.4, 1.75] {
            XCTAssertFalse(sequence.registerTap(at: start.addingTimeInterval(offset)))
        }

        XCTAssertFalse(sequence.registerTap(at: start.addingTimeInterval(2.1)))
    }

    func testSeventhTapPresentsCenterOnlyAfterSessionAuditSucceeds() async {
        let client = EntrySupportDiagnosticsClient(
            accessResults: [.success(authorizedAccess())],
            sessionResults: [.success(sessionEvent())]
        )
        let viewModel = makeViewModel(client: client)
        let start = Date(timeIntervalSince1970: 1_000)

        for tap in 0..<6 {
            await viewModel.registerVersionTap(at: start.addingTimeInterval(Double(tap) * 0.2))
            XCTAssertFalse(viewModel.isPresented)
        }
        await viewModel.registerVersionTap(at: start.addingTimeInterval(1.2))

        XCTAssertTrue(viewModel.isPresented)
        let sessionStartCount = await client.sessionStartCount
        XCTAssertEqual(sessionStartCount, 1)
    }

    func testSeventhTapDoesNotPresentCenterWhenSessionAuditFails() async {
        let client = EntrySupportDiagnosticsClient(
            accessResults: [.success(authorizedAccess())],
            sessionResults: [.failure(.transport)]
        )
        let viewModel = makeViewModel(client: client)

        await triggerEntry(on: viewModel)

        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(viewModel.state, .failed(.sessionStartFailed))
    }

    func testSecondTapSequenceDoesNotStartOverlappingAccessCheck() async {
        let accessGate = DiagnosticsAccessGate()
        let client = EntrySupportDiagnosticsClient(
            accessResults: [.success(authorizedAccess()), .success(authorizedAccess())],
            sessionResults: [.success(sessionEvent()), .success(sessionEvent())],
            accessGate: accessGate
        )
        let viewModel = makeViewModel(client: client)

        let firstEntry = Task { await triggerEntry(on: viewModel) }
        await accessGate.waitUntilEntered()
        let secondEntry = Task { await triggerEntry(on: viewModel) }
        await Task.yield()

        let accessCheckCount = await client.accessCheckCount
        XCTAssertEqual(accessCheckCount, 1, "A second tap sequence must not overlap the in-flight access check")

        await accessGate.release()
        await firstEntry.value
        await secondEntry.value
    }

    func testPollingRefreshesAfterSixtySecondsAndDismissesRevokedSession() async {
        let client = EntrySupportDiagnosticsClient(
            accessResults: [.success(authorizedAccess()), .success(disabledAccess())],
            sessionResults: [.success(sessionEvent())]
        )
        let sleeper = RecordingDiagnosticsSleeper()
        let viewModel = makeViewModel(
            client: client,
            sleep: { duration in await sleeper.sleep(for: duration) }
        )
        await triggerEntry(on: viewModel)

        await viewModel.pollWhilePresented()

        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(viewModel.state, .locked(.notGranted))
        let sleepDurations = await sleeper.durations
        let accessCheckCount = await client.accessCheckCount
        XCTAssertEqual(sleepDurations, [.seconds(60)])
        XCTAssertEqual(accessCheckCount, 2)
    }

    func testForegroundRefreshRunsOnlyWhileCenterIsPresented() async {
        let client = EntrySupportDiagnosticsClient(
            accessResults: [.success(authorizedAccess()), .success(disabledAccess())],
            sessionResults: [.success(sessionEvent())]
        )
        let viewModel = makeViewModel(client: client)

        await viewModel.appDidBecomeActive()
        let checksBeforeEntry = await client.accessCheckCount
        XCTAssertEqual(checksBeforeEntry, 0)

        await triggerEntry(on: viewModel)
        await viewModel.appDidBecomeActive()

        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(viewModel.state, .locked(.notGranted))
        let checksAfterForeground = await client.accessCheckCount
        XCTAssertEqual(checksAfterForeground, 2)
    }

    func testAccountChangeDismissesCenterAndLocksSession() async {
        let client = EntrySupportDiagnosticsClient(
            accessResults: [.success(authorizedAccess())],
            sessionResults: [.success(sessionEvent())]
        )
        let viewModel = makeViewModel(client: client)
        viewModel.updateAccount("account-a")
        await triggerEntry(on: viewModel)

        viewModel.updateAccount("account-b")

        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(viewModel.state, .locked(.accountChanged))
    }

    func testSignOutDismissesCenterAndLocksSession() async {
        let client = EntrySupportDiagnosticsClient(
            accessResults: [.success(authorizedAccess())],
            sessionResults: [.success(sessionEvent())]
        )
        let viewModel = makeViewModel(client: client)
        viewModel.updateAccount("account-a")
        await triggerEntry(on: viewModel)

        viewModel.updateAccount(nil)

        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(viewModel.state, .locked(.signedOut))
    }

    private func triggerEntry(on viewModel: SupportDiagnosticsViewModel) async {
        let start = Date(timeIntervalSince1970: 1_000)
        for tap in 0..<7 {
            await viewModel.registerVersionTap(at: start.addingTimeInterval(Double(tap) * 0.2))
        }
    }

    private func makeViewModel(
        client: EntrySupportDiagnosticsClient,
        sleep: @escaping SupportDiagnosticsViewModel.Sleep = { _ in }
    ) -> SupportDiagnosticsViewModel {
        SupportDiagnosticsViewModel(
            session: SupportDiagnosticsSession(
                client: client,
                idempotencyKeyProvider: { "entry-session-key" },
                requestIDProvider: { "entry-request-id" }
            ),
            sleep: sleep
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

private actor RecordingDiagnosticsSleeper {
    private(set) var durations: [Duration] = []

    func sleep(for duration: Duration) {
        durations.append(duration)
    }
}

private actor EntrySupportDiagnosticsClient: SupportDiagnosticsAccessProviding {
    private var accessResults: [Result<SupportDiagnosticsAccess, EntryStubError>]
    private var sessionResults: [Result<SupportDiagnosticsAuditEvent, EntryStubError>]
    private let accessGate: DiagnosticsAccessGate?
    private(set) var accessCheckCount = 0
    private(set) var sessionStartCount = 0

    init(
        accessResults: [Result<SupportDiagnosticsAccess, EntryStubError>],
        sessionResults: [Result<SupportDiagnosticsAuditEvent, EntryStubError>],
        accessGate: DiagnosticsAccessGate? = nil
    ) {
        self.accessResults = accessResults
        self.sessionResults = sessionResults
        self.accessGate = accessGate
    }

    func fetchAccess() async throws -> SupportDiagnosticsAccess {
        accessCheckCount += 1
        await accessGate?.enterAndWait()
        return try accessResults.removeFirst().get()
    }

    func startSession(
        idempotencyKey: String,
        requestID: String?
    ) async throws -> SupportDiagnosticsAuditEvent {
        sessionStartCount += 1
        return try sessionResults.removeFirst().get()
    }
}

private actor DiagnosticsAccessGate {
    private var hasEntered = false
    private var isReleased = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func enterAndWait() async {
        hasEntered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters = []
        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters = []
    }
}

private enum EntryStubError: Error {
    case transport
}
