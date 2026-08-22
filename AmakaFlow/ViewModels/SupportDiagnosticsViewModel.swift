import Combine
import Foundation

nonisolated struct SupportDiagnosticsTapSequence: Sendable {
    private static let requiredTapCount = 7
    private static let window: TimeInterval = 2

    private var firstTapAt: Date?
    private var tapCount = 0

    mutating func registerTap(at date: Date) -> Bool {
        if let firstTapAt,
           date >= firstTapAt,
           date.timeIntervalSince(firstTapAt) <= Self.window {
            tapCount += 1
        } else {
            firstTapAt = date
            tapCount = 1
        }

        guard tapCount == Self.requiredTapCount else { return false }
        reset()
        return true
    }

    mutating func reset() {
        firstTapAt = nil
        tapCount = 0
    }
}

@MainActor
final class SupportDiagnosticsViewModel: ObservableObject {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    @Published private(set) var state: SupportDiagnosticsSessionState
    @Published private(set) var isPresented = false

    private let session: SupportDiagnosticsSession
    private let sleep: Sleep
    private var tapSequence = SupportDiagnosticsTapSequence()
    private var accountID: String?

    init(
        session: SupportDiagnosticsSession,
        sleep: @escaping Sleep = { duration in
            try await Task<Never, Never>.sleep(for: duration)
        }
    ) {
        self.session = session
        self.sleep = sleep
        self.state = session.state
    }

    static func live() -> SupportDiagnosticsViewModel {
        let client: any SupportDiagnosticsAccessProviding =
            SupportDiagnosticsAccessClient.live() ?? UnavailableDiagnosticsClient()
        return SupportDiagnosticsViewModel(session: SupportDiagnosticsSession(client: client))
    }

    var authorization: SupportDiagnosticsAuthorization? {
        guard case .authorized(let authorization) = state else { return nil }
        return authorization
    }

    var currentAccountID: String? {
        accountID
    }

    func registerVersionTap(at date: Date = Date()) async {
        guard tapSequence.registerTap(at: date) else { return }
        guard session.state != .checking else { return }

        await session.checkAndStart()
        synchronizePresentation()
    }

    func appDidBecomeActive() async {
        guard isPresented else { return }
        await refreshAccess()
    }

    func pollWhilePresented() async {
        while isPresented, !Task.isCancelled {
            do {
                try await sleep(.seconds(60))
            } catch {
                return
            }
            guard isPresented, !Task.isCancelled else { return }
            await refreshAccess()
        }
    }

    func updateAccount(_ newAccountID: String?) {
        defer { accountID = newAccountID }

        guard let newAccountID else {
            reset(reason: .signedOut)
            return
        }
        guard let accountID, accountID != newAccountID else { return }
        reset(reason: .accountChanged)
    }

    func dismissCenter() {
        reset(reason: .notChecked)
    }

    private func refreshAccess() async {
        await session.refreshAccess()
        synchronizePresentation()
    }

    private func reset(reason: SupportDiagnosticsLockReason) {
        tapSequence.reset()
        session.reset(reason: reason)
        synchronizePresentation()
    }

    private func synchronizePresentation() {
        state = session.state
        isPresented = session.isAuthorized
    }
}

private nonisolated struct UnavailableDiagnosticsClient: SupportDiagnosticsAccessProviding {
    func fetchAccess() async throws -> SupportDiagnosticsAccess {
        throw SupportDiagnosticsClientError.invalidResponse
    }

    func startSession(
        idempotencyKey: String,
        requestID: String?
    ) async throws -> SupportDiagnosticsAuditEvent {
        throw SupportDiagnosticsClientError.invalidResponse
    }
}
