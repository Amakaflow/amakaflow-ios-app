import Foundation

nonisolated struct DiagnosticBundleSnapshot: Codable, Equatable, Sendable {
    let createdAt: Date
    let authorization: DiagnosticBundleAuthorizationSnapshot
    let status: SupportDiagnosticsSnapshot
    let events: [DiagnosticEvent]
    let actions: [DiagnosticActionSnapshot]
}

nonisolated struct DiagnosticBundleAuthorizationSnapshot: Codable, Equatable, Sendable {
    let grantID: UUID
    let role: SupportDiagnosticsRole
    let capabilities: Set<SupportDiagnosticsCapability>
    let expiresAt: Date?

    init(
        grantID: UUID,
        role: SupportDiagnosticsRole,
        capabilities: Set<SupportDiagnosticsCapability>,
        expiresAt: Date?
    ) {
        self.grantID = grantID
        self.role = role
        self.capabilities = capabilities
        self.expiresAt = expiresAt
    }

    init(authorization: SupportDiagnosticsAuthorization) {
        self.init(
            grantID: authorization.grantID,
            role: authorization.role,
            capabilities: authorization.capabilities,
            expiresAt: authorization.expiresAt
        )
    }

    func matches(_ authorization: SupportDiagnosticsAuthorization) -> Bool {
        grantID == authorization.grantID
            && role == authorization.role
            && capabilities == authorization.capabilities
            && expiresAt == authorization.expiresAt
    }
}

nonisolated struct DiagnosticAuthorizationLoadToken: Equatable, Sendable {
    let grantID: UUID
    let capabilities: Set<SupportDiagnosticsCapability>
    let accountID: String?

    static func capture(
        state: SupportDiagnosticsSessionState,
        accountID: String?,
        requiredCapability: SupportDiagnosticsCapability
    ) -> DiagnosticAuthorizationLoadToken? {
        guard case .authorized(let authorization) = state,
              authorization.capabilities.contains(requiredCapability)
        else { return nil }
        return DiagnosticAuthorizationLoadToken(
            grantID: authorization.grantID,
            capabilities: authorization.capabilities,
            accountID: accountID
        )
    }

    func matches(
        state: SupportDiagnosticsSessionState,
        accountID: String?,
        requiredCapability: SupportDiagnosticsCapability
    ) -> Bool {
        guard case .authorized(let authorization) = state,
              authorization.capabilities.contains(requiredCapability)
        else { return false }
        return grantID == authorization.grantID
            && capabilities == authorization.capabilities
            && self.accountID == accountID
    }
}

nonisolated struct DiagnosticActionSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let capability: SupportDiagnosticsCapability
    let outcome: SupportDiagnosticsAuditOutcome
    let title: String
    let safeContext: [String: String]
    let requestID: String?
    let sentryEventID: String?
}

nonisolated enum DiagnosticBundleFileName: String, CaseIterable, Codable, Sendable {
    case manifest = "manifest.json"
    case status = "status.json"
    case logs = "logs.ndjson"
    case actions = "actions.ndjson"
    case errors = "errors.json"
}

nonisolated enum DiagnosticBundleExcludedCategory: String, CaseIterable, Codable, Sendable {
    case tokensAuthHeadersCookies
    case requestResponseBodies
    case databaseDumpsRows
    case healthSamplesValues
    case exactLocations
    case unrelatedCustomerContent

    var displayName: String {
        switch self {
        case .tokensAuthHeadersCookies:
            return "Tokens, auth headers, and cookies"
        case .requestResponseBodies:
            return "Request and response bodies"
        case .databaseDumpsRows:
            return "Database dumps and rows"
        case .healthSamplesValues:
            return "Health samples and values"
        case .exactLocations:
            return "Exact locations"
        case .unrelatedCustomerContent:
            return "Unrelated customer content"
        }
    }
}

nonisolated struct DiagnosticBundleTimeRange: Codable, Equatable, Sendable {
    let start: Date
    let end: Date
}

nonisolated struct DiagnosticBundlePreview: Codable, Equatable, Sendable {
    static let includedFileNames = DiagnosticBundleFileName.allCases.map(\.rawValue)

    let includedFileNames: [String]
    let timeRange: DiagnosticBundleTimeRange?
    let eventCount: Int
    let excludedCategories: [String]

    init(snapshot: DiagnosticBundleSnapshot) {
        includedFileNames = Self.includedFileNames
        eventCount = snapshot.events.count
        excludedCategories = DiagnosticBundleExcludedCategory.allCases.map(\.displayName)

        let timestamps = snapshot.events.map(\.timestamp)
        if let start = timestamps.min(), let end = timestamps.max() {
            timeRange = DiagnosticBundleTimeRange(start: start, end: end)
        } else {
            timeRange = nil
        }
    }
}

nonisolated enum DiagnosticLogsPolicy {
    static func visibleEvents(
        state: SupportDiagnosticsSessionState,
        events: [DiagnosticEvent]
    ) -> [DiagnosticEvent] {
        guard hasCapability(.logsRead, in: state) else { return [] }
        return events
    }

    static func canReadLogs(_ state: SupportDiagnosticsSessionState) -> Bool {
        hasCapability(.logsRead, in: state)
    }

    static func acceptsLoadedEvents(
        token: DiagnosticAuthorizationLoadToken?,
        currentState: SupportDiagnosticsSessionState,
        currentAccountID: String?
    ) -> Bool {
        token?.matches(state: currentState, accountID: currentAccountID, requiredCapability: .logsRead) == true
    }

    static func shouldReloadLoadedContent(
        token: DiagnosticAuthorizationLoadToken?,
        currentState: SupportDiagnosticsSessionState,
        currentAccountID: String?,
        requiredCapability: SupportDiagnosticsCapability
    ) -> Bool {
        guard let currentToken = DiagnosticAuthorizationLoadToken.capture(
            state: currentState,
            accountID: currentAccountID,
            requiredCapability: requiredCapability
        ) else { return false }
        return token != currentToken
    }
}

nonisolated enum DiagnosticBundlePreviewPolicy {
    static func preview(
        state: SupportDiagnosticsSessionState,
        snapshot: DiagnosticBundleSnapshot?
    ) -> DiagnosticBundlePreview? {
        guard case .authorized(let authorization) = state,
              authorization.capabilities.contains(.bundleExport),
              let snapshot,
              snapshot.authorization.matches(authorization)
        else { return nil }
        return DiagnosticBundlePreview(snapshot: snapshot)
    }

    static func canPreviewBundle(_ state: SupportDiagnosticsSessionState) -> Bool {
        hasCapability(.bundleExport, in: state)
    }

    static func acceptsLoadedSnapshot(
        token: DiagnosticAuthorizationLoadToken?,
        currentState: SupportDiagnosticsSessionState,
        currentAccountID: String?
    ) -> Bool {
        token?.matches(state: currentState, accountID: currentAccountID, requiredCapability: .bundleExport) == true
    }
}

private nonisolated func hasCapability(
    _ capability: SupportDiagnosticsCapability,
    in state: SupportDiagnosticsSessionState
) -> Bool {
    guard case .authorized(let authorization) = state else { return false }
    return authorization.capabilities.contains(capability)
}

@MainActor
protocol DiagnosticEventSnapshotProviding {
    func eventsForCurrentAccount() async throws -> [DiagnosticEvent]
}

nonisolated struct LiveDiagnosticEventSnapshotProvider: DiagnosticEventSnapshotProviding {
    func eventsForCurrentAccount() async throws -> [DiagnosticEvent] {
        try await DebugLogService.shared.diagnosticEventsForCurrentAccount()
    }
}

@MainActor
protocol DiagnosticActionSnapshotProviding {
    func actionsForCurrentSession() async throws -> [DiagnosticActionSnapshot]
}

nonisolated struct ViewerEmptyActionProvider: DiagnosticActionSnapshotProviding {
    func actionsForCurrentSession() async throws -> [DiagnosticActionSnapshot] { [] }
}

@MainActor
protocol DiagnosticBundleSnapshotProviding {
    func snapshot(authorization: SupportDiagnosticsAuthorization) async throws -> DiagnosticBundleSnapshot
}

nonisolated struct LiveDiagnosticBundleSnapshotProvider: DiagnosticBundleSnapshotProviding {
    private let eventsProvider: any DiagnosticEventSnapshotProviding
    private let actionProvider: any DiagnosticActionSnapshotProviding
    private let now: @MainActor @Sendable () -> Date

    init(
        eventsProvider: any DiagnosticEventSnapshotProviding,
        actionProvider: any DiagnosticActionSnapshotProviding = ViewerEmptyActionProvider(),
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        self.eventsProvider = eventsProvider
        self.actionProvider = actionProvider
        self.now = now
    }

    func snapshot(authorization: SupportDiagnosticsAuthorization) async throws -> DiagnosticBundleSnapshot {
        let status = await SupportDiagnosticsProbeRunner(
            probes: SupportDiagnosticsProbes.live(authorization: authorization)
        ).run()
        let events = try await eventsProvider.eventsForCurrentAccount()
        let actions = try await actionProvider.actionsForCurrentSession()

        return DiagnosticBundleSnapshot(
            createdAt: now(),
            authorization: DiagnosticBundleAuthorizationSnapshot(authorization: authorization),
            status: status,
            events: events,
            actions: actions
        )
    }
}
