import Foundation

nonisolated enum DiagnosticEventSeverity: String, Codable, Equatable, Sendable {
    case debug
    case info
    case warning
    case error
}

nonisolated enum DiagnosticEventCategory: String, Codable, Equatable, Sendable {
    case api
    case auth
    case network
    case sync
    case completion
    case watch
    case healthKit = "health_kit"
    case storage
    case appLifecycle = "app_lifecycle"
    case operatorAction = "operator_action"
    case general
}

nonisolated struct DiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let severity: DiagnosticEventSeverity
    let category: DiagnosticEventCategory
    let name: String
    let message: String
    let metadata: [String: String]
    let requestID: String?
    let sentryEventID: String?
    let sentryTraceID: String?
    let accountHash: String?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        severity: DiagnosticEventSeverity,
        category: DiagnosticEventCategory,
        name: String,
        message: String,
        metadata: [String: String] = [:],
        requestID: String? = nil,
        sentryEventID: String? = nil,
        sentryTraceID: String? = nil,
        accountHash: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.category = category
        self.name = name
        self.message = message
        self.metadata = metadata
        self.requestID = requestID
        self.sentryEventID = sentryEventID
        self.sentryTraceID = sentryTraceID
        self.accountHash = accountHash
    }

    var projectedDebugLogEntry: DebugLogEntry {
        DebugLogEntry(
            id: id,
            timestamp: timestamp,
            type: projectedDebugLogType,
            title: name,
            details: message,
            metadata: metadata.isEmpty ? nil : metadata
        )
    }

    private var projectedDebugLogType: DebugLogType {
        switch category {
        case .api:
            return severity == .error ? .apiError : .apiSuccess
        case .watch:
            return severity == .error ? .watchError : .watchEvent
        case .completion:
            return .completionError
        case .network:
            return .networkError
        case .auth:
            return .authError
        case .sync, .healthKit, .storage, .appLifecycle, .operatorAction, .general:
            return .general
        }
    }
}
