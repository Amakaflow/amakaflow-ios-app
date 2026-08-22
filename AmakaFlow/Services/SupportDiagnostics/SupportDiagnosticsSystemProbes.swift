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
            let reading = try await syncQueueReading()
            let summary = reading.summary
            let completionCount = await MainActor.run {
                WorkoutCompletionService.shared.pendingCount
            }

            return [
                supportDiagnosticsField("Sync pending", String(summary.pendingCount)),
                supportDiagnosticsField("Sync in flight", String(summary.inFlightCount)),
                supportDiagnosticsField("Sync failed", String(summary.failedCount)),
                supportDiagnosticsField("Sync poison", String(summary.poisonCount)),
                supportDiagnosticsField("Oldest sync queue age", reading.oldestAge ?? "None"),
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
            let databaseQueue = await MainActor.run { AppDatabase.shared.dbQueue }
            let result = try await databaseQueue.read { database in
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
                    return DatabaseHealthReading(
                        schemaVersion: schemaVersion,
                        hasMigrationTable: hasMigrationTable != 0,
                        tableCount: tables,
                        migrationCount: migrations,
                        migrationHealth: migrationHealth
                    )
            }

            return [
                supportDiagnosticsField("Database readable", "Yes"),
                supportDiagnosticsField("Local schema version", String(result.schemaVersion)),
                supportDiagnosticsField("Migration table", result.hasMigrationTable ? "Present" : "Missing"),
                supportDiagnosticsField("Applied migrations", String(result.migrationCount)),
                supportDiagnosticsField("Migration health", result.migrationHealth),
                supportDiagnosticsField("Schema tables", String(result.tableCount))
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
    let simulationState: @Sendable () async -> Bool

    init(
        authorization: SupportDiagnosticsAuthorization,
        featureOverrideState: @escaping @Sendable () async -> SupportDiagnosticsFeatureOverrideState,
        simulationState: @escaping @Sendable () async -> Bool = {
            await MainActor.run { SimulationSettings.shared.isEnabled }
        }
    ) {
        self.authorization = authorization
        self.featureOverrideState = featureOverrideState
        self.simulationState = simulationState
    }

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        let overrides = await featureOverrideState()
        let simulationEnabled = await simulationState()
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

private nonisolated struct DatabaseHealthReading: Sendable {
    let schemaVersion: Int
    let hasMigrationTable: Bool
    let tableCount: Int
    let migrationCount: Int
    let migrationHealth: String
}

private nonisolated struct SyncQueueReading: Sendable {
    let summary: SyncQueueSummary
    let oldestAge: String?
}

private nonisolated func syncQueueReading(now: Date = Date()) async throws -> SyncQueueReading {
    let databaseQueue = await MainActor.run { AppDatabase.shared.dbQueue }
    return try await databaseQueue.read { database in
        let pending = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM sync_queue WHERE status = ?",
            arguments: [SyncQueueStatus.pending.rawValue]
        ) ?? 0
        let inFlight = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM sync_queue WHERE status = ?",
            arguments: [SyncQueueStatus.inFlight.rawValue]
        ) ?? 0
        let failed = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM sync_queue WHERE status = ?",
            arguments: [SyncQueueStatus.failed.rawValue]
        ) ?? 0
        let poison = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM sync_queue WHERE status = ?",
            arguments: [SyncQueueStatus.poison.rawValue]
        ) ?? 0
        let lastAttempt = try Date.fetchOne(database, sql: "SELECT MAX(last_attempted_at) FROM sync_queue")
        let latestError = try String.fetchOne(
            database,
            sql: "SELECT error_reason FROM sync_queue WHERE error_reason IS NOT NULL ORDER BY updated_at DESC LIMIT 1"
        )
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
        let oldestAge = oldest.map { oldestDate -> String in
            let age = max(0, Int(now.timeIntervalSince(oldestDate)))
            if age < 60 { return "\(age)s" }
            if age < 3_600 { return "\(age / 60)m" }
            return "\(age / 3_600)h"
        }
        return SyncQueueReading(
            summary: SyncQueueSummary(
                pendingCount: pending,
                inFlightCount: inFlight,
                failedCount: failed,
                poisonCount: poison,
                lastAttemptedAt: lastAttempt,
                latestError: latestError
            ),
            oldestAge: oldestAge
        )
    }
}
