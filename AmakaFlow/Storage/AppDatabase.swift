//
//  AppDatabase.swift
//  AmakaFlow
//
//  Local-first GRDB database foundation for AMA-1791.
//

import Foundation
import GRDB
import Sentry
import os

private let appDatabaseLog = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "AppDatabase")

struct AppDatabase {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(path: path, configuration: config)
        try self.init(dbQueue: queue)
    }

    /// Resilient launch-time singleton.
    /// Attempts on-disk init first; on any failure (sandbox/IO/migration),
    /// reports via Sentry + os.Logger and falls back to an in-memory database
    /// so the app launches instead of fatalError-ing. Local-first features that
    /// hit disk become ephemeral until the next successful start, but the app
    /// stays up.
    static let shared: AppDatabase = makeShared()

    static func makeShared(fileManager: FileManager = .default) -> AppDatabase {
        if let url = defaultDatabaseURL(fileManager: fileManager) {
            do {
                return try AppDatabase(path: url.path)
            } catch {
                appDatabaseLog.error("AppDatabase on-disk init failed: \(String(describing: error), privacy: .public)")
                SentrySDK.capture(error: error) { scope in
                    scope.setTag(value: "appdatabase_init_failed", key: "subsystem")
                }
            }
        } else {
            appDatabaseLog.error("AppDatabase: Documents directory unavailable; using in-memory fallback")
            SentrySDK.capture(message: "AppDatabase: Documents directory unavailable; in-memory fallback")
        }
        // Per CR feedback on PR #175: separate queue creation from migration.
        // Only an in-memory DatabaseQueue allocation failure is catastrophic
        // (SQLite itself is broken). Migration failures are recoverable —
        // we keep the queue, log the error, and return an unmigrated AppDatabase
        // so the app launches. Repository operations against an unmigrated DB
        // throw at the call site rather than crashing on init.
        let queue: DatabaseQueue
        do {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            queue = try DatabaseQueue(configuration: config)
        } catch {
            // SQLite catastrophically broken. Crashing is the honest outcome.
            appDatabaseLog.fault("AppDatabase in-memory queue creation failed: \(String(describing: error), privacy: .public)")
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "appdatabase_inmemory_queue_failed", key: "subsystem")
            }
            fatalError("AppDatabase: in-memory DatabaseQueue init failed (sqlite catastrophic): \(error)")
        }
        do {
            return try AppDatabase(dbQueue: queue)
        } catch {
            appDatabaseLog.error("AppDatabase migration on in-memory queue failed: \(String(describing: error), privacy: .public)")
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "appdatabase_inmemory_migration_failed", key: "subsystem")
            }
            return AppDatabase(unmigratedQueue: queue)
        }
    }

    /// Internal initializer used only when a migration has already failed and
    /// we want to surface the queue without a successful schema. Repository
    /// operations against this DB will throw on first read/write and be caught
    /// downstream rather than crashing the app at launch.
    private init(unmigratedQueue: DatabaseQueue) {
        self.dbQueue = unmigratedQueue
    }

    /// Returns nil instead of crashing when Documents is unavailable.
    static func defaultDatabaseURL(fileManager: FileManager = .default) -> URL? {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documents.appendingPathComponent("amakaflow.sqlite")
    }

    static func makeTestDatabase() throws -> AppDatabase {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(configuration: config)
        return try AppDatabase(dbQueue: queue)
    }

    #if DEBUG
    func tableNames() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
    }

    func acceptedSuggestionCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM accepted_suggestions") ?? 0
        }
    }
    #endif

    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        V1InitialSchema.register(into: &migrator)
        return migrator
    }
}
