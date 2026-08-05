//
//  WorkoutEnrichmentV2Models.swift
//  AmakaFlow
//
//  AMA-2378 — soft ActivityGoal + per-exercise RampSet / PerExerciseRamp
//  (split from WorkoutEnrichmentModels.swift for SwiftLint file_length).
//

import Foundation

/// Soft-goal kind for a session warm-up / cooldown activity (AMA-2378).
/// `open` → lap at delivery; the other three carry a `value` (sec / meters / kcal).
enum ActivityGoalKind: String, Codable, CaseIterable, Equatable, Sendable {
    case time, distance, cals, open
}

/// Declared intent for a soft activity — sibling of `duration_sec`, richer than
/// the time-only shape it grew from. Mirrors backend `ActivityGoal` exactly:
/// `open` must carry no `value`; every other kind requires one.
struct ActivityGoal: Equatable, Codable, Sendable {
    private(set) var kind: ActivityGoalKind
    private(set) var value: Int?

    enum CodingKeys: String, CodingKey {
        case kind, value
    }

    init(kind: ActivityGoalKind, value: Int?) throws {
        self.kind = kind
        self.value = try WorkoutEnrichmentMutations.validatedActivityGoal(kind: kind, value: value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ActivityGoalKind.self, forKey: .kind)
        let value = try container.decodeIfPresent(Int.self, forKey: .value)
        try self.init(kind: kind, value: value)
    }
}

/// Ramp-set kind for a declared per-exercise warm-up set (AMA-2378).
/// `open` → lap at delivery; the other three carry a `value` (reps / sec / kcal).
enum WarmupSetKind: String, Codable, CaseIterable, Equatable, Sendable {
    case reps, time, cals, open
}

/// One prescribed set inside a `PerExerciseRamp` (backend `RampSet`).
/// `open` must carry no `value`; every other kind requires one.
/// `id` is UI-only (stable ForEach identity) and never encoded.
struct RampSet: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    private(set) var kind: WarmupSetKind
    private(set) var value: Int?
    var intensityNote: String?

    enum CodingKeys: String, CodingKey {
        case kind, value
        case intensityNote = "intensity_note"
    }

    init(kind: WarmupSetKind, value: Int?, intensityNote: String? = nil, id: UUID = UUID()) throws {
        self.id = id
        self.kind = kind
        self.value = try WorkoutEnrichmentMutations.validatedRampSet(kind: kind, value: value)
        self.intensityNote = intensityNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(WarmupSetKind.self, forKey: .kind)
        let value = try container.decodeIfPresent(Int.self, forKey: .value)
        let intensityNote = try container.decodeIfPresent(String.self, forKey: .intensityNote)
        try self.init(kind: kind, value: value, intensityNote: intensityNote)
    }

    static func == (lhs: RampSet, rhs: RampSet) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.intensityNote == rhs.intensityNote
    }
}

/// Declared per-exercise ramp override (backend `PerExerciseRamp`). Matched by
/// `exercise_ref` (id or normalized name) at enrich time — server-side, not here.
/// `id` is UI-only (stable ForEach identity) and never encoded.
struct PerExerciseRamp: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var exerciseRef: String
    var enabled: Bool
    var sets: [RampSet]

    enum CodingKeys: String, CodingKey {
        case exerciseRef = "exercise_ref"
        case enabled, sets
    }

    init(exerciseRef: String, enabled: Bool = true, sets: [RampSet] = [], id: UUID = UUID()) {
        self.id = id
        self.exerciseRef = exerciseRef
        self.enabled = enabled
        self.sets = sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        exerciseRef = try container.decode(String.self, forKey: .exerciseRef)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        sets = try container.decodeIfPresent([RampSet].self, forKey: .sets) ?? []
    }

    static func == (lhs: PerExerciseRamp, rhs: PerExerciseRamp) -> Bool {
        lhs.exerciseRef == rhs.exerciseRef && lhs.enabled == rhs.enabled && lhs.sets == rhs.sets
    }
}
