//
//  EditorV2Models.swift
//  AmakaFlow
//
//  AMA-2307 / ADR-017 — Editor v2 type registry (screens-editor2.jsx E2_TYPES).
//

import SwiftUI

/// Structure group kinds shown in Editor v2 (Hevy calm list).
enum EditorV2GroupType: String, CaseIterable, Equatable, Sendable {
    case superset
    case circuit
    case emom
    case amrap
    case tabata
    case fortime
    case warmup

    /// Optional create chips — never a gate before the first exercise.
    static let formatChips: [EditorV2GroupType] = [.emom, .amrap, .tabata, .fortime, .circuit]

    /// "Runs as" switcher (warmup excluded — soft section).
    static let runsAsOptions: [EditorV2GroupType] = [.superset] + formatChips

    var label: String {
        switch self {
        case .superset: return "Superset"
        case .circuit: return "Circuit"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .tabata: return "Tabata"
        case .fortime: return "For time"
        case .warmup: return "Warm-up"
        }
    }

    /// Shared with clarify (AMA-2305) via `DDEditorStructureKind.accentColor`.
    var accentColor: Color {
        ddStructureKind.accentColor
    }

    var ddStructureKind: DDEditorStructureKind {
        switch self {
        case .superset: return .superset
        case .circuit: return .circuit
        case .emom: return .emom
        case .amrap: return .amrap
        case .tabata: return .tabata
        case .fortime: return .forTime
        case .warmup: return .warmup
        }
    }

    var structureBlockType: StructureBlockType {
        switch self {
        case .superset: return .superset
        case .circuit: return .circuit
        case .emom: return .emom
        case .amrap: return .amrap
        case .tabata: return .tabata
        case .fortime: return .forTime
        case .warmup: return .warmup
        }
    }

    /// Default config when pinning / switching type (E2_TYPES.d).
    var defaultConfig: EditorV2GroupConfig {
        switch self {
        case .superset: return EditorV2GroupConfig(rounds: 3, restSeconds: 60)
        case .circuit: return EditorV2GroupConfig(rounds: 4)
        case .emom: return EditorV2GroupConfig(rounds: 10)
        case .amrap: return EditorV2GroupConfig(capMinutes: 10)
        case .tabata: return EditorV2GroupConfig(rounds: 8, restSeconds: 10, workSeconds: 20)
        case .fortime: return EditorV2GroupConfig(capMinutes: 20)
        case .warmup: return EditorV2GroupConfig(rounds: 2)
        }
    }

    static func from(dd kind: DDEditorStructureKind) -> EditorV2GroupType? {
        switch kind {
        case .superset: return .superset
        case .circuit, .rounds: return .circuit
        case .emom: return .emom
        case .amrap: return .amrap
        case .tabata: return .tabata
        case .forTime: return .fortime
        case .warmup: return .warmup
        case .sets, .cooldown: return nil
        }
    }
}

struct EditorV2GroupConfig: Equatable, Sendable {
    var rounds: Int?
    var restSeconds: Int?
    var capMinutes: Int?
    var workSeconds: Int?

    init(
        rounds: Int? = nil,
        restSeconds: Int? = nil,
        capMinutes: Int? = nil,
        workSeconds: Int? = nil
    ) {
        self.rounds = rounds
        self.restSeconds = restSeconds
        self.capMinutes = capMinutes
        self.workSeconds = workSeconds
    }
}

struct EditorV2Group: Equatable, Identifiable, Sendable {
    var id: String
    var type: EditorV2GroupType
    var name: String
    var config: EditorV2GroupConfig
    var structureSource: StructureSource

    init(
        id: String = UUID().uuidString,
        type: EditorV2GroupType,
        name: String? = nil,
        config: EditorV2GroupConfig? = nil,
        structureSource: StructureSource = .userConfirmed
    ) {
        self.id = id
        self.type = type
        self.name = name ?? type.label
        self.config = config ?? type.defaultConfig
        self.structureSource = structureSource
    }

    var metaLine: String {
        switch type {
        case .warmup:
            return "\(config.rounds ?? 2) ROUNDS · EASY"
        case .circuit:
            return "\(config.rounds ?? 4) ROUNDS · FOR TIME"
        case .emom:
            return "\(config.rounds ?? 10) MIN · EVERY MINUTE"
        case .amrap:
            return "\(config.capMinutes ?? 10) MIN CAP · MAX ROUNDS"
        case .tabata:
            let work = config.workSeconds ?? 20
            let rest = config.restSeconds ?? 10
            let rounds = config.rounds ?? 8
            return "\(work)S ON · \(rest)S OFF · ×\(rounds)"
        case .fortime:
            return "FOR TIME · \(config.capMinutes ?? 20) MIN CAP"
        case .superset:
            let rounds = config.rounds ?? 3
            let rest = config.restSeconds ?? 60
            let restText = rest >= 60 ? "\(rest / 60) MIN" : "\(rest)S"
            return "\(rounds) ROUNDS · \(restText) REST"
        }
    }

    /// Steppers for the group config sheet — only fields this type needs.
    var stepperRows: [EditorV2StepperSpec] {
        switch type {
        case .emom:
            return [EditorV2StepperSpec(label: "Minutes", key: .rounds, min: 1, max: 60, step: 1)]
        case .amrap, .fortime:
            return [EditorV2StepperSpec(label: "Cap min", key: .capMinutes, min: 1, max: 90, step: 1)]
        case .tabata:
            return [
                EditorV2StepperSpec(label: "Work s", key: .workSeconds, min: 5, max: 120, step: 5),
                EditorV2StepperSpec(label: "Rest s", key: .restSeconds, min: 0, max: 120, step: 5),
                EditorV2StepperSpec(label: "Rounds", key: .rounds, min: 1, max: 20, step: 1)
            ]
        case .circuit, .warmup:
            return [EditorV2StepperSpec(label: "Rounds", key: .rounds, min: 1, max: 20, step: 1)]
        case .superset:
            return [
                EditorV2StepperSpec(label: "Rounds", key: .rounds, min: 1, max: 20, step: 1),
                EditorV2StepperSpec(label: "Rest s", key: .restSeconds, min: 0, max: 600, step: 15)
            ]
        }
    }
}

enum EditorV2ConfigKey: String, Equatable, Sendable {
    case rounds
    case restSeconds
    case capMinutes
    case workSeconds
}

struct EditorV2StepperSpec: Equatable, Sendable {
    var label: String
    var key: EditorV2ConfigKey
    var min: Int
    var max: Int
    var step: Int
}

struct EditorV2Exercise: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var sets: Int?
    var reps: Int?
    var distanceMeters: Int?
    var weightKg: Double?
    var restSeconds: Int?
    var groupKey: String?
    var swapMessage: String?
    var swapReplacementName: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        sets: Int? = nil,
        reps: Int? = nil,
        distanceMeters: Int? = nil,
        weightKg: Double? = nil,
        restSeconds: Int? = nil,
        groupKey: String? = nil,
        swapMessage: String? = nil,
        swapReplacementName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.distanceMeters = distanceMeters
        self.weightKg = weightKg
        self.restSeconds = restSeconds
        self.groupKey = groupKey
        self.swapMessage = swapMessage
        self.swapReplacementName = swapReplacementName
    }

    /// Mono summary under the name (screens-editor2.jsx `e2Sum`).
    var summaryLine: String {
        var parts: [String] = []
        if let sets, let reps {
            parts.append("\(sets) × \(reps)")
        } else if let reps {
            parts.append("\(reps) REPS")
        }
        if let distanceMeters { parts.append("\(distanceMeters) M") }
        if let weightKg {
            let text = weightKg.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(weightKg))
                : String(format: "%.1f", weightKg)
            parts.append("\(text) KG")
        }
        if let restSeconds { parts.append("\(restSeconds)S REST") }
        return parts.joined(separator: " · ")
    }

    /// Visible tap targets on a calm card: body + ⋯ only.
    static let maxVisibleControlsPerRow = 2
}

/// Consecutive same-group exercises share one rail (screens-editor2.jsx `runs`).
struct EditorV2Run: Equatable, Identifiable, Sendable {
    var id: String
    var groupKey: String?
    var exercises: [EditorV2Exercise]
}

/// Demo library rows for the add-exercise sheet (equipment-aware).
struct EditorV2LibraryItem: Equatable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var meta: String

    var isMissingEquipment: Bool {
        meta.uppercased().contains("NOT IN")
    }

    static let demo: [EditorV2LibraryItem] = [
        EditorV2LibraryItem(name: "Wall balls", meta: "CONDITIONING · MED BALL ✓"),
        EditorV2LibraryItem(name: "DB thrusters", meta: "FULL BODY · DUMBBELLS ✓"),
        EditorV2LibraryItem(name: "Burpee broad jumps", meta: "BODYWEIGHT ✓"),
        EditorV2LibraryItem(name: "Rower", meta: "MACHINE · ROWER ✓"),
        EditorV2LibraryItem(name: "KB swing", meta: "POSTERIOR · KETTLEBELL ✓"),
        EditorV2LibraryItem(name: "Goblet squat", meta: "QUADS · KETTLEBELL ✓"),
        EditorV2LibraryItem(name: "Barbell back squat", meta: "STRENGTH · BARBELL — NOT IN YOUR GYM")
    ]
}
