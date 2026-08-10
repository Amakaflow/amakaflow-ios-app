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
    case timedCircuit
    case emom
    case amrap
    case tabata
    case fortime
    case warmup
    case cooldown

    /// Optional create chips — never a gate before the first exercise.
    static let formatChips: [EditorV2GroupType] = [.emom, .amrap, .tabata, .fortime, .circuit]

    /// "Runs as" switcher (warmup / cooldown excluded — soft sections).
    static let runsAsOptions: [EditorV2GroupType] = [.superset] + formatChips

    /// Soft sections carry enrichment intent, not a pacing format (AMA-2336).
    var isSoftSection: Bool {
        self == .warmup || self == .cooldown
    }

    var label: String {
        switch self {
        case .superset: return "Superset"
        case .circuit: return "Circuit"
        case .timedCircuit: return "Timed circuit"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .tabata: return "Tabata"
        case .fortime: return "For time"
        case .warmup: return "Warm-up"
        case .cooldown: return "Cool-down"
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
        case .timedCircuit: return .timedCircuit
        case .emom: return .emom
        case .amrap: return .amrap
        case .tabata: return .tabata
        case .fortime: return .forTime
        case .warmup: return .warmup
        case .cooldown: return .cooldown
        }
    }

    var structureBlockType: StructureBlockType {
        switch self {
        case .superset: return .superset
        case .circuit: return .circuit
        case .timedCircuit: return .timedCircuit
        case .emom: return .emom
        case .amrap: return .amrap
        case .tabata: return .tabata
        case .fortime: return .forTime
        case .warmup: return .warmup
        case .cooldown: return .cooldown
        }
    }

    /// Default config when pinning / switching type (E2_TYPES.d).
    var defaultConfig: EditorV2GroupConfig {
        switch self {
        case .superset: return EditorV2GroupConfig(rounds: 3, restSeconds: 60)
        case .circuit: return EditorV2GroupConfig(rounds: 4)
        case .timedCircuit: return EditorV2GroupConfig(rounds: 1)
        case .emom: return EditorV2GroupConfig(rounds: 10)
        case .amrap: return EditorV2GroupConfig(capMinutes: 10)
        case .tabata: return EditorV2GroupConfig(rounds: 8, restSeconds: 10, workSeconds: 20)
        case .fortime: return EditorV2GroupConfig(capMinutes: 20)
        case .warmup: return EditorV2GroupConfig(rounds: 2)
        case .cooldown: return EditorV2GroupConfig(rounds: 1)
        }
    }

    static func from(dd kind: DDEditorStructureKind) -> EditorV2GroupType? {
        switch kind {
        case .superset: return .superset
        case .circuit, .rounds: return .circuit
        case .timedCircuit: return .timedCircuit
        case .emom: return .emom
        case .amrap: return .amrap
        case .tabata: return .tabata
        case .forTime: return .fortime
        case .warmup: return .warmup
        case .cooldown: return .cooldown
        case .sets: return nil
        }
    }

    /// Map ADR-017 clarify block types onto Editor v2 defaults (AMA-2326 chips).
    static func from(structureBlock type: StructureBlockType) -> EditorV2GroupType? {
        switch type.canonical {
        case .superset: return .superset
        case .circuit, .rounds: return .circuit
        case .timedCircuit: return .timedCircuit
        case .emom: return .emom
        case .amrap: return .amrap
        case .tabata: return .tabata
        case .forTime, .fortime: return .fortime
        case .warmup: return .warmup
        case .cooldown: return .cooldown
        case .sets, .regular, .unknown: return nil
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
    /// AMA-2336 — set only on soft sections this app added (`session_warmup` / `cooldown`).
    /// Never the presence test — that stays block `type`.
    var enrichmentKind: EnrichmentKind?

    init(
        id: String = UUID().uuidString,
        type: EditorV2GroupType,
        name: String? = nil,
        config: EditorV2GroupConfig? = nil,
        structureSource: StructureSource = .userConfirmed,
        enrichmentKind: EnrichmentKind? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name ?? type.label
        self.config = config ?? type.defaultConfig
        self.structureSource = structureSource
        self.enrichmentKind = enrichmentKind
    }

    var metaLine: String {
        switch type {
        case .warmup: return "\(config.rounds ?? 2) ROUNDS · EASY"
        case .cooldown: return "\(config.rounds ?? 1) ROUNDS · EASY"
        case .circuit: return "\(config.rounds ?? 4) ROUNDS · FOR TIME"
        case .timedCircuit: return "\(config.rounds ?? 1) ROUNDS · FOR TIME"
        case .emom: return "\(config.rounds ?? 10) MIN · EVERY MINUTE"
        case .amrap: return "\(config.capMinutes ?? 10) MIN CAP · MAX ROUNDS"
        case .tabata:
            let work = config.workSeconds ?? 20
            let rest = config.restSeconds ?? 10
            return "\(work)S ON · \(rest)S OFF · ×\(config.rounds ?? 8)"
        case .fortime: return "FOR TIME · \(config.capMinutes ?? 20) MIN CAP"
        case .superset:
            return "\(config.rounds ?? 3) ROUNDS · \(Self.restMetaText(config.restSeconds ?? 60)) REST"
        }
    }

    /// Rest labels: keep exact seconds when not a whole minute (90s ≠ “1 MIN”).
    static func restMetaText(_ rest: Int) -> String {
        if rest >= 60, rest % 60 == 0 {
            return "\(rest / 60) MIN"
        }
        return "\(rest)S"
    }

    /// Steppers for the group config sheet — only fields this type needs.
    var stepperRows: [EditorV2StepperSpec] {
        switch type {
        case .emom:
            return [EditorV2StepperSpec(label: "Minutes", key: .rounds, min: 1, max: 60, step: 1)]
        case .amrap, .fortime:
            // 5-min steps — ±1 was too slow for common 10–60 min caps.
            return [EditorV2StepperSpec(label: "Cap min", key: .capMinutes, min: 5, max: 90, step: 5)]
        case .tabata:
            return [
                EditorV2StepperSpec(label: "Work s", key: .workSeconds, min: 5, max: 120, step: 5),
                EditorV2StepperSpec(label: "Rest s", key: .restSeconds, min: 0, max: 120, step: 5),
                EditorV2StepperSpec(label: "Rounds", key: .rounds, min: 1, max: 20, step: 1)
            ]
        case .circuit, .timedCircuit, .warmup, .cooldown:
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
    var repsRange: RepsRange?
    var durationSeconds: Int?
    var distanceMeters: Int?
    var weightKg: Double?
    /// Explicit bodyweight load (shows in summary / exports as `bodyweight`).
    /// Mutually exclusive with a weighted `weightKg` prescription.
    var isBodyweight: Bool
    var restSeconds: Int?
    var calories: Int?
    /// An intentionally unbounded target. Enabling it clears all metric targets.
    var openGoal: Bool {
        didSet {
            if openGoal {
                clearGoalTargets()
            }
        }
    }
    var groupKey: String?
    var swapMessage: String?
    var swapReplacementName: String?
    /// AMA-2312 — mirrors backend `field_provenance` (`explicit` / `inferred` / `user` /
    /// `enrichment_default`).
    var fieldProvenance: [String: ProvSource]
    /// AMA-2336 — stable within-workout identity (`wex_…`), minted at save.
    var exerciseId: String?
    /// AMA-2336 — declared sibling rows; `sets: Int` shape is unchanged.
    var warmupSets: [WarmupSetRow]
    /// AMA-2336 — open rest intent → lap at delivery (`restSeconds` must be nil).
    var restOpen: Bool?
    /// AMA-2336 — row provenance for soft-section activity rows (nil on work rows).
    var structureSource: StructureSource?

    init(
        id: String = UUID().uuidString,
        name: String,
        sets: Int? = nil,
        reps: Int? = nil,
        repsRange: RepsRange? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Int? = nil,
        weightKg: Double? = nil,
        isBodyweight: Bool = false,
        restSeconds: Int? = nil,
        calories: Int? = nil,
        openGoal: Bool = false,
        groupKey: String? = nil,
        swapMessage: String? = nil,
        swapReplacementName: String? = nil,
        fieldProvenance: [String: ProvSource] = [:],
        exerciseId: String? = nil,
        warmupSets: [WarmupSetRow] = [],
        restOpen: Bool? = nil,
        structureSource: StructureSource? = nil
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.repsRange = repsRange
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.weightKg = weightKg
        self.isBodyweight = isBodyweight
        self.restSeconds = restSeconds
        self.calories = calories
        self.openGoal = openGoal
        self.groupKey = groupKey
        self.swapMessage = swapMessage
        self.swapReplacementName = swapReplacementName
        self.fieldProvenance = fieldProvenance
        self.exerciseId = exerciseId
        self.warmupSets = warmupSets
        self.restOpen = restOpen
        self.structureSource = structureSource
        if openGoal {
            clearGoalTargets()
        }
    }

    /// Mono summary under the name (screens-editor2.jsx `e2Sum`).
    var summaryLine: String {
        PrescriptionFormatter.line(PrescriptionFormatter.effective(from: self))
    }

    /// Strength / straight-set style: show Sets + Reps even when nil (AMA-2312).
    var showsStrengthPrescriptionEditors: Bool {
        if durationSeconds != nil || distanceMeters != nil || calories != nil {
            return false
        }
        return true
    }

    mutating func stampUser(_ field: String) {
        fieldProvenance[field] = .user
    }

    /// AMA-2336 — editing a soft-section activity row makes that row user-owned,
    /// so untouched siblings still refresh under changed prefs (spec §5 rule a).
    mutating func renameActivity(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        name = trimmed
        structureSource = .userAdded
    }

    /// Editing one warm-up set row flips **that row** to `user_added`.
    mutating func updateWarmupSetReps(at index: Int, reps: Int) {
        guard warmupSets.indices.contains(index), warmupSets[index].reps != reps else { return }
        warmupSets[index].reps = reps
        warmupSets[index].structureSource = .userAdded
    }

    mutating func updateWarmupSetWeight(at index: Int, weight: Double?) {
        guard warmupSets.indices.contains(index), warmupSets[index].weight != weight else { return }
        warmupSets[index].weight = weight
        warmupSets[index].structureSource = .userAdded
    }

    /// Quick-add rest intent from prefs — refreshable while nothing user-owned.
    mutating func applyEnrichmentDefaultRest(restSeconds: Int?, restOpen: Bool) throws {
        let validated = try WorkoutEnrichmentMutations.validatedRest(
            restSec: restSeconds,
            restOpen: restOpen
        )
        self.restSeconds = validated.restSec
        self.restOpen = validated.restOpen
        WorkoutEnrichmentMutations.stampRestEnrichmentDefault(fieldProvenance: &fieldProvenance)
    }

    /// User-edited rest intent — ownership is monotonic, enrichment never overwrites it.
    mutating func setRestIntent(restSeconds: Int?, restOpen: Bool) throws {
        let validated = try WorkoutEnrichmentMutations.validatedRest(
            restSec: restSeconds,
            restOpen: restOpen
        )
        self.restSeconds = validated.restSec
        self.restOpen = validated.restOpen
        WorkoutEnrichmentMutations.stampRestUser(fieldProvenance: &fieldProvenance)
    }

    /// Absent intent is a decision, not a gap — provenance is cleared with the value.
    mutating func clearRestIntent() {
        restSeconds = nil
        restOpen = nil
        fieldProvenance.removeValue(forKey: WorkoutEnrichmentMutations.restSecKey)
        fieldProvenance.removeValue(forKey: WorkoutEnrichmentMutations.restOpenKey)
    }

    /// AMA-2312 — apply range-mode commit only when the parsed range is valid and changed.
    /// Invalid/empty input leaves the existing prescription and provenance untouched.
    mutating func commitRepRange(from rangeText: String, useRangeMode: Bool) {
        guard useRangeMode else { return }
        guard let updated = RepsRange.fromRangeText(
            rangeText,
            preservingQualifier: repsRange?.qualifier
        ) else {
            return
        }
        let changed = repsRange != updated
        repsRange = updated
        reps = nil
        if changed {
            stampUser("reps_range")
        }
    }

    private mutating func clearGoalTargets() {
        reps = nil
        repsRange = nil
        durationSeconds = nil
        distanceMeters = nil
        calories = nil
    }

    static func formatWeight(_ weightKg: Double) -> String {
        weightKg.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(weightKg))
            : String(format: "%.1f", weightKg)
    }

    static func formatWeightLoad(_ weightKg: Double) -> String {
        "\(formatWeight(weightKg)) kg"
    }

    /// Prescription load string for save / social-import export.
    var exportLoadString: String? {
        if isBodyweight { return "bodyweight" }
        return weightKg.map(Self.formatWeightLoad)
    }

    mutating func setBodyweightLoad() {
        isBodyweight = true
        weightKg = nil
        stampUser("load")
    }

    mutating func setWeightedLoad(kilograms: Double) {
        isBodyweight = false
        weightKg = kilograms
        stampUser("load")
        stampUser("weight_kg")
    }

    mutating func clearLoad() {
        isBodyweight = false
        weightKg = nil
        stampUser("load")
    }

    /// Visible tap targets on a calm card: body + ⋯ only.
    static let maxVisibleControlsPerRow = 2
}

extension PrescriptionFormatter {
    static func resolvedPrimaryText(from exercise: EditorV2Exercise) -> String? {
        primaryLine(effective(from: exercise).primary)
    }

    static func resolvedLoadText(from exercise: EditorV2Exercise) -> String? {
        exerciseLoad(from: exercise).flatMap(formattedLoad)
    }

    static func exerciseLoad(from exercise: EditorV2Exercise) -> ExerciseLoad? {
        if exercise.isBodyweight {
            return ExerciseLoad(value: 0, unit: "bodyweight")
        }
        return exercise.weightKg.map { ExerciseLoad(value: $0, unit: "kg") }
    }

    static func effective(from exercise: EditorV2Exercise) -> EffectivePrescription {
        let load = exerciseLoad(from: exercise)
        var secondary = secondaryParts(
            load: load,
            notes: nil,
            restSeconds: exercise.restSeconds,
            rangeQualifier: exercise.repsRange?.qualifier,
            restOpen: exercise.restOpen == true
        )

        let primary: PrescriptionPrimary
        if exercise.openGoal {
            primary = .open(sets: exercise.sets)
        } else {
            primary = resolvePrimaryMetric(
                PrescriptionMetricInputs(
                    durationSeconds: exercise.durationSeconds,
                    distanceMeters: exercise.distanceMeters,
                    calories: exercise.calories,
                    plainReps: exercise.reps,
                    repsRange: exercise.repsRange,
                    sets: exercise.sets
                )
            )
        }

        if case .repsRange(let range, _) = primary, let qualifier = range.qualifier {
            if !secondary.contains(qualifier) {
                secondary.append(qualifier)
            }
        }

        return EffectivePrescription(primary: primary, secondary: secondary)
    }
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
