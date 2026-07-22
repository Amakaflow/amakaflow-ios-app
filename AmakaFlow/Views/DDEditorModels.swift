//
//  DDEditorModels.swift
//  AmakaFlow
//
//  Daily Driver editor drafts + seed (shared by legacy backfill + Editor v2).
//

import SwiftUI

enum DDEditorMode: Equatable {
    case edit
    case new
    case importReview
    case backfill
}

// MARK: - Block structure kinds (DD_STRUCTURES)

enum DDEditorStructureKind: String, CaseIterable, Identifiable {
    case circuit
    case emom
    case amrap
    case tabata
    case forTime = "for-time"
    case sets
    case superset
    case rounds
    case warmup
    case cooldown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .circuit: return "Circuit"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .tabata: return "Tabata"
        case .forTime: return "For Time"
        case .sets: return "Sets"
        case .superset: return "Superset"
        case .rounds: return "Rounds"
        case .warmup: return "Warm-up"
        case .cooldown: return "Cool-down"
        }
    }

    var emoji: String {
        switch self {
        case .circuit, .rounds: return "🟢"
        case .emom: return "🔵"
        case .amrap: return "🟠"
        case .tabata: return "🔴"
        case .forTime: return "🟣"
        case .sets: return "⚫"
        case .superset: return "🟡"
        case .warmup, .cooldown: return "⬜"
        }
    }

    var accentColor: Color {
        switch self {
        case .circuit, .rounds: return Color(hex: "4AD97F")
        case .emom: return DailyDriver.blue
        case .amrap: return DailyDriver.orange
        case .tabata: return DailyDriver.red
        case .forTime: return DailyDriver.purple
        case .sets: return Color.white.opacity(0.35)
        case .superset: return DailyDriver.amber
        case .warmup, .cooldown: return Color(hex: "8890A0")
        }
    }

    static func from(blockStructure: BlockStructure) -> DDEditorStructureKind {
        switch blockStructure {
        case .circuit: return .circuit
        case .emom: return .emom
        case .amrap: return .amrap
        case .tabata: return .tabata
        case .superset: return .superset
        case .straight: return .sets
        }
    }
}

// MARK: - Draft models

struct DDEditorExerciseDraft: Identifiable, Equatable {
    let id: String
    var name: String
    var sets: Int?
    var reps: Int?
    var durationSeconds: Int?
    var distanceMeters: Int?
    var weightKg: Double?
    var calories: Int?
    var restSeconds: Int?
    var showsLastTime: Bool
    var swapMessage: String?
    var swapReplacementName: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        sets: Int? = 3,
        reps: Int? = 10,
        durationSeconds: Int? = nil,
        distanceMeters: Int? = nil,
        weightKg: Double? = nil,
        calories: Int? = nil,
        restSeconds: Int? = 60,
        showsLastTime: Bool = false,
        swapMessage: String? = nil,
        swapReplacementName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.weightKg = weightKg
        self.calories = calories
        self.restSeconds = restSeconds
        self.showsLastTime = showsLastTime
        self.swapMessage = swapMessage
        self.swapReplacementName = swapReplacementName
    }

    var summaryLine: String {
        var parts: [String] = []
        if let sets { parts.append("\(sets) SETS") }
        if let reps { parts.append("\(reps) REPS") }
        if let durationSeconds {
            parts.append(durationSeconds >= 60 ? "\(durationSeconds / 60) MIN" : "\(durationSeconds)S")
        }
        if let distanceMeters { parts.append("\(distanceMeters) M") }
        if let calories { parts.append("\(calories) CAL") }
        if let weightKg {
            let text = weightKg.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(weightKg))
                : String(format: "%.1f", weightKg)
            parts.append("\(text) KG")
        }
        if let restSeconds { parts.append("REST \(restSeconds)S") }
        var line = parts.joined(separator: " · ")
        if showsLastTime { line += " · LAST TIME" }
        return line
    }
}

struct DDEditorBlockDraft: Identifiable, Equatable {
    let id: String
    var structure: DDEditorStructureKind
    var label: String
    var rounds: Int
    var restBetweenRoundsSeconds: Int
    var timeCapSeconds: Int?
    var isOpen: Bool
    var exercises: [DDEditorExerciseDraft]

    init(
        id: String = UUID().uuidString,
        structure: DDEditorStructureKind,
        label: String,
        rounds: Int = 1,
        restBetweenRoundsSeconds: Int = 60,
        timeCapSeconds: Int? = nil,
        isOpen: Bool = true,
        exercises: [DDEditorExerciseDraft] = []
    ) {
        self.id = id
        self.structure = structure
        self.label = label
        self.rounds = rounds
        self.restBetweenRoundsSeconds = restBetweenRoundsSeconds
        self.timeCapSeconds = timeCapSeconds
        self.isOpen = isOpen
        self.exercises = exercises
    }

    var metaLine: String {
        let count = exercises.count
        let exercisePart = "\(count) EXERCISE\(count == 1 ? "" : "S")"
        if structure == .amrap || structure == .forTime {
            let cap = DDEditorFormatting.duration(timeCapSeconds ?? 600)
            return "\(exercisePart) · CAP \(cap.uppercased())"
        }
        if structure == .sets {
            return "\(exercisePart) · \(rounds) SETS · \(DDEditorFormatting.duration(restBetweenRoundsSeconds).uppercased()) REST"
        }
        if rounds > 1 {
            let rest = DDEditorFormatting.duration(restBetweenRoundsSeconds)
            return "\(exercisePart) · \(rounds) ROUNDS · \(rest.uppercased()) REST/ROUND"
        }
        return exercisePart
    }
}

enum DDEditorFormatting {
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 { return "\(minutes) min" }
        return "\(minutes)m \(remainder)s"
    }
}

enum DDEditorSeed {
    static func initialState(mode: DDEditorMode, workout: Workout?) -> (title: String, blocks: [DDEditorBlockDraft]) {
        switch mode {
        case .new:
            return ("", [])
        case .backfill:
            return (
                "Lower body — posterior",
                [
                    DDEditorBlockDraft(
                        structure: .sets,
                        label: "Main lifts",
                        rounds: 3,
                        restBetweenRoundsSeconds: 120,
                        exercises: [
                            DDEditorExerciseDraft(name: "Back squat", sets: 3, reps: 5, weightKg: 85, restSeconds: 120, showsLastTime: true),
                            DDEditorExerciseDraft(name: "Romanian deadlift", sets: 3, reps: 8, weightKg: 70, restSeconds: 120, showsLastTime: true),
                            DDEditorExerciseDraft(name: "Split squat", sets: 2, reps: 10, weightKg: 20, restSeconds: 60, showsLastTime: true)
                        ]
                    )
                ]
            )
        case .importReview:
            return (
                "DB Full-body AMRAP",
                [
                    DDEditorBlockDraft(
                        structure: .amrap,
                        label: "AMRAP",
                        timeCapSeconds: 600,
                        exercises: [
                            DDEditorExerciseDraft(name: "Wall balls", sets: nil, reps: 20, restSeconds: nil),
                            DDEditorExerciseDraft(
                                name: "Barbell thrusters",
                                sets: nil,
                                reps: 12,
                                weightKg: 40,
                                restSeconds: nil,
                                swapMessage: "No barbell — swap to DB thrusters 2×16?",
                                swapReplacementName: "DB thrusters"
                            ),
                            DDEditorExerciseDraft(name: "Burpee broad jumps", sets: nil, reps: 10, restSeconds: nil)
                        ]
                    ),
                    DDEditorBlockDraft(
                        structure: .forTime,
                        label: "Finisher",
                        timeCapSeconds: 240,
                        isOpen: false,
                        exercises: [
                            DDEditorExerciseDraft(
                                name: "Sled push",
                                distanceMeters: 40,
                                swapMessage: "No sled — swap to heavy farmer carry?",
                                swapReplacementName: "Heavy farmer carry"
                            )
                        ]
                    )
                ]
            )
        case .edit:
            if let workout {
                if !workout.blocks.isEmpty {
                    return (workout.name, workout.blocks.map { blockDraft(from: $0) })
                }
                let exercises = workout.intervals.compactMap { interval -> DDEditorExerciseDraft? in
                    guard case .reps(let sets, let reps, let name, let load, let restSec, _) = interval else { return nil }
                    return DDEditorExerciseDraft(
                        name: name,
                        sets: sets,
                        reps: reps,
                        weightKg: Self.parseLoad(load),
                        restSeconds: restSec
                    )
                }
                if exercises.isEmpty {
                    return (workout.name, Self.hyroxDefaultBlocks())
                }
                return (
                    workout.name,
                    [DDEditorBlockDraft(structure: .sets, label: "Main block", exercises: exercises)]
                )
            }
            return ("Hyrox Sim — Stations 1–4", Self.hyroxDefaultBlocks())
        }
    }

    static func hyroxDefaultBlocks() -> [DDEditorBlockDraft] {
        [
            DDEditorBlockDraft(
                structure: .circuit,
                label: "Stations 1–4",
                rounds: 2,
                restBetweenRoundsSeconds: 90,
                exercises: [
                    DDEditorExerciseDraft(name: "SkiErg", distanceMeters: 250, restSeconds: 30),
                    DDEditorExerciseDraft(name: "Sled push", distanceMeters: 40, weightKg: 80, restSeconds: 30),
                    DDEditorExerciseDraft(name: "Burpee broad jumps", sets: nil, reps: 10, restSeconds: 30),
                    DDEditorExerciseDraft(name: "Rower", distanceMeters: 500, restSeconds: 60)
                ]
            ),
            DDEditorBlockDraft(
                structure: .rounds,
                label: "Run intervals",
                rounds: 4,
                restBetweenRoundsSeconds: 60,
                isOpen: false,
                exercises: [
                    DDEditorExerciseDraft(name: "Run", distanceMeters: 400)
                ]
            )
        ]
    }

    private static func blockDraft(from block: Block) -> DDEditorBlockDraft {
        DDEditorBlockDraft(
            structure: DDEditorStructureKind.from(blockStructure: block.structure),
            label: block.label ?? block.structure.displayName,
            rounds: block.rounds,
            restBetweenRoundsSeconds: block.restBetweenSeconds ?? 60,
            exercises: block.exercises.map { exercise in
                DDEditorExerciseDraft(
                    name: exercise.name,
                    sets: exercise.sets,
                    reps: Int(exercise.reps ?? ""),
                    durationSeconds: exercise.durationSeconds,
                    distanceMeters: exercise.distance.map { Int($0) },
                    weightKg: exercise.load?.value,
                    restSeconds: exercise.restSeconds
                )
            }
        )
    }

    private static func parseLoad(_ load: String?) -> Double? {
        guard let load else { return nil }
        let trimmed = load.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(
            of: #"^(\d+(?:\.\d+)?)"#,
            options: .regularExpression
        ) else { return nil }
        return Double(trimmed[match])
    }
}
