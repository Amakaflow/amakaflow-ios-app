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

    /// AMA-2393 C3 — type picker choice → persisted app sport.
    var workoutSport: WorkoutSport {
        switch self {
        case .lift: return .strength
        case .conditioning: return .conditioning
        case .run: return .running
        case .recover: return .mobility
        }
    }

    /// Section accent (mockup: green Lift · orange Conditioning · blue Run).
    var accentHex: String {
        switch self {
        case .lift: return "7AB953"
        case .conditioning: return "F4A24A"
        case .run: return "5AB8F4"
        case .recover: return "A0A0A0"
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
    /// SF Symbol on the type-picker tile (mockup icons).
    var systemImage: String
    /// Pre-filled canvas title; `nil` keeps the "Name your workout" placeholder.
    var defaultTitle: String?

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
        subtitle: "Pick moves · 3×10 default",
        structureKind: .straightSets,
        systemImage: "dumbbell.fill"
    )
    static let superset = BuilderV3TypeSeed(
        id: "lift_superset",
        category: .lift,
        label: "Supersets",
        subtitle: "Pairs, back to back",
        structureKind: .superset,
        systemImage: "arrow.triangle.2.circlepath",
        defaultTitle: "Supersets"
    )
    /// Same underlying group type as supersets — three (or more) moves cycled
    /// with rest after the last. Pairing a third exercise into a pair upgrades
    /// the group label to Tri-set automatically.
    static let triset = BuilderV3TypeSeed(
        id: "lift_triset",
        category: .lift,
        label: "Tri-sets",
        subtitle: "Three moves, back to back",
        structureKind: .superset,
        systemImage: "circle.grid.3x3.fill",
        defaultTitle: "Tri-sets"
    )
    static let push = BuilderV3TypeSeed(
        id: "lift_push",
        category: .lift,
        label: "Push day",
        subtitle: "Chest · shoulders · tris",
        structureKind: .splitStarter(.push),
        systemImage: "dumbbell.fill",
        defaultTitle: "Push day"
    )
    static let pull = BuilderV3TypeSeed(
        id: "lift_pull",
        category: .lift,
        label: "Pull day",
        subtitle: "Back · biceps",
        structureKind: .splitStarter(.pull),
        systemImage: "dumbbell.fill",
        defaultTitle: "Pull day"
    )
    static let legs = BuilderV3TypeSeed(
        id: "lift_legs",
        category: .lift,
        label: "Leg day",
        subtitle: "Quads · glutes · hams",
        structureKind: .splitStarter(.legs),
        systemImage: "figure.strengthtraining.traditional",
        defaultTitle: "Leg day"
    )
    static let fullBody = BuilderV3TypeSeed(
        id: "lift_full_body",
        category: .lift,
        label: "Full body",
        subtitle: "One of everything",
        structureKind: .splitStarter(.fullBody),
        systemImage: "figure.stand",
        defaultTitle: "Full body"
    )

    // MARK: - Conditioning

    static let emom = BuilderV3TypeSeed(
        id: "conditioning_emom",
        category: .conditioning,
        label: "EMOM",
        subtitle: "Every minute on the minute",
        structureKind: .format(.emom),
        systemImage: "clock.fill",
        defaultTitle: "Engine EMOM"
    )
    static let amrap = BuilderV3TypeSeed(
        id: "conditioning_amrap",
        category: .conditioning,
        label: "AMRAP",
        subtitle: "Max rounds in a time cap",
        structureKind: .format(.amrap),
        systemImage: "bolt.fill",
        defaultTitle: "AMRAP"
    )
    static let tabata = BuilderV3TypeSeed(
        id: "conditioning_tabata",
        category: .conditioning,
        label: "Tabata",
        subtitle: "20s on · 10s off ×8",
        structureKind: .format(.tabata),
        systemImage: "hourglass",
        defaultTitle: "Tabata"
    )
    static let forTime = BuilderV3TypeSeed(
        id: "conditioning_for_time",
        category: .conditioning,
        label: "For time",
        subtitle: "Fixed work, race the clock",
        structureKind: .format(.fortime),
        systemImage: "trophy.fill",
        defaultTitle: "For time"
    )
    static let circuit = BuilderV3TypeSeed(
        id: "conditioning_circuit",
        category: .conditioning,
        label: "Circuit",
        subtitle: "Fixed rounds of the same moves",
        structureKind: .format(.circuit),
        systemImage: "circle.grid.cross.fill",
        defaultTitle: "Circuit"
    )

    // MARK: - Run

    static let intervals = BuilderV3TypeSeed(
        id: "run_intervals",
        category: .run,
        label: "Intervals",
        subtitle: "Repeated work + recovery",
        structureKind: .blank,
        systemImage: "figure.run",
        defaultTitle: "Interval repeats"
    )
    static let tempo = BuilderV3TypeSeed(
        id: "run_tempo",
        category: .run,
        label: "Tempo",
        subtitle: "Sustained effort, comfortably hard",
        structureKind: .blank,
        systemImage: "figure.run",
        defaultTitle: "Tempo"
    )
    static let longRun = BuilderV3TypeSeed(
        id: "run_long_run",
        category: .run,
        label: "Long run",
        subtitle: "Easy, continuous distance",
        structureKind: .blank,
        systemImage: "figure.run",
        defaultTitle: "Long run"
    )
    static let racePace = BuilderV3TypeSeed(
        id: "run_race_pace",
        category: .run,
        label: "Race pace",
        subtitle: "Reps at target race effort",
        structureKind: .blank,
        systemImage: "flag.checkered",
        defaultTitle: "Race pace"
    )

    // MARK: - Recover

    static let mobility = BuilderV3TypeSeed(
        id: "recover_mobility",
        category: .recover,
        label: "Mobility",
        subtitle: "Stretches and prep work",
        structureKind: .mobility,
        systemImage: "figure.cooldown",
        defaultTitle: "Mobility"
    )
    static let blank = BuilderV3TypeSeed(
        id: "recover_blank",
        category: .recover,
        label: "Blank",
        subtitle: "Start with nothing pinned",
        structureKind: .blank,
        systemImage: "square.dashed"
    )

    static let lift: [BuilderV3TypeSeed] = [straightSets, superset, triset, push, pull, legs, fullBody]
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
        if let defaultTitle = seed.defaultTitle {
            session.title = defaultTitle
        }
        switch seed.structureKind {
        case .straightSets, .blank:
            break
        case .superset:
            _ = session.startFormat(.superset)
            if seed.id == "lift_triset" {
                session.updateGroup("fmt") { $0.name = "Tri-set" }
            }
        case .format(let type):
            _ = session.startFormat(type)
        case .splitStarter(let starter):
            for name in starter.starterExerciseNames {
                _ = session.addExercise(named: name)
            }
        case .mobility:
            for name in mobilityExerciseNames {
                let exercise = EditorV2Exercise(name: name, durationSeconds: mobilityDurationSeconds)
                session.exercises[exercise.id] = exercise
                session.order.append(.loose(exercise.id))
            }
        }
        return session
    }
}
