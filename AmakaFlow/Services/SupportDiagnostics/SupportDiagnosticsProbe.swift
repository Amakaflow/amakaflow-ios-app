import Foundation

nonisolated enum SupportDiagnosticsProbeID: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case appBuildDevice = "app_build_device"
    case configuredHosts = "configured_hosts"
    case clerkSession = "clerk_session"
    case reachabilityHealth = "reachability_health"
    case watchConnectivity = "watch_connectivity"
    case healthKitAuthorization = "healthkit_authorization"
    case queues
    case databaseHealth = "database_health"
    case grantState = "grant_state"
    case correlationIDs = "correlation_ids"
}

nonisolated enum SupportDiagnosticsSafeErrorCode: String, Codable, Equatable, Sendable {
    case probeFailed = "PROBE_FAILED"
    case probeTimedOut = "PROBE_TIMED_OUT"
    case configurationUnavailable = "CONFIGURATION_UNAVAILABLE"
    case authUnavailable = "AUTH_UNAVAILABLE"
    case networkUnavailable = "NETWORK_UNAVAILABLE"
    case watchUnavailable = "WATCH_UNAVAILABLE"
    case healthKitUnavailable = "HEALTHKIT_UNAVAILABLE"
    case queueUnavailable = "QUEUE_UNAVAILABLE"
    case databaseUnavailable = "DATABASE_UNAVAILABLE"
}

nonisolated struct SupportDiagnosticsDisplayField: Codable, Equatable, Sendable {
    let label: String
    let value: String
}

nonisolated enum SupportDiagnosticsAvailability: Codable, Equatable, Sendable {
    case available(fields: [SupportDiagnosticsDisplayField])
    case unavailable(errorCode: SupportDiagnosticsSafeErrorCode, correlationID: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case fields
        case errorCode
        case correlationID
    }

    private enum AvailabilityType: String, Codable {
        case available
        case unavailable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(AvailabilityType.self, forKey: .type) {
        case .available:
            let fields = try container.decode([SupportDiagnosticsDisplayField].self, forKey: .fields)
            self = .available(fields: fields)
        case .unavailable:
            let errorCode = try container.decode(SupportDiagnosticsSafeErrorCode.self, forKey: .errorCode)
            let correlationID = try container.decodeIfPresent(String.self, forKey: .correlationID)
            self = .unavailable(errorCode: errorCode, correlationID: correlationID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .available(let fields):
            try container.encode(AvailabilityType.available, forKey: .type)
            try container.encode(fields, forKey: .fields)
        case .unavailable(let errorCode, let correlationID):
            try container.encode(AvailabilityType.unavailable, forKey: .type)
            try container.encode(errorCode, forKey: .errorCode)
            try container.encodeIfPresent(correlationID, forKey: .correlationID)
        }
    }
}

nonisolated struct SupportDiagnosticsProbeResult: Codable, Equatable, Sendable {
    let id: SupportDiagnosticsProbeID
    let title: String
    let availability: SupportDiagnosticsAvailability
}

nonisolated struct SupportDiagnosticsSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    let results: [SupportDiagnosticsProbeResult]

    func result(for id: SupportDiagnosticsProbeID) -> SupportDiagnosticsProbeResult? {
        results.first { $0.id == id }
    }
}

nonisolated struct SupportDiagnosticsProbeError: Error, Equatable, Sendable {
    let code: SupportDiagnosticsSafeErrorCode
    let correlationID: String?

    init(code: SupportDiagnosticsSafeErrorCode, correlationID: String? = nil) {
        self.code = code
        self.correlationID = correlationID
    }
}

nonisolated protocol SupportDiagnosticsProbe: Sendable {
    var id: SupportDiagnosticsProbeID { get }
    var title: String { get }
    var timeout: Duration { get }

    func run() async throws -> [SupportDiagnosticsDisplayField]
}
