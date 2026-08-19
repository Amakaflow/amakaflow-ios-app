//
//  LogbookDistanceScale.swift
//  AmakaFlow
//
//  AMA-2462 — distance has a SCALE, not just a unit.
//
//  The mi/km preference is a road-scale choice and must not reach an erg.
//  A Concept2 monitor, a Hyrox card and the gym whiteboard all read metres, so
//  rendering a 500 m ski as "0.31 MI" would be worse than showing nothing.
//  This is a property of the equipment, not an override the athlete manages —
//  which is what stops it drifting out of sync with the display in front of them.
//

import Foundation

enum LogbookDistanceScale: String, Equatable, Codable, Sendable {
    /// Ergs. Always metres, whatever the athlete picked.
    case machineMetres
    /// Runs, rides, sleds, carries. Follows `DistanceUnit.stored`.
    case road

    /// Word-level match, never substring: "Dumbbell Gorilla Row" contains "row"
    /// but is not a rower, and "Energy System Intervals" contains "erg".
    static func forExercise(named name: String) -> LogbookDistanceScale {
        let parts = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        let tokens = Set(parts.map(String.init))
        return tokens.contains(where: ergTokens.contains) ? .machineMetres : .road
    }

    /// Whole tokens only. `ski`/`bike` are deliberately absent — a bike can be a
    /// road ride, and only the `erg` alongside them makes it a machine.
    private static let ergTokens: Set<String> = [
        "erg", "ergo", "ergometer",
        "skierg", "bikeerg", "rowerg",
        "rower", "concept2", "c2"
    ]
}
