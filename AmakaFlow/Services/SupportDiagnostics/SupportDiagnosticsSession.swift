import Combine
import Foundation

nonisolated enum SupportDiagnosticsLockReason: Equatable, Sendable {
    case notChecked
    case notGranted
    case expired
    case malformedGrant
    case signedOut
    case accountChanged
}

nonisolated enum SupportDiagnosticsFailure: Equatable, Sendable {
    case accessCheckFailed
    case sessionStartFailed
}

nonisolated enum SupportDiagnosticsSessionState: Equatable, Sendable {
    case locked(SupportDiagnosticsLockReason)
    case checking
    case authorized(SupportDiagnosticsAuthorization)
    case failed(SupportDiagnosticsFailure)
}

@MainActor
final class SupportDiagnosticsSession: ObservableObject {
    typealias IdempotencyKeyProvider = () -> String
    typealias RequestIDProvider = () -> String?

    @Published private(set) var state: SupportDiagnosticsSessionState = .locked(.notChecked)

    private let client: any SupportDiagnosticsAccessProviding
    private let idempotencyKeyProvider: IdempotencyKeyProvider
    private let requestIDProvider: RequestIDProvider
    private var sessionIdempotencyKey: String?

    init(
        client: any SupportDiagnosticsAccessProviding,
        idempotencyKeyProvider: @escaping IdempotencyKeyProvider = { UUID().uuidString },
        requestIDProvider: @escaping RequestIDProvider = { UUID().uuidString }
    ) {
        self.client = client
        self.idempotencyKeyProvider = idempotencyKeyProvider
        self.requestIDProvider = requestIDProvider
    }

    var isAuthorized: Bool {
        if case .authorized = state { return true }
        return false
    }

    func checkAndStart() async {
        state = .checking

        let access: SupportDiagnosticsAccess
        do {
            access = try await client.fetchAccess()
        } catch {
            state = .failed(.accessCheckFailed)
            return
        }

        guard access.enabled else {
            state = .locked(.notGranted)
            return
        }
        guard let authorization = access.authorization else {
            state = .locked(access.expiresAt.map { $0 <= access.serverTime } == true ? .expired : .malformedGrant)
            return
        }

        let idempotencyKey = sessionIdempotencyKey ?? idempotencyKeyProvider()
        sessionIdempotencyKey = idempotencyKey
        do {
            _ = try await client.startSession(
                idempotencyKey: idempotencyKey,
                requestID: requestIDProvider()
            )
            state = .authorized(authorization)
        } catch {
            state = .failed(.sessionStartFailed)
        }
    }

    func refreshAccess() async {
        do {
            let access = try await client.fetchAccess()
            guard access.enabled else {
                state = .locked(.notGranted)
                return
            }
            guard let authorization = access.authorization else {
                state = .locked(access.expiresAt.map { $0 <= access.serverTime } == true ? .expired : .malformedGrant)
                return
            }
            state = .authorized(authorization)
        } catch {
            state = .failed(.accessCheckFailed)
        }
    }

    func reset(reason: SupportDiagnosticsLockReason) {
        sessionIdempotencyKey = nil
        state = .locked(reason)
    }
}
