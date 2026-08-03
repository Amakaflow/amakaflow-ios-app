//
//  BuilderV3ExerciseLibrary.swift
//  AmakaFlow
//
//  AMA-2372 — demo/fixture exercise catalog for the multi-select picker.
//  Hevy-style rows: name + primary muscle + equipment tag, used both as the
//  offline fixture and as the local filter source before a query is typed.
//

import Foundation

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
    /// Demo/fixture catalog — used for `Recent`/`All` browsing and as the
    /// search-client fallback when the live endpoint is unavailable or a
    /// Maestro/UITEST run requests fixtures.
    static let demo: [BuilderV3ExerciseItem] = [
        BuilderV3ExerciseItem(name: "Bench Press", muscle: "Chest", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(name: "Overhead Press", muscle: "Shoulders", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(name: "Triceps Pushdown", muscle: "Triceps", equipmentKey: "cable", equipmentLabel: "Cable"),
        BuilderV3ExerciseItem(name: "Deadlift", muscle: "Back", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(name: "Barbell Row", muscle: "Back", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(name: "Lat Pulldown", muscle: "Back", equipmentKey: "cable", equipmentLabel: "Cable"),
        BuilderV3ExerciseItem(name: "Back Squat", muscle: "Quads", equipmentKey: "rack", equipmentLabel: "Rack"),
        BuilderV3ExerciseItem(name: "Romanian Deadlift", muscle: "Hamstrings", equipmentKey: "barbell", equipmentLabel: "Barbell"),
        BuilderV3ExerciseItem(name: "Leg Press", muscle: "Quads", equipmentKey: "machine", equipmentLabel: "Machine"),
        BuilderV3ExerciseItem(name: "Goblet Squat", muscle: "Quads", equipmentKey: "kettlebells", equipmentLabel: "Kettlebell"),
        BuilderV3ExerciseItem(name: "DB Thrusters", muscle: "Full body", equipmentKey: "dumbbells", equipmentLabel: "Dumbbells"),
        BuilderV3ExerciseItem(name: "KB Swing", muscle: "Posterior", equipmentKey: "kettlebells", equipmentLabel: "Kettlebell"),
        BuilderV3ExerciseItem(name: "Wall Balls", muscle: "Full body", equipmentKey: "med_ball", equipmentLabel: "Med ball"),
        BuilderV3ExerciseItem(name: "Rower", muscle: "Conditioning", equipmentKey: "rower", equipmentLabel: "Rower"),
        BuilderV3ExerciseItem(name: "Assault Bike", muscle: "Conditioning", equipmentKey: "assault_bike", equipmentLabel: "Assault bike"),
        BuilderV3ExerciseItem(name: "Burpees", muscle: "Full body", equipmentKey: nil, equipmentLabel: "Bodyweight"),
        BuilderV3ExerciseItem(name: "Pull Ups", muscle: "Back", equipmentKey: "pull_up_bar", equipmentLabel: "Pull-up bar"),
        BuilderV3ExerciseItem(name: "Push Ups", muscle: "Chest", equipmentKey: nil, equipmentLabel: "Bodyweight"),
        BuilderV3ExerciseItem(name: "Hip Flexor Stretch", muscle: "Mobility", equipmentKey: nil, equipmentLabel: "Bodyweight"),
        BuilderV3ExerciseItem(name: "Thoracic Rotations", muscle: "Mobility", equipmentKey: nil, equipmentLabel: "Bodyweight")
    ]

    /// A small "recently used" slice for the Recent tab fixture.
    static let recentDefaultNames = ["Bench Press", "Back Squat", "Pull Ups", "Burpees"]

    static let recent: [BuilderV3ExerciseItem] = recentDefaultNames.compactMap { name in
        demo.first { $0.name == name }
    }

    static let muscleFilters: [String] = ["Chest", "Back", "Quads", "Hamstrings", "Shoulders", "Full body"]
    static let equipmentFilters: [String] = ["barbell", "dumbbells", "kettlebells", "cable", "machine", "bodyweight"]

    nonisolated static func equipmentFilterLabel(_ key: String) -> String {
        switch key {
        case "barbell": return "Barbell"
        case "dumbbells": return "Dumbbells"
        case "kettlebells": return "Kettlebell"
        case "cable": return "Cable"
        case "machine": return "Machine"
        case "bodyweight": return "Bodyweight"
        default: return key.capitalized
        }
    }

    static func matches(_ item: BuilderV3ExerciseItem, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return item.name.lowercased().contains(needle) || item.muscle.lowercased().contains(needle)
    }
}
