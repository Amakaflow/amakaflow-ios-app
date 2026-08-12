//
//  StravaActivityClassification.swift
//  AmakaFlow
//
//  AMA-2411 — shared Strava sport_type (+ title) → Actuals type / list icon.
//  Generic `Workout` often means gym cardio machines; peek at the title before
//  defaulting to strength so Ski Row / Assault bike don't show a dumbbell.
//

import Foundation

enum StravaActivityClassification {
    /// Maps Strava `sport_type` / legacy `type` (+ activity title) to Actuals card type.
    static func actualsWorkoutType(sportType: String, title: String) -> ActualsWorkoutType {
        switch normalizedSportType(sportType) {
        case "run", "virtualrun", "trailrun", "walk", "hike":
            return .run
        case "ride", "virtualride", "ebikeride", "gravelride", "mountainbikeride":
            return .ride
        case "elliptical", "highintensityintervaltraining":
            // Machine cardio / HIIT — not pure strength (AMA-2411).
            return .other
        case "weighttraining", "crossfit", "yoga":
            return .strength
        case "workout":
            return titleSuggestsCardioMachine(title) ? .other : .strength
        default:
            return .other
        }
    }

    /// SF Symbol for Strava list rows — keep in sync with Actuals Today type mapping.
    static func typeIcon(sportType: String, title: String) -> String {
        switch normalizedSportType(sportType) {
        case "run", "virtualrun", "trailrun":
            return "figure.run"
        case "ride", "virtualride", "ebikeride", "gravelride", "mountainbikeride":
            return "bicycle"
        case "swim":
            return "figure.pool.swim"
        case "walk", "hike":
            return "figure.walk"
        case "yoga":
            return "figure.mind.and.body"
        case "weighttraining", "crossfit":
            return "dumbbell.fill"
        case "elliptical":
            return "figure.elliptical"
        case "highintensityintervaltraining":
            return "figure.mixed.cardio"
        case "workout":
            return titleSuggestsCardioMachine(title)
                ? "figure.mixed.cardio"
                : "figure.strengthtraining.traditional"
        default:
            return "figure.mixed.cardio"
        }
    }

    /// True when a generic `Workout` title reads as machine / gym cardio.
    static func titleSuggestsCardioMachine(_ title: String) -> Bool {
        let lowered = title.lowercased()
        // Reuse exercise-name machine heuristics (assault bike, rower, ski erg, …).
        if WorkoutSportHonesty.machineKindKey(forExerciseName: title) != nil {
            return true
        }
        // Strength "row" variants stay strength (bent-over / cable / etc.).
        if looksLikeStrengthRow(lowered) {
            return false
        }
        // Activity titles are looser than exercise names ("Ski Row", "Cardio").
        if containsWord(lowered, "ski")
            || containsWord(lowered, "row")
            || containsWord(lowered, "rower")
            || containsWord(lowered, "erg")
            || containsWord(lowered, "assault")
            || containsWord(lowered, "airbike")
            || lowered.contains("air bike")
            || containsWord(lowered, "bike")
            || containsWord(lowered, "elliptical")
            || containsWord(lowered, "cardio")
            || containsWord(lowered, "treadmill")
            || containsWord(lowered, "stair")
            || containsWord(lowered, "spin") {
            return true
        }
        return false
    }

    // MARK: - Helpers

    private static func normalizedSportType(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func looksLikeStrengthRow(_ lowered: String) -> Bool {
        lowered.contains("row")
            && (lowered.contains("dumbbell")
                || lowered.contains("barbell")
                || lowered.contains("cable")
                || lowered.contains("seated")
                || lowered.contains("bent"))
    }

    private static func containsWord(_ haystack: String, _ word: String) -> Bool {
        let pattern = "(^|[^a-z0-9])\(NSRegularExpression.escapedPattern(for: word))([^a-z0-9]|$)"
        return haystack.range(of: pattern, options: .regularExpression) != nil
    }
}
