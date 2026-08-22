import Foundation
import GRDB
import HealthKit
import UIKit
import WatchConnectivity

nonisolated enum SupportDiagnosticsProbes {
    static func live(authorization: SupportDiagnosticsAuthorization) -> [any SupportDiagnosticsProbe] {
        [
            AppBuildDeviceProbe(),
            ConfiguredHostsProbe(),
            ClerkSessionProbe(),
            ReachabilityHealthProbe(),
            WatchConnectivityProbe(),
            HealthKitAuthorizationProbe(),
            QueuesProbe(),
            DatabaseHealthProbe(),
            GrantStateProbe(authorization: authorization),
            CorrelationIDsProbe()
        ]
    }
}

private nonisolated struct AppBuildDeviceProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .appBuildDevice
    let title = "App, build, and device"
    let timeout: Duration = .seconds(1)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let identifier = bundle.bundleIdentifier
        let device = UIDevice.current

        return [
            field("App version", version ?? "Unknown"),
            field("Build", build ?? "Unknown"),
            field("Bundle ID", identifier ?? "Unknown"),
            field("Device model", device.model),
            field("System", "\(device.systemName) \(device.systemVersion)")
        ]
    }
}

private nonisolated struct ConfiguredHostsProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .configuredHosts
    let title = "Configured hosts"
    let timeout: Duration = .seconds(1)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        await MainActor.run {
            let environment = AppEnvironment.current
            return [
                field("Environment", environment.rawValue),
                field("Mobile BFF", host(from: environment.mobileBFFURL)),
                field("Mapper API", host(from: environment.mapperAPIURL)),
                field("Ingestor API", host(from: environment.ingestorAPIURL)),
                field("Calendar API", host(from: environment.calendarAPIURL)),
                field("Chat API", host(from: environment.chatAPIURL)),
                field("MCP API", host(from: environment.mcpAPIURL))
            ]
        }
    }
}

private nonisolated struct ClerkSessionProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .clerkSession
    let title = "Clerk session"
    let timeout: Duration = .seconds(1)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        await MainActor.run {
            let auth = AuthViewModel.shared
            return [
                field("Resolved initial session", yesNo(auth.hasResolvedInitialSession)),
                field("Authenticated", yesNo(auth.isAuthenticated)),
                field("Active SDK session", yesNo(auth.hasActiveSession)),
                field("Needs reauth", yesNo(auth.needsReauth)),
                field("Last token refresh", formatted(auth.lastTokenRefresh))
            ]
        }
    }
}

private nonisolated struct ReachabilityHealthProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .reachabilityHealth
    let title = "Reachability and health"
    let timeout: Duration = .seconds(4)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        let baseURL = await MainActor.run {
            AppEnvironment.current.mobileBFFURL
        }
        guard let base = URL(string: baseURL) else {
            throw SupportDiagnosticsProbeError(code: .configurationUnavailable)
        }
        let url = base.appending(path: "health")
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3

        let started = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupportDiagnosticsProbeError(code: .networkUnavailable)
            }
            let elapsed = Int(Date().timeIntervalSince(started) * 1_000)
            return [
                field("Host", base.host ?? "Unknown"),
                field("HTTP status", String(httpResponse.statusCode)),
                field("Latency", "\(elapsed) ms")
            ]
        } catch let error as SupportDiagnosticsProbeError {
            throw error
        } catch {
            throw SupportDiagnosticsProbeError(code: .networkUnavailable)
        }
    }
}

private nonisolated struct WatchConnectivityProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .watchConnectivity
    let title = "Watch connectivity"
    let timeout: Duration = .seconds(1)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        await MainActor.run {
            let session = AppDependencies.current.watchSession
            return [
                field("Supported", yesNo(WCSession.isSupported())),
                field("Paired", yesNo(session.isPaired)),
                field("Watch app installed", yesNo(session.isWatchAppInstalled)),
                field("Reachable", yesNo(session.isReachable)),
                field("Activation", activationDescription(session.activationState))
            ]
        }
    }
}

private nonisolated struct HealthKitAuthorizationProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .healthKitAuthorization
    let title = "HealthKit authorization"
    let timeout: Duration = .seconds(1)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SupportDiagnosticsProbeError(code: .healthKitUnavailable)
        }

        let store = HKHealthStore()
        let protein = HKQuantityType.quantityType(forIdentifier: .dietaryProtein)
        let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater)
        let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass)

        let actualsState = await MainActor.run {
            LiveActualsHealthKitConnector().authorizationState.rawValue
        }

        return [
            field("Health data available", "Yes"),
            field("Actuals workout read", actualsState),
            field("Protein write", authorizationDescription(protein, store: store)),
            field("Water write", authorizationDescription(water, store: store)),
            field("Body mass write", authorizationDescription(bodyMass, store: store)),
            field("Read status disclosure", "Not exposed by HealthKit")
        ]
    }
}

private nonisolated struct QueuesProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .queues
    let title = "Queues"
    let timeout: Duration = .seconds(2)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        do {
            let summary = try await MainActor.run {
                try AppDependencies.current.syncQueueRepository.summary()
            }
            let oldestAge = try await oldestSyncQueueAge()
            let completionCount = await MainActor.run {
                WorkoutCompletionService.shared.pendingCount
            }

            return [
                field("Sync pending", String(summary.pendingCount)),
                field("Sync in flight", String(summary.inFlightCount)),
                field("Sync failed", String(summary.failedCount)),
                field("Sync poison", String(summary.poisonCount)),
                field("Oldest sync queue age", oldestAge ?? "None"),
                field("Last sync attempt", formatted(summary.lastAttemptedAt)),
                field("Last safe sync error", summary.latestError == nil ? "None" : "SYNC_QUEUE_ERROR_RECORDED"),
                field("Completion pending", String(completionCount))
            ]
        } catch {
            throw SupportDiagnosticsProbeError(code: .queueUnavailable)
        }
    }
}

private nonisolated struct DatabaseHealthProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .databaseHealth
    let title = "Database schema and migrations"
    let timeout: Duration = .seconds(2)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        do {
            let result = try await MainActor.run {
                try AppDatabase.shared.dbQueue.read { database in
                    let tables = try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'"
                    ) ?? 0
                    let migrations = try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM grdb_migrations"
                    ) ?? 0
                    return (tables, migrations)
                }
            }

            return [
                field("Database readable", "Yes"),
                field("Schema tables", String(result.0)),
                field("Applied migrations", String(result.1))
            ]
        } catch {
            throw SupportDiagnosticsProbeError(code: .databaseUnavailable)
        }
    }
}

private nonisolated struct GrantStateProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .grantState
    let title = "Effective grant state"
    let timeout: Duration = .seconds(1)

    let authorization: SupportDiagnosticsAuthorization

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        [
            field("Role", authorization.role.rawValue),
            field("Capability count", String(authorization.capabilities.count)),
            field("Expires", formatted(authorization.expiresAt)),
            field("Expired", yesNo(isExpired))
        ]
    }

    private var isExpired: Bool {
        guard let expiresAt = authorization.expiresAt else { return false }
        return expiresAt <= authorization.serverTime
    }
}

private nonisolated struct CorrelationIDsProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .correlationIDs
    let title = "Correlation IDs"
    let timeout: Duration = .seconds(1)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        [
            field("Existing IDs", "None recorded for status probes")
        ]
    }
}

private nonisolated func field(_ label: String, _ value: String) -> SupportDiagnosticsDisplayField {
    SupportDiagnosticsDisplayField(label: label, value: value)
}

private nonisolated func yesNo(_ value: Bool) -> String {
    value ? "Yes" : "No"
}

private nonisolated func formatted(_ date: Date?) -> String {
    guard let date else { return "None" }
    return date.formatted(date: .abbreviated, time: .shortened)
}

private nonisolated func host(from urlString: String) -> String {
    guard let url = URL(string: urlString), let host = url.host else {
        return "Invalid"
    }
    return host
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

private nonisolated func authorizationDescription(
    _ type: HKQuantityType?,
    store: HKHealthStore
) -> String {
    guard let type else { return "Unavailable" }
    switch store.authorizationStatus(for: type) {
    case .notDetermined:
        return "Not determined"
    case .sharingDenied:
        return "Denied"
    case .sharingAuthorized:
        return "Authorized"
    @unknown default:
        return "Unknown"
    }
}

@MainActor
private func oldestSyncQueueAge(now: Date = Date()) throws -> String? {
    try AppDatabase.shared.dbQueue.read { database in
        let oldest = try Date.fetchOne(
            database,
            sql: """
            SELECT MIN(created_at) FROM sync_queue
            WHERE status IN (?, ?, ?)
            """,
            arguments: [
                SyncQueueStatus.pending.rawValue,
                SyncQueueStatus.failed.rawValue,
                SyncQueueStatus.poison.rawValue
            ]
        )
        guard let oldest else { return nil }
        let age = max(0, Int(now.timeIntervalSince(oldest)))
        if age < 60 {
            return "\(age)s"
        }
        if age < 3_600 {
            return "\(age / 60)m"
        }
        return "\(age / 3_600)h"
    }
}
