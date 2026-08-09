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

        var hasLift = false
        var hasCardio = false
        var hasRun = false
        var hasMobility = false
        var hasSwim = false
        var machineKinds = Set<String>()

        for block in work {
            for exercise in block.exercises {
                classifyExercise(
                    exercise,
                    hasLift: &hasLift,
                    hasCardio: &hasCardio,
                    hasRun: &hasRun,
                    hasMobility: &hasMobility,
                    hasSwim: &hasSwim,
                    machineKinds: &machineKinds
                )
            }
        }

        return decideSport(
            hasLift: hasLift,
            hasCardio: hasCardio,
            hasRun: hasRun,
            hasMobility: hasMobility,
            hasSwim: hasSwim,
            machineKinds: machineKinds
        )
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

    // MARK: - Helpers

    private static func isIntervalStructure(_ block: Block) -> Bool {
        switch block.structure {
        case .emom, .tabata, .amrap, .circuit, .timedCircuit:
            return true
        case .straight, .superset:
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

    private static func classifyExercise(
        _ exercise: Exercise,
        hasLift: inout Bool,
        hasCardio: inout Bool,
        hasRun: inout Bool,
        hasMobility: inout Bool,
        hasSwim: inout Bool,
        machineKinds: inout Set<String>
    ) {
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
        if matches(name, ["stretch", "mobility", "yoga", "foam roll"]) {
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

    private static func decideSport(
        hasLift: Bool,
        hasCardio: Bool,
        hasRun: Bool,
        hasMobility: Bool,
        hasSwim: Bool,
        machineKinds: Set<String>
    ) -> WorkoutSport? {
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
