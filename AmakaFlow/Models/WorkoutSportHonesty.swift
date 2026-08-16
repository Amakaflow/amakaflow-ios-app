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
        // EMOM / AMRAP / Tabata / circuit with lifts → conditioning (HIIT-ish).
        // Pure cardio circuits still fall through to machine-kind inference (mixed).
        if work.contains(where: isIntervalStructure), work.contains(where: blockHasLift) {
            return .conditioning
        }

        var flags = ContentFlags()
        for block in work {
            for exercise in block.exercises {
                flags.ingest(exercise)
            }
        }
        return flags.decideSport()
    }

    /// True when stored sport disagrees with content inference (show chip).
    static func disagrees(stored: WorkoutSport, blocks: [Block]) -> Bool {
        guard let inferred = inferSport(from: blocks) else { return false }
        if stored == .other { return true }
        return stored != inferred
    }

    static func disagreementPrompt(stored: WorkoutSport) -> String {
        "Is this a \(stored.displayName.lowercased()) workout?"
    }

    /// Hero / type-chip pill. Title is ignored — brands like HYROX are not wire sports.
    static func heroPill(sport: WorkoutSport, workoutName: String) -> String {
        _ = workoutName
        return sport.heroPill
    }

    private static let machineSymbols: [String: String] = [
        "bike": "bicycle",
        "row": "figure.rower",
        "ski": "figure.skiing.crosscountry",
        "treadmill": "figure.run",
        "elliptical": "figure.elliptical",
        "stair": "figure.stair.stepper",
        "jump": "figure.jumprope"
    ]

    /// SF Symbol for a circuit/exercise row (cardio machines ≠ dumbbell).
    static func systemImage(forExerciseName name: String) -> String {
        let lowered = name.lowercased()
        if let kind = machineKind(lowered), let symbol = machineSymbols[kind] {
            return symbol
        }
        if matchesRun(lowered) { return "figure.run" }
        if matches(lowered, ["swim", "freestyle", "backstroke", "breaststroke"]) {
            return "figure.pool.swim"
        }
        if matches(lowered, ["stretch", "mobility", "yoga", "foam roll"]) {
            return "figure.flexibility"
        }
        return "dumbbell.fill"
    }

    /// AMA-2395 — shared machine-kind key for pace tables / modality chips.
    /// Returns `"ski" | "row" | "bike" | "treadmill" | "elliptical" | "stair" | "jump"` or nil.
    static func machineKindKey(forExerciseName name: String) -> String? {
        machineKind(name.lowercased())
    }

    /// AMA-2395 — run/jog detection shared with the pace table (not treadmill).
    static func looksLikeRun(_ name: String) -> Bool {
        matchesRun(name.lowercased())
    }

    /// AMA-2395 — coarse modality bucket for chip tinting (cardio / bodyweight / lift).
    enum ModalityChipKind {
        case cardio
        case bodyweight
        case lift
    }

    static func modalityChipKind(forExerciseName name: String) -> ModalityChipKind {
        let lowered = name.lowercased()
        if machineKind(lowered) != nil || matchesRun(lowered) {
            return .cardio
        }
        // "jump rope" is classified as cardio via machineKind — omit it here.
        if matches(
            lowered,
            ["burpee", "bodyweight", "air squat", "push-up", "push up", "pull-up", "pull up"]
        ) {
            return .bodyweight
        }
        return .lift
    }

    // MARK: - Helpers

    private struct ContentFlags {
        var hasLift = false
        var hasCardio = false
        var hasRun = false
        var hasMobility = false
        var hasSwim = false
        var machineKinds = Set<String>()

        mutating func ingest(_ exercise: Exercise) {
            let name = exercise.name.lowercased()
            if let kind = machineKind(name) {
                hasCardio = true
                machineKinds.insert(kind)
                return
            }
            if matches(name, ["swim", "freestyle", "backstroke", "breaststroke"]) {
                hasSwim = true
                return
            }
            if matchesRun(name) {
                hasRun = true
                return
            }
            if matches(name, ["stretch", "mobility", "yoga", "foam roll", "spinal", "spine"]) {
                hasMobility = true
                return
            }
            if exercise.sets != nil || exercise.reps != nil || matches(
                name,
                ["barbell", "dumbbell", "squat", "deadlift", "press", "curl", "lunge", "burpee"]
            ) {
                hasLift = true
            }
        }

        func decideSport() -> WorkoutSport? {
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
    }

    private static func isIntervalStructure(_ block: Block) -> Bool {
        switch block.structure {
        case .emom, .tabata, .amrap, .circuit, .timedCircuit, .fortime:
            return true
        case .straight, .superset, .warmup, .cooldown:
            return false
        }
    }

    private static func blockHasLift(_ block: Block) -> Bool {
        block.exercises.contains { exercise in
            let name = exercise.name.lowercased()
            // Cardio machines with duration are not lifts even inside a circuit.
            if machineKind(name) != nil { return false }
            if exercise.sets != nil || exercise.reps != nil { return true }
            return matches(
                name,
                ["barbell", "dumbbell", "squat", "deadlift", "press", "curl", "lunge", "burpee"]
            )
        }
    }

    private static func isWarmupOrCooldown(_ block: Block) -> Bool {
        let label = (block.label ?? "").lowercased()
        if label.contains("warmup") || label.contains("warm-up") || label.contains("warm up")
            || label.contains("cooldown") || label.contains("cool-down") || label.contains("cool down")
            || label.contains("primer") {
            return true
        }
        return false
    }

    private static func machineKind(_ name: String) -> String? {
        let patterns: [(String, String)] = [
            ("ski erg", "ski"), ("skierg", "ski"),
            ("assault bike", "bike"), ("echo bike", "bike"), ("airdyne", "bike"),
            ("spin bike", "bike"), ("bike", "bike"),
            ("rowing", "row"), ("rower", "row"), ("row machine", "row"),
            ("treadmill", "treadmill"),
            ("elliptical", "elliptical"),
            ("stair", "stair"),
            ("jump rope", "jump")
        ]
        // Strength rows
        if name.contains("row") && (name.contains("dumbbell") || name.contains("barbell") || name.contains("cable")) {
            return nil
        }
        for (phrase, kind) in patterns where name.contains(phrase) {
            return kind
        }
        // Word-boundary "spin" / "erg" — avoid spine/energy false positives.
        if name.range(of: #"(^|[^a-z])spin([^a-z]|$)"#, options: .regularExpression) != nil {
            return "bike"
        }
        if name.range(of: #"(^|[^a-z])erg([^a-z]|$)"#, options: .regularExpression) != nil {
            return "ski"
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
