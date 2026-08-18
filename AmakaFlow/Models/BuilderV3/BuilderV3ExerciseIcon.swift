//
//  BuilderV3ExerciseIcon.swift
//  AmakaFlow
//
//  AMA-2450 — per-row icon chip for the exercise picker (screens-exsearch.jsx
//  `EXIconChip`).
//

import Foundation

/// Picks a row's glyph from its equipment key.
///
/// The rig keys its icon off the exercise's *category*, which the wire does not
/// give us per row: `ExerciseSearchResult.category` carries the movement class
/// ("compound" / "isolation"), and the browse category is only known from the
/// request, not from a search hit. Equipment is the one field present on every
/// row in both modes, and it is at least as informative — a rower and a barbell
/// should not share a glyph just because both are "strength".
///
/// Symbols are drawn only from names already shipping in this app
/// (`BuilderV3BrowseCategory.systemImage`) plus long-standing SF Symbols, so a
/// typo cannot render an invisible row.
enum BuilderV3ExerciseIcon {
    static func systemImage(equipmentKey: String?) -> String {
        guard let equipmentKey, !equipmentKey.isEmpty else { return bodyweight }
        switch equipmentKey {
        case "treadmill":
            return "figure.run"
        case "assault_bike", "stationary_bike":
            return "bicycle"
        case "stair_climber":
            return "figure.stairs"
        case "ski_erg", "rowing_machine":
            return "figure.mixed.cardio"
        case "bodyweight":
            return bodyweight
        default:
            // Barbell, dumbbells, kettlebells, cable, machine, benches, and any
            // catalogue key we have not enumerated: loaded movements.
            return "dumbbell.fill"
        }
    }

    private static let bodyweight = "figure.core.training"
}
