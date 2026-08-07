//
//  BuilderV3ExerciseLibrary.swift
//  AmakaFlow
//
//  AMA-2372 — demo/fixture exercise catalog for the multi-select picker.
//  Hevy-style rows: name + primary muscle + equipment tag, used both as the
//  offline fixture and as the local filter source before a query is typed.
//

import Foundation

enum BuilderV3BrowseCategory: String, CaseIterable, Identifiable {
    case cardio
    case strength
    case olympic
    case flexibility
    case plyometrics
    case strongman

    var id: String { rawValue }

    var queryValue: String {
        switch self {
        case .plyometrics: return "plyometric"
        default: return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .olympic: return "Olympic"
        case .plyometrics: return "Plyometrics"
        default: return rawValue.capitalized
        }
    }

    var systemImage: String {
        switch self {
        case .cardio: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .olympic: return "figure.strengthtraining.traditional"
        case .flexibility: return "figure.flexibility"
        case .plyometrics: return "figure.jumprope"
        case .strongman: return "figure.core.training"
        }
    }
}

struct BuilderV3ExerciseItem: Identifiable, Equatable, Sendable, Codable {
    var id: String
    var name: String
    var muscle: String
    /// Normalized equipment key (matches `EquipmentProfileViewModel.EquipmentItem.id`
    /// where possible) — `nil` means bodyweight / always available.
    var equipmentKey: String?
    var equipmentLabel: String

    init(
        id: String = UUID().uuidString,
        name: String,
        muscle: String,
        equipmentKey: String?,
        equipmentLabel: String
    ) {
        self.id = id
        self.name = name
        self.muscle = muscle
        self.equipmentKey = equipmentKey
        self.equipmentLabel = equipmentLabel
    }
}

enum BuilderV3ExerciseLibrary {
    /// Degraded-mode catalog. IDs intentionally mirror server-style stable slugs.
    static let demo: [BuilderV3ExerciseItem] = [
        BuilderV3ExerciseItem(id: "strength-bench-press", name: "Bench Press", muscle: "Chest", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(id: "strength-overhead-press", name: "Overhead Press", muscle: "Shoulders", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(id: "strength-triceps-pushdown", name: "Triceps Pushdown", muscle: "Triceps", equipmentKey: "cable", equipmentLabel: "Cable"),
        BuilderV3ExerciseItem(id: "strength-deadlift", name: "Deadlift", muscle: "Lower back", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(id: "strength-barbell-row", name: "Barbell Row", muscle: "Lats", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(id: "strength-lat-pulldown", name: "Lat Pulldown", muscle: "Lats", equipmentKey: "cable", equipmentLabel: "Cable"),
        BuilderV3ExerciseItem(id: "strength-back-squat", name: "Back Squat", muscle: "Quads", equipmentKey: "rack", equipmentLabel: "Rack"),
        BuilderV3ExerciseItem(id: "strength-romanian-deadlift", name: "Romanian Deadlift", muscle: "Hamstrings", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(id: "strength-leg-press", name: "Leg Press", muscle: "Quads", equipmentKey: "machine", equipmentLabel: "Machine"),
        BuilderV3ExerciseItem(id: "strength-goblet-squat", name: "Goblet Squat", muscle: "Quads", equipmentKey: "kettlebells", equipmentLabel: "Kettlebell"),
        BuilderV3ExerciseItem(id: "strength-pull-ups", name: "Pull Ups", muscle: "Lats", equipmentKey: "pull_up_bar", equipmentLabel: "Pull-up bar"),
        BuilderV3ExerciseItem(id: "strength-push-ups", name: "Push Ups", muscle: "Chest", equipmentKey: nil, equipmentLabel: "Bodyweight"),
        BuilderV3ExerciseItem(id: "cardio-ski-erg", name: "Ski Erg", muscle: "Conditioning", equipmentKey: "ski_erg", equipmentLabel: "Ski Erg"),
        BuilderV3ExerciseItem(id: "cardio-treadmill-run", name: "Treadmill Run", muscle: "Conditioning", equipmentKey: "treadmill", equipmentLabel: "Treadmill"),
        BuilderV3ExerciseItem(id: "cardio-rowing-machine", name: "Rowing Machine", muscle: "Conditioning", equipmentKey: "rowing_machine", equipmentLabel: "Rower"),
        BuilderV3ExerciseItem(id: "cardio-assault-bike", name: "Assault Bike", muscle: "Conditioning", equipmentKey: "assault_bike", equipmentLabel: "Assault bike"),
        BuilderV3ExerciseItem(id: "cardio-stationary-bike", name: "Spin / Indoor Bike", muscle: "Conditioning", equipmentKey: "stationary_bike", equipmentLabel: "Stationary bike"),
        BuilderV3ExerciseItem(id: "cardio-stair-climber", name: "Stair Climber", muscle: "Conditioning", equipmentKey: "stair_climber", equipmentLabel: "Stair climber"),
        BuilderV3ExerciseItem(id: "plyometric-db-thrusters", name: "DB Thrusters", muscle: "Full body", equipmentKey: "dumbbells", equipmentLabel: "Dumbbells"),
        BuilderV3ExerciseItem(id: "plyometric-kb-swing", name: "KB Swing", muscle: "Glutes", equipmentKey: "kettlebells", equipmentLabel: "Kettlebell"),
        BuilderV3ExerciseItem(id: "plyometric-wall-balls", name: "Wall Balls", muscle: "Full body", equipmentKey: "med_ball", equipmentLabel: "Med ball"),
        BuilderV3ExerciseItem(id: "plyometric-burpees", name: "Burpees", muscle: "Full body", equipmentKey: nil, equipmentLabel: "Bodyweight"),
        BuilderV3ExerciseItem(id: "flexibility-hip-flexor-stretch", name: "Hip Flexor Stretch", muscle: "Hip flexors", equipmentKey: nil, equipmentLabel: "Bodyweight"),
        BuilderV3ExerciseItem(id: "flexibility-thoracic-rotations", name: "Thoracic Rotations", muscle: "Upper back", equipmentKey: nil, equipmentLabel: "Bodyweight"),
        BuilderV3ExerciseItem(id: "olympic-clean-and-jerk", name: "Clean and Jerk", muscle: "Full body", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(id: "strongman-farmers-carry", name: "Farmer's Carry", muscle: "Full body", equipmentKey: "dumbbells", equipmentLabel: "Dumbbells")
    ]

    /// A small "recently used" slice for the Recent tab fixture.
    static let recentDefaultNames = ["Bench Press", "Back Squat", "Pull Ups", "Burpees"]

    static let recent: [BuilderV3ExerciseItem] = recentDefaultNames.compactMap { name in
        demo.first { $0.name == name }
    }

    static let strengthMuscleChips: [(label: String, key: String)] = [
        ("Chest", "chest"), ("Lats", "lats"), ("Shoulders", "shoulders"),
        ("Quads", "quadriceps"), ("Hamstrings", "hamstrings"), ("Glutes", "glutes"),
        ("Biceps", "biceps"), ("Triceps", "triceps"), ("Core", "abs")
    ]

    static let cardioEquipmentChips: [(label: String, key: String)] = [
        ("Ski Erg", "ski_erg"), ("Treadmill", "treadmill"),
        ("Rower", "rowing_machine"), ("Assault", "assault_bike"),
        ("Bike", "stationary_bike"), ("Stairs", "stair_climber")
    ]

    private static let equipmentLabels: [String: String] = [
        "barbell": "Barbell",
        "dumbbells": "Dumbbells",
        "kettlebells": "Kettlebell",
        "cable": "Cable",
        "machine": "Machine",
        "bodyweight": "Bodyweight",
        "ski_erg": "Ski Erg",
        "treadmill": "Treadmill",
        "rowing_machine": "Rower",
        "assault_bike": "Assault bike",
        "stationary_bike": "Stationary bike",
        "stair_climber": "Stair climber",
    ]

    nonisolated static func equipmentFilterLabel(_ key: String) -> String {
        equipmentLabels[key] ?? key.capitalized
    }

    static func fixtureItems(category: String, muscle: String?, equipment: String?) -> [BuilderV3ExerciseItem] {
        demo.filter { item in
            guard item.id.hasPrefix("\(category)-") else { return false }
            if let muscle, canonicalMuscle(for: item) != muscle { return false }
            if let equipment, item.equipmentKey != equipment { return false }
            return true
        }
    }

    private static func canonicalMuscle(for item: BuilderV3ExerciseItem) -> String {
        switch item.muscle.lowercased() {
        case "quads": return "quadriceps"
        case "hip flexors": return "hip_flexors"
        case "upper back": return "upper_back"
        case "lower back": return "lower_back"
        default: return item.muscle.lowercased().replacingOccurrences(of: " ", with: "_")
        }
    }

    static func matches(_ item: BuilderV3ExerciseItem, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return item.name.lowercased().contains(needle) || item.muscle.lowercased().contains(needle)
    }
}
