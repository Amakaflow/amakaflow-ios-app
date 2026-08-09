//
//  WorkoutSportHonesty.swift
//  AmakaFlow
//
//  AMA-2393 — content-based sport inference for the disagreement chip.
//  Mirrors mapper `activity_classifier` buckets at a light client level so we
//  can flag "stored label ≠ content" without silently rewriting.
//

import Foundation

/// AMA-2395 — display modality for the per-exercise icon chip. Derived from the
/// SAME name tables `WorkoutSportHonesty` uses for sport inference (AMA-2393):
/// one source of truth, imported not copied.
enum WorkoutModality: String, CaseIterable {
    /// Ski / row / bike / assault / spin / treadmill / elliptical / stair.
    case cardioMachine
    case run
    case lift
    /// Bodyweight movements + jump rope.
    case bodyweight
    /// Nothing matched — renders the neutral lift chip.
    case unknown
}

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

    // MARK: - Modality (AMA-2395 icon chips)

    /// Cardio-machine kind (`ski` / `row` / `bike` / `treadmill` / …) or nil.
    /// The AMA-2395 pace table keys off this so there is one machine table.
    static func machineKindKey(forName rawName: String) -> String? {
        machineKind(rawName.lowercased())
    }

    /// Display modality for one exercise. Order matters: cardio machines first
    /// (a "Ski Erg" is never a lift), then run, then bodyweight, then lifts.
    static func modality(for exercise: Exercise) -> WorkoutModality {
        // A bodyweight load tag only wins when the name isn't a machine
        // (a bodyweight-tagged Assault Bike is still a bike).
        if exercise.load?.unit.lowercased() == "bodyweight",
           machineKind(exercise.name.lowercased()) == nil {
            return .bodyweight
        }
        return modality(
            forName: exercise.name,
            hasSetsOrReps: exercise.sets != nil || exercise.reps != nil
        )
    }

    /// Name-only modality — used where no `Exercise` is in hand (band titles).
    static func modality(forName rawName: String, hasSetsOrReps: Bool = false) -> WorkoutModality {
        let name = rawName.lowercased()
        if let kind = machineKind(name) {
            // Jump rope lives in the machine table for sport inference but reads
            // as a bodyweight (amber bolt) chip.
            return kind == "jump" ? .bodyweight : .cardioMachine
        }
        if matchesRun(name) { return .run }
        if matches(name, bodyweightNeedles) { return .bodyweight }
        if matches(name, liftNeedles) { return .lift }
        return hasSetsOrReps ? .lift : .unknown
    }

    /// Dominant modality across a set of exercises — drives derived band names
    /// (`CONDITIONING` / `CORE` / `ACCESSORIES`) for untitled mixed blocks.
    static func dominantModality(of exercises: [Exercise]) -> WorkoutModality {
        var counts: [WorkoutModality: Int] = [:]
        for exercise in exercises {
            counts[modality(for: exercise), default: 0] += 1
        }
        guard let best = counts.values.max(), best > 0 else { return .unknown }
        // Ties resolve in a stable, meaningful order rather than dictionary order.
        let priority: [WorkoutModality] = [.cardioMachine, .run, .lift, .bodyweight, .unknown]
        return priority.first { counts[$0] == best } ?? .unknown
    }

    private static let bodyweightNeedles = [
        "plank", "push-up", "push up", "pushup", "pull-up", "pull up", "pullup",
        "sit-up", "sit up", "situp", "crunch", "mountain climber", "jumping jack",
        "air squat", "hollow", "dead bug", "bird dog", "glute bridge", "wall sit",
        "jump rope", "skipping", "bear crawl", "inchworm", "v-up", "toes to bar",
        "hanging leg raise", "flutter kick", "russian twist", "superman"
    ]

    private static let liftNeedles = [
        "barbell", "dumbbell", "kettlebell", "cable", "machine press", "smith",
        "squat", "deadlift", "press", "curl", "lunge", "burpee", "row",
        "fly", "raise", "extension", "pulldown", "thruster", "clean", "snatch",
        "jerk", "hip thrust", "shrug", "calf raise"
    ]

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
