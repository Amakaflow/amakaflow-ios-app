import Foundation
import GRDB
import HealthKit

nonisolated struct HealthKitAuthorizationProbe: SupportDiagnosticsProbe {
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
            supportDiagnosticsField("Health data available", "Yes"),
            supportDiagnosticsField("Actuals workout read", actualsState),
            supportDiagnosticsField("Protein write", authorizationDescription(protein, store: store)),
            supportDiagnosticsField("Water write", authorizationDescription(water, store: store)),
            supportDiagnosticsField("Body mass write", authorizationDescription(bodyMass, store: store)),
            supportDiagnosticsField("Read status disclosure", "Not exposed by HealthKit")
        ]
    }
}

nonisolated struct QueuesProbe: SupportDiagnosticsProbe {
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
                supportDiagnosticsField("Sync pending", String(summary.pendingCount)),
                supportDiagnosticsField("Sync in flight", String(summary.inFlightCount)),
                supportDiagnosticsField("Sync failed", String(summary.failedCount)),
                supportDiagnosticsField("Sync poison", String(summary.poisonCount)),
                supportDiagnosticsField("Oldest sync queue age", oldestAge ?? "None"),
                supportDiagnosticsField("Last sync attempt", supportDiagnosticsFormatted(summary.lastAttemptedAt)),
                supportDiagnosticsField(
                    "Last safe sync error",
                    summary.latestError == nil ? "None" : "SYNC_QUEUE_ERROR_RECORDED"
                ),
                supportDiagnosticsField("Completion pending", String(completionCount))
            ]
        } catch {
            throw SupportDiagnosticsProbeError(code: .queueUnavailable)
        }
    }
}

nonisolated struct DatabaseHealthProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .databaseHealth
    let title = "Database schema and migrations"
    let timeout: Duration = .seconds(2)

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        do {
            let result = try await MainActor.run {
                try AppDatabase.shared.dbQueue.read { database in
                    let schemaVersion = try Int.fetchOne(database, sql: "PRAGMA user_version") ?? 0
                    let hasMigrationTable = try Int.fetchOne(
                        database,
                        sql: """
                        SELECT COUNT(*) FROM sqlite_master
                        WHERE type = 'table' AND name = 'grdb_migrations'
                        """
                    ) ?? 0
                    let tables = try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'"
                    ) ?? 0
                    let migrations = hasMigrationTable == 0 ? 0 : try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM grdb_migrations"
                    ) ?? 0
                    let migrationHealth = hasMigrationTable == 0 ? "Missing migration table" : "Readable"
                    return (schemaVersion, hasMigrationTable, tables, migrations, migrationHealth)
                }
            }

            return [
                supportDiagnosticsField("Database readable", "Yes"),
                supportDiagnosticsField("Local schema version", String(result.0)),
                supportDiagnosticsField("Migration table", result.1 == 0 ? "Missing" : "Present"),
                supportDiagnosticsField("Applied migrations", String(result.3)),
                supportDiagnosticsField("Migration health", result.4),
                supportDiagnosticsField("Schema tables", String(result.2))
            ]
        } catch {
            throw SupportDiagnosticsProbeError(code: .databaseUnavailable)
        }
    }
}

nonisolated struct GrantStateProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .grantState
    let title = "Effective grant state"
    let timeout: Duration = .seconds(1)

    let authorization: SupportDiagnosticsAuthorization
    let featureOverrideState: @Sendable () async -> SupportDiagnosticsFeatureOverrideState

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        let overrides = await featureOverrideState()
        let simulationEnabled = await MainActor.run {
            SimulationSettings.shared.isEnabled
        }
        return [
            supportDiagnosticsField("Role", authorization.role.rawValue),
            supportDiagnosticsField("Capability count", String(authorization.capabilities.count)),
            supportDiagnosticsField("Capability wire list", capabilityWireList),
            supportDiagnosticsField("Expires", supportDiagnosticsFormatted(authorization.expiresAt)),
            supportDiagnosticsField("Expired", supportDiagnosticsYesNo(isExpired)),
            supportDiagnosticsField("Simulation state", simulationEnabled ? "Enabled" : "Disabled"),
            supportDiagnosticsField(
                "Allowlisted feature overrides",
                SupportDiagnosticsSafeSummaries.featureOverrides(overrides)
            )
        ]
    }

    private var isExpired: Bool {
        guard let expiresAt = authorization.expiresAt else { return false }
        return expiresAt <= authorization.serverTime
    }

    private var capabilityWireList: String {
        let values = authorization.capabilities.map(\.rawValue).sorted()
        return values.isEmpty ? "None" : values.joined(separator: ", ")
    }
}

nonisolated struct CorrelationIDsProbe: SupportDiagnosticsProbe {
    let id: SupportDiagnosticsProbeID = .correlationIDs
    let title = "Correlation IDs"
    let timeout: Duration = .seconds(1)
    let provider: @Sendable () async -> SupportDiagnosticsCorrelationIdentifiers

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        let identifiers = await provider()
        return [
            supportDiagnosticsField(
                "Existing request ID",
                SupportDiagnosticsSafeSummaries.displayIdentifier(identifiers.requestID)
            ),
            supportDiagnosticsField(
                "Existing Sentry event ID",
                SupportDiagnosticsSafeSummaries.displayIdentifier(identifiers.sentryEventID)
            ),
            supportDiagnosticsField(
                "Existing Sentry trace ID",
                SupportDiagnosticsSafeSummaries.displayIdentifier(identifiers.sentryTraceID)
            )
        ]
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
