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
    private var operationGeneration = 0

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
        let generation = beginOperation()
        state = .checking

        let access: SupportDiagnosticsAccess
        do {
            access = try await client.fetchAccess()
        } catch {
            guard operationGeneration == generation else { return }
            state = .failed(.accessCheckFailed)
            return
        }

        guard operationGeneration == generation else { return }
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
            let auditEvent = try await client.startSession(
                idempotencyKey: idempotencyKey,
                requestID: requestIDProvider()
            )
            guard operationGeneration == generation else { return }
            guard auditEvent.eventType == .sessionStarted,
                  auditEvent.outcome == .succeeded
            else {
                state = .failed(.sessionStartFailed)
                return
            }
            state = .authorized(authorization)
        } catch {
            guard operationGeneration == generation else { return }
            state = .failed(.sessionStartFailed)
        }
    }

    func refreshAccess() async {
        let generation = beginOperation()
        do {
            let access = try await client.fetchAccess()
            guard operationGeneration == generation else { return }
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
            guard operationGeneration == generation else { return }
            state = .failed(.accessCheckFailed)
        }
    }

    func reset(reason: SupportDiagnosticsLockReason) {
        operationGeneration += 1
        sessionIdempotencyKey = nil
        state = .locked(reason)
    }

    private func beginOperation() -> Int {
        operationGeneration += 1
        return operationGeneration
    }
}
