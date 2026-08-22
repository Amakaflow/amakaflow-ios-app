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

    static let approvedLiveFieldLabels: [SupportDiagnosticsProbeID: [String]] = [
        .appBuildDevice: [
            "App version",
            "Build",
            "Bundle ID",
            "Distribution",
            "Device model",
            "System",
            "Locale",
            "Timezone"
        ],
        .configuredHosts: [
            "Environment",
            "Mobile BFF",
            "Mapper API",
            "Ingestor API",
            "Calendar API",
            "Chat API",
            "MCP API",
            "Strava API"
        ],
        .clerkSession: [
            "Resolved initial session",
            "Authenticated",
            "Active SDK session",
            "Needs reauth",
            "Token expiry",
            "Last token refresh",
            "User ID hash"
        ],
        .reachabilityHealth: approvedReachabilityServiceNames.flatMap {
            ["\($0) host", "\($0) outcome", "\($0) latency"]
        },
        .watchConnectivity: [
            "Supported",
            "Paired",
            "Watch app installed",
            "Reachable",
            "Activation",
            "Last transfer result"
        ],
        .healthKitAuthorization: [
            "Health data available",
            "Actuals workout read",
            "Protein write",
            "Water write",
            "Body mass write",
            "Read status disclosure"
        ],
        .queues: [
            "Sync pending",
            "Sync in flight",
            "Sync failed",
            "Sync poison",
            "Oldest sync queue age",
            "Last sync attempt",
            "Last safe sync error",
            "Completion pending"
        ],
        .databaseHealth: [
            "Database readable",
            "Local schema version",
            "Migration table",
            "Applied migrations",
            "Migration health",
            "Schema tables"
        ],
        .grantState: [
            "Role",
            "Capability count",
            "Capability wire list",
            "Expires",
            "Expired",
            "Simulation state",
            "Allowlisted feature overrides"
        ],
        .correlationIDs: [
            "Existing request ID",
            "Existing Sentry event ID",
            "Existing Sentry trace ID"
        ]
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
        correlationIdentifiers: { .noneRecorded },
        lastWatchTransferState: { .noneRecorded },
        allowlistedFeatureOverrides: { .noneConfigured }
    )
}

nonisolated struct SupportDiagnosticsCorrelationIdentifiers: Equatable, Sendable {
    let requestID: String?
    let sentryEventID: String?
    let sentryTraceID: String?

    static let noneRecorded = SupportDiagnosticsCorrelationIdentifiers(
        requestID: nil,
        sentryEventID: nil,
        sentryTraceID: nil
    )
}

nonisolated enum SupportDiagnosticsWatchTransferState: Equatable, Sendable {
    case noneRecorded
    case recorded(action: String, outcome: String)
}

nonisolated enum SupportDiagnosticsFeatureOverrideState: Equatable, Sendable {
    case noneConfigured
    case configured([String])
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

    private static func sanitizedToken(_ token: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".:_-"))
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
