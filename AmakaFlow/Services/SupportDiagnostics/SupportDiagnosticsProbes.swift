import CryptoKit
import Foundation

nonisolated enum SupportDiagnosticsProbes {
    static let approvedReachabilityServiceNames = [
        "Mobile BFF",
        "Mapper API",
        "Ingestor API",
        "Calendar API",
        "Chat API",
        "MCP API",
        "Strava API"
    ]

    static func live(
        authorization: SupportDiagnosticsAuthorization,
        dependencies: SupportDiagnosticsProbeDependencies = .live
    ) -> [any SupportDiagnosticsProbe] {
        [
            AppBuildDeviceProbe(),
            ConfiguredHostsProbe(),
            ClerkSessionProbe(),
            ReachabilityHealthProbe(),
            WatchConnectivityProbe(lastTransferState: dependencies.lastWatchTransferState),
            HealthKitAuthorizationProbe(),
            QueuesProbe(),
            DatabaseHealthProbe(),
            GrantStateProbe(
                authorization: authorization,
                featureOverrideState: dependencies.allowlistedFeatureOverrides
            ),
            CorrelationIDsProbe(provider: dependencies.correlationIdentifiers)
        ]
    }
}

nonisolated struct SupportDiagnosticsProbeDependencies: Sendable {
    let correlationIdentifiers: @Sendable () async -> SupportDiagnosticsCorrelationIdentifiers
    let lastWatchTransferState: @Sendable () async -> SupportDiagnosticsWatchTransferState
    let allowlistedFeatureOverrides: @Sendable () async -> SupportDiagnosticsFeatureOverrideState

    static let live = SupportDiagnosticsProbeDependencies(
        correlationIdentifiers: {
            var identifiers = SupportDiagnosticsRuntimeState.shared.correlationIdentifiers()
            let loggedIdentifiers = await MainActor.run {
                SupportDiagnosticsCorrelationIdentifiers.fromDebugLogEntries(DebugLogService.shared.entries)
            }
            identifiers.mergeMissing(with: loggedIdentifiers)
            return identifiers
        },
        lastWatchTransferState: {
            SupportDiagnosticsRuntimeState.shared.lastWatchTransferState()
        },
        allowlistedFeatureOverrides: {
            await SupportDiagnosticsFeatureOverrideReader.live.state()
        }
    )
}

nonisolated struct SupportDiagnosticsCorrelationIdentifiers: Equatable, Sendable {
    var requestID: String?
    var sentryEventID: String?
    var sentryTraceID: String?

    static let noneRecorded = SupportDiagnosticsCorrelationIdentifiers(
        requestID: nil,
        sentryEventID: nil,
        sentryTraceID: nil
    )

    mutating func mergeMissing(with other: SupportDiagnosticsCorrelationIdentifiers) {
        requestID = requestID ?? other.requestID
        sentryEventID = sentryEventID ?? other.sentryEventID
        sentryTraceID = sentryTraceID ?? other.sentryTraceID
    }

    static func fromDebugLogEntries(_ entries: [DebugLogEntry]) -> SupportDiagnosticsCorrelationIdentifiers {
        var requestID: String?
        var traceID: String?
        for entry in entries {
            guard let metadata = entry.metadata else { continue }
            requestID = requestID
                ?? metadata["request_id"]
                ?? metadata["requestId"]
            traceID = traceID
                ?? metadata["trace_id"]
                ?? metadata["traceId"]
            if requestID != nil, traceID != nil { break }
        }
        return SupportDiagnosticsCorrelationIdentifiers(
            requestID: requestID,
            sentryEventID: nil,
            sentryTraceID: traceID
        )
    }
}

nonisolated enum SupportDiagnosticsWatchTransferState: Equatable, Sendable {
    case noneRecorded
    case recorded(action: String, outcome: String)
}

nonisolated enum SupportDiagnosticsFeatureOverrideState: Equatable, Sendable {
    case noneConfigured
    case configured([String])
}

nonisolated final class SupportDiagnosticsRuntimeState: @unchecked Sendable {
    static let shared = SupportDiagnosticsRuntimeState()

    private let lock = NSLock()
    private var requestID: String?
    private var sentryEventID: String?
    private var sentryTraceID: String?
    private var watchTransferState: SupportDiagnosticsWatchTransferState = .noneRecorded
    private var fallbackCorrelationID: String?

    private init() {}

    func recordRequestID(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        lock.withLock { requestID = id }
    }

    func recordSentryEventID(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        lock.withLock { sentryEventID = id }
    }

    func recordSentryTraceID(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        lock.withLock { sentryTraceID = id }
    }

    func recordWatchTransfer(action: String, outcome: String) {
        guard !action.isEmpty, !outcome.isEmpty else { return }
        lock.withLock {
            watchTransferState = .recorded(action: action, outcome: outcome)
        }
    }

    func correlationIdentifiers() -> SupportDiagnosticsCorrelationIdentifiers {
        lock.withLock {
            SupportDiagnosticsCorrelationIdentifiers(
                requestID: requestID,
                sentryEventID: sentryEventID,
                sentryTraceID: sentryTraceID
            )
        }
    }

    func lastWatchTransferState() -> SupportDiagnosticsWatchTransferState {
        lock.withLock { watchTransferState }
    }

    func safeCorrelationID() -> String {
        lock.withLock {
            if let requestID { return requestID }
            if let sentryEventID { return sentryEventID }
            if let fallbackCorrelationID { return fallbackCorrelationID }
            let generated = "diag-\(UUID().uuidString)"
            fallbackCorrelationID = generated
            return generated
        }
    }

    func resetForTests() {
        lock.withLock {
            requestID = nil
            sentryEventID = nil
            sentryTraceID = nil
            watchTransferState = .noneRecorded
            fallbackCorrelationID = nil
        }
    }

    func setFallbackCorrelationIDForTests(_ id: String) {
        lock.withLock { fallbackCorrelationID = id }
    }
}

nonisolated struct SupportDiagnosticsFeatureOverrideReader: Sendable {
    private let environment: [String: String]
    private let explicitStates: [String: Bool]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        explicitStates: [String: Bool] = [:]
    ) {
        self.environment = environment
        self.explicitStates = explicitStates
    }

    static var live: SupportDiagnosticsFeatureOverrideReader {
        var states: [String: Bool] = [:]
        if UserDefaults.standard.object(forKey: DefaultsKey.strengthAutoCaptureExperimental.rawValue) != nil {
            states["strength_auto_capture"] = StrengthAutoCaptureSettings.isEnabled
        }
        return SupportDiagnosticsFeatureOverrideReader(explicitStates: states)
    }

    func state() async -> SupportDiagnosticsFeatureOverrideState {
        var overrides: [String] = []
        let allowlistedEnvironment = [
            "AMAKAFLOW_PROGRAM_WIZARD": "program_wizard",
            "AMAKAFLOW_PAYWALL_GATE": "paywall_gate",
            "AMAKAFLOW_NON_MVP": "non_mvp"
        ]
        for (key, label) in allowlistedEnvironment {
            guard let value = environment[key],
                  let parsed = Self.parseBoolean(value)
            else { continue }
            overrides.append("\(label)=\(parsed ? "enabled" : "disabled")")
        }
        for (label, isEnabled) in explicitStates {
            overrides.append("\(label)=\(isEnabled ? "enabled" : "disabled")")
        }
        return overrides.isEmpty ? .noneConfigured : .configured(overrides)
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "1", "true", "yes", "enabled":
            return true
        case "0", "false", "no", "disabled":
            return false
        default:
            return nil
        }
    }
}

nonisolated enum SupportDiagnosticsSafeSummaries {
    static func hashedUserID(_ rawUserID: String?) -> String {
        guard let rawUserID, !rawUserID.isEmpty else { return "None" }
        let digest = SHA256.hash(data: Data(rawUserID.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex.prefix(16))"
    }

    static func sanitizedWatchTransferResult(state: SupportDiagnosticsWatchTransferState) -> String {
        switch state {
        case .noneRecorded:
            return "None recorded"
        case .recorded(let action, let outcome):
            return "\(sanitizedToken(action)): \(sanitizedToken(outcome))"
        }
    }

    static func displayIdentifier(_ identifier: String?) -> String {
        guard let identifier, !identifier.isEmpty else { return "None recorded" }
        return String(sanitizedToken(identifier).prefix(96))
    }

    static func featureOverrides(_ state: SupportDiagnosticsFeatureOverrideState) -> String {
        switch state {
        case .noneConfigured:
            return "None"
        case .configured(let overrides):
            let sanitized = overrides
                .filter { !$0.isEmpty }
                .map(sanitizedToken)
                .sorted()
            return sanitized.isEmpty ? "None" : sanitized.joined(separator: ", ")
        }
    }

    static func tokenExpirySummary(_ expiresAt: Date?, now: Date = Date()) -> String {
        guard let expiresAt else { return "None" }
        let formatted = supportDiagnosticsFormatted(expiresAt)
        return expiresAt <= now ? "Expired \(formatted)" : formatted
    }

    private static func sanitizedToken(_ token: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".:_-="))
        let scalars = token.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(scalars)
    }
}

nonisolated func supportDiagnosticsField(
    _ label: String,
    _ value: String
) -> SupportDiagnosticsDisplayField {
    SupportDiagnosticsDisplayField(label: label, value: value)
}

nonisolated func supportDiagnosticsYesNo(_ value: Bool) -> String {
    value ? "Yes" : "No"
}

nonisolated func supportDiagnosticsFormatted(_ date: Date?) -> String {
    guard let date else { return "None" }
    return date.formatted(date: .abbreviated, time: .shortened)
}
