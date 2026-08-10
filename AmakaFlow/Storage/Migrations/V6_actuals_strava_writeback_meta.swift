//
//  V6_actuals_strava_writeback_meta.swift
//  AmakaFlow
//
//  AMA-2396: persist Strava sport/description so write-back still evaluates
//  after a cold launch (skip rules need activity type).
//

import Foundation
import GRDB

enum V6ActualsStravaWriteBackMeta {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v6_actuals_strava_writeback_meta") { database in
            try database.alter(table: "actuals_sessions") { table in
                table.add(column: "strava_activity_type", .text)
                table.add(column: "strava_current_description", .text)
                table.add(column: "strava_recording_app", .text)
                table.add(column: "strava_is_race", .boolean).notNull().defaults(to: false)
            }
        }
    }
}
