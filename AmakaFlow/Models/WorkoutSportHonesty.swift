//
//  WorkoutSportHonesty.swift
//  AmakaFlow
//
//  AMA-2393 — content-based sport inference for the disagreement chip.
//  Mirrors mapper `activity_classifier` buckets at a light client level so we
//  can flag "stored label ≠ content" without silently rewriting.
//

import Foundation

enum WorkoutSportHonesty {
    /// Lightweight content inference used only for the quiet disagreement chip.
    /// Never writes sport — flag only.
    static func inferSport(from blocks: [Block]) -> WorkoutSport? {
        let work = blocks.filter { !isWarmupOrCooldown($0) }
        var hasLift = false
        var hasCardio = false
        var hasRun = false
        var hasMobility = false
        var hasSwim = false
        var machineKinds = Set<String>()

        for block in work {
            for exercise in block.exercises {
                let name = exercise.name.lowercased()
                if let kind = machineKind(name) {
                    hasCardio = true
                    machineKinds.insert(kind)
                    continue
                }
                if matches(name, ["swim", "freestyle", "backstroke", "breaststroke"]) {
                    hasSwim = true
                    continue
                }
                if matchesRun(name) {
                    hasRun = true
                    continue
                }
                if matches(name, ["stretch", "mobility", "yoga", "foam roll"]) {
                    hasMobility = true
                    continue
                }
                if exercise.sets != nil || exercise.reps != nil || matches(
                    name,
                    ["barbell", "dumbbell", "squat", "deadlift", "press", "curl", "lunge", "burpee"]
                ) {
                    hasLift = true
                }
            }
        }

        if hasMobility && !hasLift && !hasCardio && !hasRun && !hasSwim {
            return .mobility
        }
        if hasSwim && !hasLift && !hasCardio && !hasRun {
            return .swimming
        }
        if hasRun && !hasLift && !hasCardio {
            return .running
        }
        if hasCardio && !hasLift {
            if machineKinds.count >= 2 {
                return .mixed
            }
            if machineKinds.contains("bike") { return .cycling }
            if machineKinds.contains("treadmill") { return .running }
            return .conditioning
        }
        if hasLift && hasCardio {
            return .conditioning
        }
        if hasLift {
            return .strength
        }
        return nil
    }

    /// True when stored sport disagrees with content inference (show chip).
    static func disagrees(stored: WorkoutSport, blocks: [Block]) -> Bool {
        guard let inferred = inferSport(from: blocks) else { return false }
        if stored == .other { return true }
        return normalize(stored) != normalize(inferred)
    }

    static func disagreementPrompt(stored: WorkoutSport) -> String {
        "Is this a \(stored.displayName.lowercased()) workout?"
    }

    // MARK: - Helpers

    private static func normalize(_ sport: WorkoutSport) -> WorkoutSport {
        if sport == .cardio { return .conditioning }
        return sport
    }

    private static func isWarmupOrCooldown(_ block: Block) -> Bool {
        let label = (block.label ?? "").lowercased()
        if label.contains("warmup") || label.contains("warm-up") || label.contains("warm up")
            || label.contains("cooldown") || label.contains("cool-down") || label.contains("cool down")
            || label.contains("primer")
        {
            return true
        }
        return false
    }

    private static func machineKind(_ name: String) -> String? {
        let patterns: [(String, String)] = [
            ("ski erg", "ski"), ("skierg", "ski"),
            ("assault bike", "bike"), ("echo bike", "bike"), ("airdyne", "bike"),
            ("spin", "bike"), ("bike", "bike"),
            ("rowing", "row"), ("rower", "row"), ("row machine", "row"),
            ("treadmill", "treadmill"),
            ("elliptical", "elliptical"),
            ("stair", "stair"),
            ("jump rope", "jump"),
        ]
        // Strength rows
        if name.contains("row") && (name.contains("dumbbell") || name.contains("barbell") || name.contains("cable")) {
            return nil
        }
        for (phrase, kind) in patterns where name.contains(phrase) {
            return kind
        }
        return nil
    }

    private static func matches(_ name: String, _ needles: [String]) -> Bool {
        needles.contains { name.contains($0) }
    }

    private static func matchesRun(_ name: String) -> Bool {
        if name.contains("treadmill") { return false }
        let pattern = #"(^|[^a-z])(run|jog)([^a-z]|$)"#
        return name.range(of: pattern, options: .regularExpression) != nil
            || name.contains("tempo run")
            || name.contains("stride")
    }
}
