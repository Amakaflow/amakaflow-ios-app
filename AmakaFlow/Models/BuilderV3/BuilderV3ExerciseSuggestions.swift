//
//  BuilderV3ExerciseSuggestions.swift
//  AmakaFlow
//
//  AMA-2443 slice 2b — "Suggested for this workout" logic and did-you-mean helpers.
//

import Foundation

enum BuilderV3ExerciseSuggestions {
    /// Rank catalog exercises by overlap with the current canvas's exercises.
    /// Returns up to `limit` names, ranked by relevance (most relevant first).
    ///
    /// Strategy: prefer exercises from the same muscle groups and with similar
    /// equipment to what's already on the canvas.
    static func suggestedExercises(
        canvasNames: [String],
        catalog: [BuilderV3ExerciseItem],
        limit: Int = 6
    ) -> [BuilderV3ExerciseItem] {
        // Extract muscles and equipment from canvas
        let canvasMuscles = Set(
            canvasNames.compactMap { name -> String? in
                catalog.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.muscle.lowercased()
            }
        )
        let canvasEquipment = Set(
            canvasNames.compactMap { name -> String? in
                catalog.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.equipmentKey
            }
        )
        
        // Filter out exercises already on canvas
        let canvasNamesLower = Set(canvasNames.map { $0.lowercased() })
        let candidates = catalog.filter { !canvasNamesLower.contains($0.name.lowercased()) }
        
        // Score each candidate by muscle + equipment overlap
        let scored = candidates.map { item -> (item: BuilderV3ExerciseItem, score: Int) in
            var score = 0
            if canvasMuscles.contains(item.muscle.lowercased()) {
                score += 2
            }
            if let key = item.equipmentKey, canvasEquipment.contains(key) {
                score += 1
            } else if item.equipmentKey == nil && canvasEquipment.isEmpty {
                score += 1
            }
            return (item, score)
        }
        
        // Sort by score descending, then alphabetically for stable ties
        let sorted = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
        }
        
        return Array(sorted.prefix(limit).map(\.item))
    }
    
    /// Attempt to correct a typed query against the catalog. Returns the best
    /// match's name if a close-enough match exists, otherwise nil.
    ///
    /// Tolerates: missing/extra spaces, common typos, plural/singular mismatch.
    static func didYouMean(query: String, catalog: [BuilderV3ExerciseItem]) -> String? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        
        // Normalize spaces in catalog names
        let normalized = catalog.map { item -> (name: String, normalized: String) in
            let norm = item.name.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return (item.name, norm)
        }
        
        // Check for space-tolerant match
        let needleNoSpaces = needle.replacingOccurrences(of: " ", with: "")
        for (originalName, norm) in normalized {
            let normNoSpaces = norm.replacingOccurrences(of: " ", with: "")
            if normNoSpaces == needleNoSpaces {
                return originalName
            }
        }
        
        // Check for close Levenshtein distance (≤2 edits for queries >4 chars)
        if needle.count > 4 {
            for (originalName, norm) in normalized {
                let distance = levenshteinDistance(needle, norm)
                if distance <= 2 {
                    return originalName
                }
            }
        }
        
        return nil
    }
    
    /// Simple Levenshtein distance for small strings (exercise names).
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count {
            dp[i][0] = i
        }
        for j in 0...b.count {
            dp[0][j] = j
        }
        
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dp[i][j] = min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
            }
        }
        
        return dp[a.count][b.count]
    }
}
