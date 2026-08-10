//
//  V7_actuals_structure_body.swift
//  AmakaFlow
//
//  AMA-2396: persist full Library structure text for Strava write-back.
//

import Foundation
import GRDB

enum V7ActualsStructureBody {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7_actuals_structure_body") { database in
            try database.alter(table: "actuals_sessions") { table in
                table.add(column: "structure_body", .text)
            }
        }
    }
}
