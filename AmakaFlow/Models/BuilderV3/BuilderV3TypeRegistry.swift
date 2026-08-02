//
//  BuilderV3TypeRegistry.swift
//  AmakaFlow
//
//  AMA-2372 — Builder v3: local structure-seed registry for the type picker.
//  No seed API — every seed below is authored client-side and turned into an
//  `EditorV2Session` (Lift / Conditioning / Recover) or a `BuilderV3RunSession`
//  (Run) before the editor ever renders.
//

import Foundation

/// Top-level type-picker sections (product spec 2026-08-02).
enum BuilderV3Category: String, CaseIterable, Equatable, Sendable {
    case lift
    case conditioning
    case run
    case recover

    var label: String {
        switch self {
        case .lift: return "Lift"
        case .conditioning: return "Conditioning"
        case .run: return "Run"
        case .recover: return "Recover"
        }
    }
}

/// Push/Pull/Legs/Full body starter splits — fixed starter exercise names (spec).
enum BuilderV3SplitStarter: String, CaseIterable, Equatable, Sendable {
    case push
    case pull
    case legs
    case fullBody

    var label: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .fullBody: return "Full body"
        }
    }

    /// Fixed starter names — deterministic, no seed API.
    var starterExerciseNames: [String] {
        switch self {
        case .push: return ["Bench Press", "Overhead Press", "Triceps Pushdown"]
        case .pull: return ["Deadlift", "Barbell Row", "Lat Pulldown"]
        case .legs: return ["Back Squat", "Romanian Deadlift", "Leg Press"]
        case .fullBody: return ["Squat", "Bench Press", "Barbell Row"]
        }
    }
}

/// How a Lift/Conditioning/Recover seed turns into `EditorV2Session` state.
enum BuilderV3StructureKind: Equatable, Sendable {
    case straightSets
    case superset
    case format(EditorV2GroupType)
    case splitStarter(BuilderV3SplitStarter)
    /// Plain duration-style rows (not run holds) — e.g. mobility stretches.
    case mobility
    case blank
}

struct BuilderV3TypeSeed: Identifiable, Equatable, Sendable {
    var id: String
    var category: BuilderV3Category
    var label: String
    var subtitle: String
    var structureKind: BuilderV3StructureKind

    /// `builder_v3_type_<id>` accessibility identifier for the picker tile.
    var accessibilityId: String { "builder_v3_type_\(id)" }
}

/// Local structure-seed registry — the single source of truth for the Builder v3
/// type picker. Intentionally has no network dependency: every seed is authored
/// here and materialized into editor state on selection.
enum BuilderV3TypeRegistry {
    // MARK: - Lift

    static let straightSets = BuilderV3TypeSeed(
        id: "lift_straight_sets",
        category: .lift,
        label: "Straight sets",
        subtitle: "One move at a time · sets × reps",
        structureKind: .straightSets
    )
    static let superset = BuilderV3TypeSeed(
        id: "lift_superset",
        category: .lift,
        label: "Superset",
        subtitle: "Pair two moves back to back",
        structureKind: .superset
    )
    static let push = BuilderV3TypeSeed(
        id: "lift_push",
        category: .lift,
        label: "Push",
        subtitle: "Chest · shoulders · triceps",
        structureKind: .splitStarter(.push)
    )
    static let pull = BuilderV3TypeSeed(
        id: "lift_pull",
        category: .lift,
        label: "Pull",
        subtitle: "Back · biceps",
        structureKind: .splitStarter(.pull)
    )
    static let legs = BuilderV3TypeSeed(
        id: "lift_legs",
        category: .lift,
        label: "Legs",
        subtitle: "Quads · hamstrings · glutes",
        structureKind: .splitStarter(.legs)
    )
    static let fullBody = BuilderV3TypeSeed(
        id: "lift_full_body",
        category: .lift,
        label: "Full body",
        subtitle: "One lift per major pattern",
        structureKind: .splitStarter(.fullBody)
    )

    // MARK: - Conditioning

    static let emom = BuilderV3TypeSeed(
        id: "conditioning_emom",
        category: .conditioning,
        label: "EMOM",
        subtitle: "Every minute on the minute",
        structureKind: .format(.emom)
    )
    static let amrap = BuilderV3TypeSeed(
        id: "conditioning_amrap",
        category: .conditioning,
        label: "AMRAP",
        subtitle: "As many rounds as possible",
        structureKind: .format(.amrap)
    )
    static let tabata = BuilderV3TypeSeed(
        id: "conditioning_tabata",
        category: .conditioning,
        label: "Tabata",
        subtitle: "20s on · 10s off",
        structureKind: .format(.tabata)
    )
    static let forTime = BuilderV3TypeSeed(
        id: "conditioning_for_time",
        category: .conditioning,
        label: "For time",
        subtitle: "Finish the work as fast as possible",
        structureKind: .format(.fortime)
    )
    static let circuit = BuilderV3TypeSeed(
        id: "conditioning_circuit",
        category: .conditioning,
        label: "Circuit",
        subtitle: "Fixed rounds of the same moves",
        structureKind: .format(.circuit)
    )

    // MARK: - Run

    static let intervals = BuilderV3TypeSeed(
        id: "run_intervals",
        category: .run,
        label: "Intervals",
        subtitle: "Repeated work + recovery",
        structureKind: .blank
    )
    static let tempo = BuilderV3TypeSeed(
        id: "run_tempo",
        category: .run,
        label: "Tempo",
        subtitle: "Sustained effort, comfortably hard",
        structureKind: .blank
    )
    static let longRun = BuilderV3TypeSeed(
        id: "run_long_run",
        category: .run,
        label: "Long run",
        subtitle: "Easy, continuous distance",
        structureKind: .blank
    )
    static let racePace = BuilderV3TypeSeed(
        id: "run_race_pace",
        category: .run,
        label: "Race pace",
        subtitle: "Reps at target race effort",
        structureKind: .blank
    )

    // MARK: - Recover

    static let mobility = BuilderV3TypeSeed(
        id: "recover_mobility",
        category: .recover,
        label: "Mobility",
        subtitle: "Stretches and prep work",
        structureKind: .mobility
    )
    static let blank = BuilderV3TypeSeed(
        id: "recover_blank",
        category: .recover,
        label: "Blank",
        subtitle: "Start with nothing pinned",
        structureKind: .blank
    )

    static let lift: [BuilderV3TypeSeed] = [straightSets, superset, push, pull, legs, fullBody]
    static let conditioning: [BuilderV3TypeSeed] = [emom, amrap, tabata, forTime, circuit]
    static let run: [BuilderV3TypeSeed] = [intervals, tempo, longRun, racePace]
    static let recover: [BuilderV3TypeSeed] = [mobility, blank]

    static let all: [BuilderV3TypeSeed] = lift + conditioning + run + recover

    static func seeds(for category: BuilderV3Category) -> [BuilderV3TypeSeed] {
        switch category {
        case .lift: return lift
        case .conditioning: return conditioning
        case .run: return run
        case .recover: return recover
        }
    }

    /// Run seeds materialize as a `BuilderV3RunSession`, never `EditorV2Session`.
    static func isRunSeed(_ seed: BuilderV3TypeSeed) -> Bool {
        seed.category == .run
    }

    /// Mobility stretch names — plain duration-style rows (spec: "not run holds").
    static let mobilityExerciseNames = ["Hip flexor stretch", "Thoracic rotations", "Ankle mobility"]
    static let mobilityDurationSeconds = 30

    /// Build the `EditorV2Session` for a Lift / Conditioning / Recover seed.
    /// Never called for `.run` seeds — use `BuilderV3RunRegistry` instead.
    static func makeEditorSession(for seed: BuilderV3TypeSeed) -> EditorV2Session {
        var session = EditorV2Session()
        switch seed.structureKind {
        case .straightSets, .blank:
            break
        case .superset:
            _ = session.startFormat(.superset)
        case .format(let type):
            _ = session.startFormat(type)
        case .splitStarter(let starter):
            for name in starter.starterExerciseNames {
                _ = session.addExercise(named: name)
            }
        case .mobility:
            for name in mobilityExerciseNames {
                session.exercises.append(
                    EditorV2Exercise(name: name, durationSeconds: mobilityDurationSeconds)
                )
            }
        }
        return session
    }
}
