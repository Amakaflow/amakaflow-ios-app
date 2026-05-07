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
        do {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            let queue = try DatabaseQueue(configuration: config)
            return try AppDatabase(dbQueue: queue)
        } catch {
            // In-memory init should never fail in practice. If it does, SQLite is
            // catastrophically broken and crashing is the honest outcome.
            appDatabaseLog.fault("AppDatabase in-memory fallback failed: \(String(describing: error), privacy: .public)")
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "appdatabase_inmemory_fallback_failed", key: "subsystem")
            }
            fatalError("AppDatabase: in-memory fallback failed (sqlite catastrophic): \(error)")
        }
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
