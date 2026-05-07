//
//  AppDatabase.swift
//  AmakaFlow
//
//  Local-first GRDB database foundation for AMA-1791.
//

import Foundation
import GRDB

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

    static let shared: AppDatabase = {
        do {
            return try AppDatabase(path: defaultDatabaseURL().path)
        } catch {
            fatalError("Unable to initialize AppDatabase: \(error)")
        }
    }()

    static func defaultDatabaseURL(fileManager: FileManager = .default) -> URL {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            preconditionFailure("Unable to resolve Documents directory for durable AppDatabase storage")
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
