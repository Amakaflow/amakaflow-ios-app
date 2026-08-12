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
    ///
    /// Uses an explicit phrase allow-list (word-boundary) plus a deny-list for
    /// common false positives (`Leg Press`, brand + machine presses, step-ups).
    static func resolve(exerciseName: String) -> NarrowRepExerciseFamily? {
        let normalized = normalize(exerciseName)
        guard !normalized.isEmpty else { return nil }

        if denyList.contains(where: { containsPhrase(normalized, phrase: $0) }) {
            return nil
        }

        // Longest matching allow phrase wins (avoids generic short tokens winning).
        var best: (family: NarrowRepExerciseFamily, length: Int)?
        for (family, phrases) in allowList {
            for phrase in phrases where containsPhrase(normalized, phrase: phrase) {
                if best == nil || phrase.count > best!.length {
                    best = (family, phrase.count)
                }
            }
        }
        return best?.family
    }

    // MARK: - Allow / deny

    /// Validated movement phrases only — no bare brand tokens (`hammer`) or
    /// unbounded `contains("press")` / `contains("bench")` matching.
    private static let allowList: [(NarrowRepExerciseFamily, [String])] = [
        (.curl, [
            "hammer curl",
            "bicep curl",
            "biceps curl",
            "preacher curl",
            "concentration curl",
            "cable curl",
            "barbell curl",
            "dumbbell curl",
            "db curl",
            "curl",
        ]),
        (.row, [
            "face pull",
            "bent over row",
            "seated row",
            "cable row",
            "barbell row",
            "dumbbell row",
            "db row",
            "pull down",
            "pulldown",
            "row",
        ]),
        (.swing, [
            "kettlebell swing",
            "kb swing",
            "russian swing",
            "swing",
        ]),
        (.press, [
            "bench press",
            "overhead press",
            "shoulder press",
            "military press",
            "push press",
            "chest press",
            "incline press",
            "decline press",
            "dumbbell press",
            "db press",
            "barbell press",
            "ohp",
        ]),
    ]

    /// Names that would otherwise collide with allow phrases.
    private static let denyList: [String] = [
        "leg press",
        "calf press",
        "hip press",
        "step up",
        "stepups",
        "box step",
        "bench step",
        "hammer strength", // brand / machine line — not hammer curls
    ]

    // MARK: - Matching helpers

    private static func normalize(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// True when `phrase` appears as whole word(s) inside `text`.
    private static func containsPhrase(_ text: String, phrase: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = "(^|\\s)\(escaped)(s)?($|\\s)"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
