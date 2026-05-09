//
//  V2_add_request_id_to_sync_queue.swift
//  AmakaFlow
//
//  AMA-1823: add a nullable `request_id` column to `sync_queue` so each
//  attempt can stamp a fresh UUID that flows through to the BFF as the
//  `X-Request-ID` header. Lets us correlate iOS failure → Sentry
//  breadcrumb → mobile-bff structured log → mapper-api log in <60s.
//
//  Schema change is additive + nullable, so existing rows remain valid
//  and the migration is a single ALTER TABLE.
//

import Foundation
import GRDB

enum V2AddRequestIdToSyncQueue {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_add_request_id_to_sync_queue") { db in
            try db.alter(table: "sync_queue") { table in
                table.add(column: "request_id", .text)
            }
        }
    }
}
