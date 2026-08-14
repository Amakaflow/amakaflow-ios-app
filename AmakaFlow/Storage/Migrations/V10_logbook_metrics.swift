//
//  V10_logbook_metrics.swift
//  AmakaFlow
//
//  AMA-2426: duration / calories / distance on set rows for timed & cardio stations.
//

import Foundation
import GRDB

enum V10LogbookMetrics {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v10_logbook_metrics") { database in
            try database.alter(table: "actuals_set_rows") { table in
                table.add(column: "duration_seconds", .integer)
                table.add(column: "calories", .integer)
                table.add(column: "distance_meters", .double)
            }
        }
    }
}
