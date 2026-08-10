//
//  V8_actuals_exercise_structure.swift
//  AmakaFlow
//
//  AMA-2396: persist per-exercise structure header / block index so fill-in
//  and verified screens can show TRI-SET / SUPERSET bands (parity with Strava).
//

import Foundation
import GRDB

enum V8ActualsExerciseStructure {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v8_actuals_exercise_structure") { database in
            try database.alter(table: "actuals_exercise_rows") { table in
                table.add(column: "structure_header", .text)
                table.add(column: "structure_block_index", .integer)
            }
        }
    }
}
