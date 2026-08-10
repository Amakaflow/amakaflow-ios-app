//
//  V5_actuals_sync_v2.swift
//  AmakaFlow
//
//  AMA-2396: sync v2 — per-session Strava write-back state, so un-verify /
//  remove-from-Strava / refresh-ours can restore or re-decorate without a
//  network round trip to know what happened last time.
//

import Foundation
import GRDB

enum V5ActualsSyncV2 {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5_actuals_sync_v2") { database in
            try database.alter(table: "actuals_sessions") { table in
                table.add(column: "strava_decoration", .text)
                table.add(column: "pre_update_title", .text)
                table.add(column: "pre_update_description", .text)
                table.add(column: "strava_activity_id", .text)
                table.add(column: "is_draft", .boolean).notNull().defaults(to: false)
            }
        }
    }
}
