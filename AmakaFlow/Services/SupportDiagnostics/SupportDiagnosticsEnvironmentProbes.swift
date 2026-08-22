import ClerkKit
import Foundation
import UIKit
import WatchConnectivity

nonisolated struct AppBuildDeviceProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .appBuildDevice
    let title = "App, build, and device"
    let timeout: Duration = .seconds(1)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        await MainActor.run {
            let bundle = Bundle.main
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            let identifier = bundle.bundleIdentifier
            let device = UIDevice.current

            return [
                supportDiagnosticsField("App version", version ?? "Unknown"),
                supportDiagnosticsField("Build", build ?? "Unknown"),
                supportDiagnosticsField("Bundle ID", identifier ?? "Unknown"),
                supportDiagnosticsField("Distribution", distributionType(bundle: bundle)),
                supportDiagnosticsField("Device model", device.model),
                supportDiagnosticsField("System", "\(device.systemName) \(device.systemVersion)"),
                supportDiagnosticsField("Locale", Locale.current.identifier),
                supportDiagnosticsField("Timezone", TimeZone.current.identifier)
            ]
        }
    }
}

nonisolated struct ConfiguredHostsProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .configuredHosts
    let title = "Configured hosts"
    let timeout: Duration = .seconds(1)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        await MainActor.run {
            let environment = AppEnvironment.current
            return [supportDiagnosticsField("Environment", environment.rawValue)]
                + supportDiagnosticsServiceEndpoints(environment: environment).map {
                    supportDiagnosticsField($0.name, host(from: $0.baseURL))
                }
        }
    }
}

nonisolated struct ClerkSessionProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .clerkSession
    let title = "Clerk session"
    let timeout: Duration = .seconds(1)
    let sessionState: @Sendable () async -> SupportDiagnosticsClerkSessionState
    let now: @Sendable () -> Date

    init(
        sessionState: @escaping @Sendable () async -> SupportDiagnosticsClerkSessionState = {
            await MainActor.run {
                let auth = AuthViewModel.shared
                return SupportDiagnosticsClerkSessionState(
                    hasResolvedInitialSession: auth.hasResolvedInitialSession,
                    isAuthenticated: auth.isAuthenticated,
                    hasActiveSession: auth.hasActiveSession,
                    needsReauth: auth.needsReauth,
                    tokenExpiresAt: Clerk.shared.session?.expireAt,
                    lastTokenRefresh: auth.lastTokenRefresh,
                    rawUserID: auth.userProfile?.id
                )
            }
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.sessionState = sessionState
        self.now = now
    }

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        let state = await sessionState()
        return [
            supportDiagnosticsField(
                "Resolved initial session",
                supportDiagnosticsYesNo(state.hasResolvedInitialSession)
            ),
            supportDiagnosticsField("Authenticated", supportDiagnosticsYesNo(state.isAuthenticated)),
            supportDiagnosticsField("Active SDK session", supportDiagnosticsYesNo(state.hasActiveSession)),
            supportDiagnosticsField("Needs reauth", supportDiagnosticsYesNo(state.needsReauth)),
            supportDiagnosticsField(
                "Token expiry",
                SupportDiagnosticsSafeSummaries.tokenExpirySummary(state.tokenExpiresAt, now: now())
            ),
            supportDiagnosticsField("Last token refresh", supportDiagnosticsFormatted(state.lastTokenRefresh)),
            supportDiagnosticsField(
                "User ID hash",
                SupportDiagnosticsSafeSummaries.hashedUserID(state.rawUserID)
            )
        ]
    }
}

nonisolated struct SupportDiagnosticsClerkSessionState: Equatable, Sendable {
    let hasResolvedInitialSession: Bool
    let isAuthenticated: Bool
    let hasActiveSession: Bool
    let needsReauth: Bool
    let tokenExpiresAt: Date?
    let lastTokenRefresh: Date?
    let rawUserID: String?
}

nonisolated struct ReachabilityHealthProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .reachabilityHealth
    let title = "Reachability and health"
    let timeout: Duration = .seconds(4)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        let endpoints = await MainActor.run {
            supportDiagnosticsServiceEndpoints(environment: AppEnvironment.current)
        }

        let checked = await withTaskGroup(of: IndexedServiceFields.self) { group in
            for (index, endpoint) in endpoints.enumerated() {
                group.addTask {
                    await IndexedServiceFields(
                        index: index,
                        fields: checkHealth(endpoint: endpoint)
                    )
                }
            }

            var fields: [IndexedServiceFields] = []
            for await result in group {
                fields.append(result)
            }
            return fields.sorted { $0.index < $1.index }
        }

        return checked.flatMap(\.fields)
    }
}

nonisolated struct WatchConnectivityProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .watchConnectivity
    let title = "Watch connectivity"
    let timeout: Duration = .seconds(1)
    let lastTransferState: @Sendable () async -> SupportDiagnosticsWatchTransferState

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        let state = await lastTransferState()
        return await MainActor.run {
            let session = AppDependencies.current.watchSession
            return [
                supportDiagnosticsField("Supported", supportDiagnosticsYesNo(WCSession.isSupported())),
                supportDiagnosticsField("Paired", supportDiagnosticsYesNo(session.isPaired)),
                supportDiagnosticsField("Watch app installed", supportDiagnosticsYesNo(session.isWatchAppInstalled)),
                supportDiagnosticsField("Reachable", supportDiagnosticsYesNo(session.isReachable)),
                supportDiagnosticsField("Activation", activationDescription(session.activationState)),
                supportDiagnosticsField(
                    "Last transfer result",
                    SupportDiagnosticsSafeSummaries.sanitizedWatchTransferResult(state: state)
                )
            ]
        }
    }
}

private nonisolated func distributionType(bundle: Bundle) -> String {
    #if DEBUG
    return "Debug"
    #else
    if bundle.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
        return "TestFlight or sandbox"
    }
    return "Release"
    #endif
}

private nonisolated func host(from urlString: String) -> String {
    guard let url = URL(string: urlString), let host = url.host else {
        return "Invalid"
    }
    return host
}

nonisolated struct SupportDiagnosticsServiceEndpoint: Sendable {
    let name: String
    let baseURL: String
}

private nonisolated struct IndexedServiceFields: Sendable {
    let index: Int
    let fields: [SupportDiagnosticsDisplayField]
}

@MainActor
func supportDiagnosticsServiceEndpoints(
    environment: AppEnvironment
) -> [SupportDiagnosticsServiceEndpoint] {
    [
        SupportDiagnosticsServiceEndpoint(name: "Mobile BFF", baseURL: environment.mobileBFFURL),
        SupportDiagnosticsServiceEndpoint(name: "Mapper API", baseURL: environment.mapperAPIURL),
        SupportDiagnosticsServiceEndpoint(name: "Ingestor API", baseURL: environment.ingestorAPIURL),
        SupportDiagnosticsServiceEndpoint(name: "Calendar API", baseURL: environment.calendarAPIURL),
        SupportDiagnosticsServiceEndpoint(name: "Chat API", baseURL: environment.chatAPIURL),
        SupportDiagnosticsServiceEndpoint(name: "MCP API", baseURL: environment.mcpAPIURL),
        SupportDiagnosticsServiceEndpoint(name: "Strava API", baseURL: environment.stravaAPIURL)
    ]
}

private nonisolated func checkHealth(
    endpoint: SupportDiagnosticsServiceEndpoint
) async -> [SupportDiagnosticsDisplayField] {
    guard let base = URL(string: endpoint.baseURL), let host = base.host else {
        return [
            supportDiagnosticsField("\(endpoint.name) host", "Invalid"),
            supportDiagnosticsField("\(endpoint.name) outcome", "Configuration unavailable"),
            supportDiagnosticsField("\(endpoint.name) latency", "Not checked")
        ]
    }

    let url = base.appending(path: "health")
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    // Leave one second for the probe runner to collect and classify the result
    // before its four-second hard deadline cancels the group.
    request.timeoutInterval = 3
    let clock = ContinuousClock()
    let started = clock.now

    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return healthFields(
                name: endpoint.name,
                host: host,
                outcome: "Network unavailable",
                elapsed: started.duration(to: clock.now)
            )
        }
        return healthFields(
            name: endpoint.name,
            host: host,
            outcome: "HTTP \(httpResponse.statusCode)",
            elapsed: started.duration(to: clock.now)
        )
    } catch let error as URLError {
        return healthFields(
            name: endpoint.name,
            host: host,
            outcome: "Network unavailable (\(error.errorCode))",
            elapsed: started.duration(to: clock.now)
        )
    } catch {
        return healthFields(
            name: endpoint.name,
            host: host,
            outcome: "Network unavailable",
            elapsed: started.duration(to: clock.now)
        )
    }
}

private nonisolated func healthFields(
    name: String,
    host: String,
    outcome: String,
    elapsed: Duration
) -> [SupportDiagnosticsDisplayField] {
    let elapsedMilliseconds = elapsed.components.seconds * 1_000
        + elapsed.components.attoseconds / 1_000_000_000_000_000
    return [
        supportDiagnosticsField("\(name) host", host),
        supportDiagnosticsField("\(name) outcome", outcome),
        supportDiagnosticsField("\(name) latency", "\(elapsedMilliseconds) ms")
    ]
}

private nonisolated func activationDescription(_ state: WCSessionActivationState) -> String {
    switch state {
    case .notActivated:
        return "Not activated"
    case .inactive:
        return "Inactive"
    case .activated:
        return "Activated"
    @unknown default:
        return "Unknown"
    }
}
