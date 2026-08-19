//
//  LogbookTrackedFields.swift
//  AmakaFlow
//
//  AMA-2462 slice 2 — the plan proposes the fields, the athlete decides which
//  stay. A field that is off is ABSENT: no column, no wheel, no empty dash to
//  skip past. That is what lets one row shape cover a chin-up, a belted
//  chin-up, a barbell row, a Ski Erg, a Rower and an Assault Bike with no
//  per-machine code.
//

import Foundation

enum LogbookTrackedField: String, Equatable, Codable, Sendable, CaseIterable {
    case reps
    case weight
    case time
    case distance
    case calories

    /// Column order is fixed so the grid never reshuffles between exercises.
    static let canonicalOrder: [LogbookTrackedField] = [.weight, .reps, .time, .distance, .calories]
}

extension Array where Element == LogbookTrackedField {
    /// Deduplicated and sorted into `canonicalOrder`.
    var canonical: [LogbookTrackedField] {
        LogbookTrackedField.canonicalOrder.filter(contains)
    }
}

/// Whether a movement carries its own load. Needed because "weight" on a
/// chin-up means ADDED weight (a belt or dumbbell), not absolute — a belted
/// chin-up is `+25`, never `200`, and Progress must never read it as absolute.
enum LogbookMovementClass {
    /// Deliberately conservative: a false positive silently removes the load
    /// column from a movement someone loads, which is worse than showing a
    /// column they can turn off. Word-level matching for the same reason as
    /// `LogbookDistanceScale` — no substrings.
    static func isBodyweight(named name: String) -> Bool {
        let tokens = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let joined = tokens.joined(separator: " ")
        if loadedQualifiers.contains(where: tokens.contains) { return false }
        return bodyweightPhrases.contains { joined.contains($0) }
    }

    /// If any of these appear, the athlete has already said it is loaded.
    private static let loadedQualifiers: Set<String> = [
        "weighted", "barbell", "dumbbell", "kettlebell", "banded", "machine", "cable"
    ]

    /// Phrase-level so "pull up" and "pullup" both match without matching "pull".
    private static let bodyweightPhrases: [String] = [
        "pull up", "pullup", "pull ups", "pullups",
        "chin up", "chinup", "chin ups", "chinups",
        "muscle up", "muscleup",
        "push up", "pushup", "push ups", "pushups",
        "sit up", "situp", "sit ups", "situps",
        "dip", "dips",
        "burpee", "burpees",
        "air squat", "air squats",
        "box jump", "box jumps",
        "toes to bar", "knees to elbows",
        "plank", "mountain climber", "mountain climbers"
    ]
}

/// What the plan prescribes for one exercise — grouped so the defaults
/// function reads as "name + kind + prescription" rather than six loose
/// optionals in an order nobody can remember.
struct LogbookPrescription: Equatable {
    var weightKg: Double?
    var durationSeconds: Int?
    var distanceMeters: Int?
    var calories: Int?
}

extension LogbookTrackedField {
    /// The opening state. Never binding — the athlete can change it, and
    /// `LogbookExerciseEntry.trackedFields` prefers their choice when present.
    static func defaults(
        forExerciseNamed name: String,
        loggingKind: LogbookLoggingKind,
        prescription: LogbookPrescription
    ) -> [LogbookTrackedField] {
        if loggingKind == .metric {
            var fields: [LogbookTrackedField] = []
            if prescription.durationSeconds != nil { fields.append(.time) }
            if prescription.distanceMeters != nil { fields.append(.distance) }
            if prescription.calories != nil { fields.append(.calories) }
            // A metric station with nothing prescribed still needs one field to
            // log into; time is the only one every machine can report.
            return fields.isEmpty ? [.time] : fields.canonical
        }

        var fields: [LogbookTrackedField] = [.reps]
        // Bodyweight and unloaded → reps only. The load column is absent rather
        // than sitting on a meaningless zero; `＋ Weight` promotes it in one tap.
        let bodyweightAndUnloaded =
            LogbookMovementClass.isBodyweight(named: name) && prescription.weightKg == nil
        if !bodyweightAndUnloaded { fields.append(.weight) }
        return fields.canonical
    }
}
