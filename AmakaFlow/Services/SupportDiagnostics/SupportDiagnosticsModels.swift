import Foundation

nonisolated enum SupportDiagnosticsRole: String, Codable, Equatable, Sendable {
    case viewer
    case operatorRole = "operator"
    case staff
}

nonisolated enum SupportDiagnosticsCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case statusRead = "status.read"
    case logsRead = "logs.read"
    case bundleExport = "bundle.export"
    case authRefresh = "auth.refresh"
    case watchReconnect = "watch.reconnect"
    case healthAuthorizationRefresh = "health.authorization.refresh"
    case syncRetry = "sync.retry"
    case completionRetry = "completion.retry"
    case queueClearLocalPending = "queue.clear.local_pending"
    case cacheClearSafe = "cache.clear.safe"
    case environmentOverrideAllowed = "environment.override.allowed"
    case simulationEnableIsolated = "simulation.enable.isolated"
    case featureOverrideAllowlisted = "feature_override.allowlisted"
}

nonisolated struct SupportDiagnosticsAuthorization: Equatable, Sendable {
    let grantID: UUID
    let role: SupportDiagnosticsRole
    let capabilities: Set<SupportDiagnosticsCapability>
    let expiresAt: Date?
    let serverTime: Date
}

nonisolated struct SupportDiagnosticsAccess: Equatable, Sendable {
    let enabled: Bool
    let grantID: UUID?
    let role: SupportDiagnosticsRole?
    let capabilities: Set<SupportDiagnosticsCapability>
    let expiresAt: Date?
    let serverTime: Date

    var authorization: SupportDiagnosticsAuthorization? {
        guard enabled, let grantID, let role else { return nil }
        if role != .staff {
            guard let expiresAt, expiresAt > serverTime else { return nil }
        } else if let expiresAt, expiresAt <= serverTime {
            return nil
        }
        return SupportDiagnosticsAuthorization(
            grantID: grantID,
            role: role,
            capabilities: capabilities,
            expiresAt: expiresAt,
            serverTime: serverTime
        )
    }
}

nonisolated enum SupportDiagnosticsAuditEventType: String, Codable, Equatable, Sendable {
    case sessionStarted = "session.started"
    case command
    case export
}

nonisolated enum SupportDiagnosticsAuditOutcome: String, Codable, Equatable, Sendable {
    case started
    case succeeded
    case failed
    case cancelled
    case presented
    case denied
}

nonisolated struct SupportDiagnosticsAuditEvent: Equatable, Sendable {
    let auditID: UUID
    let eventType: SupportDiagnosticsAuditEventType
    let outcome: SupportDiagnosticsAuditOutcome
    let createdAt: Date
}
