//
//  NarrowRepExerciseFamily.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 Phase 5 — validated exercise families for narrow rep assist.
//  Unsupported names never receive IMU rep proposals (no silent invent).
//

import Foundation

/// Curated families where wrist IMU + peak segmentation is a reasonable assist.
enum NarrowRepExerciseFamily: String, Equatable, Codable, CaseIterable {
    case curl
    case press
    case row
    case swing

    var displayName: String {
        switch self {
        case .curl: return "Curl"
        case .press: return "Press"
        case .row: return "Row"
        case .swing: return "Swing"
        }
    }

    /// Map a planned exercise name to a supported family, or `nil` if unsupported.
    static func resolve(exerciseName: String) -> NarrowRepExerciseFamily? {
        let normalized = exerciseName
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        // Order matters: more specific tokens first (e.g. "press" before generic).
        let rules: [(NarrowRepExerciseFamily, [String])] = [
            (.curl, ["curl", "bicep", "hammer"]),
            (.row, ["row", "pulldown", "pull down", "face pull"]),
            (.swing, ["swing", "kb swing", "kettlebell swing"]),
            (.press, ["press", "bench", "overhead", "ohp", "push press", "military"]),
        ]

        for (family, keywords) in rules {
            if keywords.contains(where: { normalized.contains($0) }) {
                return family
            }
        }
        return nil
    }
}
