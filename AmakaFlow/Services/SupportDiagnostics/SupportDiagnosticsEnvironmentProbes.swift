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
            return [
                supportDiagnosticsField("Environment", environment.rawValue),
                supportDiagnosticsField("Mobile BFF", host(from: environment.mobileBFFURL)),
                supportDiagnosticsField("Mapper API", host(from: environment.mapperAPIURL)),
                supportDiagnosticsField("Ingestor API", host(from: environment.ingestorAPIURL)),
                supportDiagnosticsField("Calendar API", host(from: environment.calendarAPIURL)),
                supportDiagnosticsField("Chat API", host(from: environment.chatAPIURL)),
                supportDiagnosticsField("MCP API", host(from: environment.mcpAPIURL)),
                supportDiagnosticsField("Strava API", host(from: environment.stravaAPIURL))
            ]
        }
    }
}

nonisolated struct ClerkSessionProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .clerkSession
    let title = "Clerk session"
    let timeout: Duration = .seconds(1)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        await MainActor.run {
            let auth = AuthViewModel.shared
            return [
                supportDiagnosticsField(
                    "Resolved initial session",
                    supportDiagnosticsYesNo(auth.hasResolvedInitialSession)
                ),
                supportDiagnosticsField("Authenticated", supportDiagnosticsYesNo(auth.isAuthenticated)),
                supportDiagnosticsField("Active SDK session", supportDiagnosticsYesNo(auth.hasActiveSession)),
                supportDiagnosticsField("Needs reauth", supportDiagnosticsYesNo(auth.needsReauth)),
                supportDiagnosticsField("Token expiry", "Not reported by SDK"),
                supportDiagnosticsField("Last token refresh", supportDiagnosticsFormatted(auth.lastTokenRefresh)),
                supportDiagnosticsField(
                    "User ID hash",
                    SupportDiagnosticsSafeSummaries.hashedUserID(auth.userProfile?.id)
                )
            ]
        }
    }
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

private nonisolated struct SupportDiagnosticsServiceEndpoint: Sendable {
    let name: String
    let baseURL: String
}

private nonisolated struct IndexedServiceFields: Sendable {
    let index: Int
    let fields: [SupportDiagnosticsDisplayField]
}

@MainActor
private func supportDiagnosticsServiceEndpoints(
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
    request.timeoutInterval = 1
    let started = Date()

    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return healthFields(name: endpoint.name, host: host, outcome: "Network unavailable", started: started)
        }
        return healthFields(name: endpoint.name, host: host, outcome: "HTTP \(httpResponse.statusCode)", started: started)
    } catch {
        return healthFields(name: endpoint.name, host: host, outcome: "Network unavailable", started: started)
    }
}

private nonisolated func healthFields(
    name: String,
    host: String,
    outcome: String,
    started: Date
) -> [SupportDiagnosticsDisplayField] {
    let elapsed = Int(Date().timeIntervalSince(started) * 1_000)
    return [
        supportDiagnosticsField("\(name) host", host),
        supportDiagnosticsField("\(name) outcome", outcome),
        supportDiagnosticsField("\(name) latency", "\(elapsed) ms")
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
