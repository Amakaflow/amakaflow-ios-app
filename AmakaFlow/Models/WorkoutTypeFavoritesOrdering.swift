// AmakaFlow/Models/WorkoutTypeFavoritesOrdering.swift
import Foundation

enum WorkoutTypeFavoritesOrdering {
    static let visibleChipLimit = 8

    /// Locked UI sequence (spec §2).
    static let categorySequence: [String] = [
        "run", "strength", "conditioning", "mobility",
        "recovery", "yoga", "ride", "mixed",
    ]

    static func orderedPresets(_ items: [WorkoutTypeItem]) -> [WorkoutTypeItem] {
        items
            .filter(\.aiPreset)
            .sorted { lhs, rhs in
                let li = categoryIndex(lhs.category)
                let ri = categoryIndex(rhs.category)
                if li != ri { return li < ri }
                return lhs.displayName < rhs.displayName
            }
    }

    static func visibleChips(from items: [WorkoutTypeItem]) -> [WorkoutTypeItem] {
        Array(orderedPresets(items).prefix(visibleChipLimit))
    }

    private static func categoryIndex(_ category: String) -> Int {
        let key = category.lowercased()
        if let idx = categorySequence.firstIndex(of: key) {
            return idx
        }
        return categorySequence.count
    }
}
