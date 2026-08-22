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
    let title: String
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
        title: String? = nil,
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
        self.title = title ?? name
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
            title: title,
            details: message,
            metadata: metadata.isEmpty ? nil : metadata
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case severity
        case category
        case name
        case title
        case message
        case metadata
        case requestID
        case sentryEventID
        case sentryTraceID
        case accountHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        severity = try container.decode(DiagnosticEventSeverity.self, forKey: .severity)
        category = try container.decode(DiagnosticEventCategory.self, forKey: .category)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? name
        message = try container.decode(String.self, forKey: .message)
        metadata = try container.decode([String: String].self, forKey: .metadata)
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
        sentryEventID = try container.decodeIfPresent(String.self, forKey: .sentryEventID)
        sentryTraceID = try container.decodeIfPresent(String.self, forKey: .sentryTraceID)
        accountHash = try container.decodeIfPresent(String.self, forKey: .accountHash)
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
