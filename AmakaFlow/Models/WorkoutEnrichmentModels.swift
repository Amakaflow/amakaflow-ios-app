//
//  WorkoutEnrichmentModels.swift
//  AmakaFlow
//
//  AMA-2336 — declared enrichment contract (spec 2026-07-27 §§1–2).
//  Source of truth: mapper-api `domain/enrichment.py` + `api/routers/enrichment.py`
//  (AMA-2334). Snake_case CodingKeys mirror the backend payloads exactly — no
//  underscore smuggling, one provenance system.
//  `BetweenSetRestPrefs` / `StationTransitionPrefs` live in
//  WorkoutEnrichmentModels+RecoveryPrefs.swift (SwiftLint file_length).
//

import Foundation

/// One enum, two positions: block field (`session_warmup` / `cooldown` only) and
/// tombstone / prefs key (all five kinds).
enum EnrichmentKind: String, Codable, CaseIterable, Equatable, Sendable {
    case sessionWarmup = "session_warmup"
    case cooldown
    case betweenSetRest = "between_set_rest"
    case exerciseWarmupSets = "exercise_warmup_sets"
    /// AMA-2423 — opt-in watch-ready recovery after every station in a
    /// multi-station circuit/superset/timed-round block. Tombstone / prefs
    /// key only, never a block field (mirrors `betweenSetRest`).
    case stationTransition = "station_transition"

    /// Kinds that appear as a `enrichment_kind` block field (soft sections).
    var isBlockKind: Bool {
        self == .sessionWarmup || self == .cooldown
    }
}

/// Per-workout delete marker. Written by callers, read by enrich, invisible to adapters.
struct EnrichmentTombstone: Equatable, Codable, Sendable {
    var kind: EnrichmentKind
    /// Required when `kind == .exerciseWarmupSets` (per-exercise tombstone).
    var exerciseId: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case exerciseId = "exercise_id"
    }

    init(kind: EnrichmentKind, exerciseId: String? = nil) {
        self.kind = kind
        self.exerciseId = exerciseId
    }

    /// Lenient list parse from ingest JSON — unknown kinds are dropped, never fatal.
    static func parseList(_ raw: Any?) -> [EnrichmentTombstone] {
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let rawKind = item["kind"] as? String,
                  let kind = EnrichmentKind(rawValue: rawKind) else { return nil }
            // Only per-exercise tombstones carry `exercise_id`; stray IDs on other
            // kinds never match `isTombstoned` and would silently drop the delete.
            let exerciseId = kind == .exerciseWarmupSets
                ? item["exercise_id"] as? String
                : nil
            guard kind != .exerciseWarmupSets || exerciseId != nil else { return nil }
            return EnrichmentTombstone(kind: kind, exerciseId: exerciseId)
        }
    }

    /// AMA-2334 left `WorkoutData.extra="forbid"` without a top-level
    /// `enrichment_tombstones` field, so callers persist under `metadata` until
    /// the save schema catches up. Enrich still accepts request-body tombstones
    /// and may also see a top-level key from older/local payloads — read both.
    static func parseFromWorkoutData(_ workoutData: [String: Any]) -> [EnrichmentTombstone] {
        let topLevel = parseList(workoutData["enrichment_tombstones"])
        if !topLevel.isEmpty { return topLevel }
        let metadata = workoutData["metadata"] as? [String: Any]
        return parseList(metadata?["enrichment_tombstones"])
    }

    /// Encode for `workout_data.metadata` (the only allowed nest today).
    static func metadataPayload(_ tombstones: [EnrichmentTombstone]) throws -> [[String: Any]] {
        try tombstones.map { try WorkoutEnrichmentJSON.object(from: $0) }
    }
}

/// One free-form row inside a session warm-up / cooldown soft section.
struct EnrichmentActivity: Equatable, Codable, Sendable {
    var name: String
    /// `nil` → open intent (lap at delivery).
    var durationSec: Int?
    var structureSource: StructureSource
    /// AMA-2378 — declared soft goal (time/distance/cals/open); `duration_sec`
    /// stays the timed-goal projection callers already read.
    var goal: ActivityGoal?

    enum CodingKeys: String, CodingKey {
        case name
        case durationSec = "duration_sec"
        case structureSource = "structure_source"
        case goal
    }

    init(
        name: String,
        durationSec: Int? = nil,
        structureSource: StructureSource = .enrichmentDefault,
        goal: ActivityGoal? = nil
    ) {
        self.name = name
        self.durationSec = durationSec
        self.structureSource = structureSource
        self.goal = goal
    }

    init(pref: EnrichmentActivityPref) {
        self.init(name: pref.name, durationSec: pref.durationSec, goal: pref.goal)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        durationSec = try container.decodeIfPresent(Int.self, forKey: .durationSec)
        structureSource = try container.decodeIfPresent(StructureSource.self, forKey: .structureSource)
            ?? .enrichmentDefault
        goal = try container.decodeIfPresent(ActivityGoal.self, forKey: .goal)
    }
}

/// Declared sibling of `sets: Int` — warm-up sets are rows, `sets` shape is unchanged.
/// AMA-2378: rows may declare `kind`/`value`/`intensity_note` instead of `reps`
/// (per-exercise ramps), so `reps` is optional — a row must carry `reps` or `kind`.
struct WarmupSetRow: Equatable, Codable, Sendable {
    var reps: Int?
    var weight: Double?
    var kind: WarmupSetKind?
    var value: Int?
    var intensityNote: String?
    var structureSource: StructureSource

    enum CodingKeys: String, CodingKey {
        case reps, weight, kind, value
        case intensityNote = "intensity_note"
        case structureSource = "structure_source"
    }

    init(
        reps: Int? = nil,
        weight: Double? = nil,
        kind: WarmupSetKind? = nil,
        value: Int? = nil,
        intensityNote: String? = nil,
        structureSource: StructureSource = .enrichmentDefault
    ) {
        self.reps = reps
        self.weight = weight
        self.kind = kind
        self.value = value
        self.intensityNote = intensityNote
        self.structureSource = structureSource
    }

    init(defaultSet: WarmupSetDefault) {
        self.init(reps: defaultSet.reps, weight: defaultSet.weight)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        let kind = try container.decodeIfPresent(WarmupSetKind.self, forKey: .kind)
        guard reps != nil || kind != nil else {
            throw WorkoutPreferencesValidationError.warmupSetRowRequiresRepsOrKind
        }
        self.reps = reps
        self.kind = kind
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        let decodedValue = try container.decodeIfPresent(Int.self, forKey: .value)
        // Open rows carry no value — mirror `parseList` so a decode → save
        // round-trip cannot re-emit an invalid `{kind: open, value: n}` pair.
        value = kind == .open ? nil : decodedValue
        intensityNote = try container.decodeIfPresent(String.self, forKey: .intensityNote)
        structureSource = try container.decodeIfPresent(StructureSource.self, forKey: .structureSource)
            ?? .enrichmentDefault
    }

    /// Lenient list parse from ingest JSON (`warmup_sets`) — rows need `reps` or `kind`.
    static func parseList(_ raw: Any?) -> [WarmupSetRow]? {
        guard let items = raw as? [[String: Any]] else { return nil }
        let rows: [WarmupSetRow] = items.compactMap { item in
            let weight = (item["weight"] as? Double) ?? (item["weight"] as? Int).map(Double.init)
            let source = (item["structure_source"] as? String)
                .flatMap(StructureSource.init(rawValue:)) ?? .enrichmentDefault
            let kind = (item["kind"] as? String).flatMap(WarmupSetKind.init(rawValue:))
            // Open goals must not carry a value — strip it so save round-trips stay valid.
            let value = kind == .open ? nil : (item["value"] as? Int)
            let intensityNote = item["intensity_note"] as? String
            guard let reps = item["reps"] as? Int else {
                guard let kind else { return nil }
                return WarmupSetRow(
                    kind: kind,
                    value: value,
                    intensityNote: intensityNote,
                    structureSource: source
                )
            }
            return WarmupSetRow(
                reps: reps,
                weight: weight,
                kind: kind,
                value: value,
                intensityNote: intensityNote,
                structureSource: source
            )
        }
        return rows.isEmpty ? nil : rows
    }
}

// MARK: - Preferences (`workout_preferences`)

/// Prefs-side activity row. Backend `SessionActivity` forbids extra keys, so prefs
/// carry no `structure_source` (that is stamped when enrichment writes the block).
/// `id` is UI-only (stable ForEach identity) and never encoded.
struct EnrichmentActivityPref: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var name: String
    var durationSec: Int?
    /// AMA-2378 — declared soft goal override; absent → `duration_sec`-only v1 shape.
    var goal: ActivityGoal?

    enum CodingKeys: String, CodingKey {
        case name
        case durationSec = "duration_sec"
        case goal
    }

    init(name: String, durationSec: Int? = nil, goal: ActivityGoal? = nil, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.durationSec = durationSec
        self.goal = goal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        name = try container.decode(String.self, forKey: .name)
        durationSec = try container.decodeIfPresent(Int.self, forKey: .durationSec)
        goal = try container.decodeIfPresent(ActivityGoal.self, forKey: .goal)
    }

    static func == (lhs: EnrichmentActivityPref, rhs: EnrichmentActivityPref) -> Bool {
        lhs.name == rhs.name && lhs.durationSec == rhs.durationSec && lhs.goal == rhs.goal
    }
}

/// Prefs-side warm-up set row (backend `WarmupSetDefault` — no `structure_source`).
/// `id` is UI-only (stable ForEach identity) and never encoded.
struct WarmupSetDefault: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var reps: Int
    var weight: Double?

    enum CodingKeys: String, CodingKey {
        case reps, weight
    }

    init(reps: Int, weight: Double? = nil, id: UUID = UUID()) {
        self.id = id
        self.reps = reps
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        reps = try container.decode(Int.self, forKey: .reps)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
    }

    static func == (lhs: WarmupSetDefault, rhs: WarmupSetDefault) -> Bool {
        lhs.reps == rhs.reps && lhs.weight == rhs.weight
    }
}

struct SessionWarmupPrefs: Equatable, Codable, Sendable {
    var enabled: Bool
    var activities: [EnrichmentActivityPref]

    enum CodingKeys: String, CodingKey {
        case enabled, activities
    }

    init(enabled: Bool = true, activities: [EnrichmentActivityPref] = []) {
        self.enabled = enabled
        self.activities = activities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        activities = try container.decodeIfPresent([EnrichmentActivityPref].self, forKey: .activities) ?? []
    }

    static let defaults = SessionWarmupPrefs(
        enabled: true,
        activities: [EnrichmentActivityPref(name: "Jump Rope")]
    )
}

struct CooldownPrefs: Equatable, Codable, Sendable {
    var enabled: Bool
    var activities: [EnrichmentActivityPref]

    enum CodingKeys: String, CodingKey {
        case enabled, activities
    }

    init(enabled: Bool = false, activities: [EnrichmentActivityPref] = []) {
        self.enabled = enabled
        self.activities = activities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        activities = try container.decodeIfPresent([EnrichmentActivityPref].self, forKey: .activities) ?? []
    }

    /// Cooldown ships off by default (spec §2 DEFAULT_PREFS).
    static let defaults = CooldownPrefs(enabled: false, activities: [])
}

struct ExerciseWarmupSetsPrefs: Equatable, Codable, Sendable {
    var enabled: Bool
    var defaultSets: [WarmupSetDefault]
    /// Normalized name keys — matching runs server-side at enrich time.
    var excludeExerciseKeys: [String]
    /// AMA-2378 / AMA-2408 — per-exercise ramp overrides (`exercise_ref` → sets).
    /// Opt-in only: `nil`/empty means ZERO ramps (never the v1 global
    /// `default_sets` auto-apply). `default_sets` remains the seed for a newly
    /// enabled exercise's ramp (8/5), not a silent apply-to-all.
    var perExercise: [PerExerciseRamp]?

    enum CodingKeys: String, CodingKey {
        case enabled
        case defaultSets = "default_sets"
        case excludeExerciseKeys = "exclude_exercise_keys"
        case perExercise = "per_exercise"
    }

    init(
        enabled: Bool = true,
        defaultSets: [WarmupSetDefault] = [],
        excludeExerciseKeys: [String] = [],
        perExercise: [PerExerciseRamp]? = nil
    ) {
        self.enabled = enabled
        self.defaultSets = defaultSets
        self.excludeExerciseKeys = excludeExerciseKeys
        self.perExercise = perExercise
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        defaultSets = try container.decodeIfPresent([WarmupSetDefault].self, forKey: .defaultSets) ?? []
        excludeExerciseKeys = try container.decodeIfPresent([String].self, forKey: .excludeExerciseKeys) ?? []
        perExercise = try container.decodeIfPresent([PerExerciseRamp].self, forKey: .perExercise)
    }

    static let defaults = ExerciseWarmupSetsPrefs(
        enabled: true,
        defaultSets: [WarmupSetDefault(reps: 8), WarmupSetDefault(reps: 5)],
        excludeExerciseKeys: []
    )
}

/// `workout_preferences` — defaults source only, never a caller of enrich (spec §5).
struct WorkoutPreferences: Equatable, Codable, Sendable {
    var sessionWarmup: SessionWarmupPrefs
    var cooldown: CooldownPrefs
    var betweenSetRest: BetweenSetRestPrefs
    var exerciseWarmupSets: ExerciseWarmupSetsPrefs
    /// AMA-2423 — off by default (mirrors backend `DEFAULT_PREFS`).
    var stationTransition: StationTransitionPrefs

    enum CodingKeys: String, CodingKey {
        case sessionWarmup = "session_warmup"
        case cooldown
        case betweenSetRest = "between_set_rest"
        case exerciseWarmupSets = "exercise_warmup_sets"
        case stationTransition = "station_transition"
    }

    init(
        sessionWarmup: SessionWarmupPrefs = .defaults,
        cooldown: CooldownPrefs = .defaults,
        betweenSetRest: BetweenSetRestPrefs = .defaults,
        exerciseWarmupSets: ExerciseWarmupSetsPrefs = .defaults,
        stationTransition: StationTransitionPrefs = .defaults
    ) {
        self.sessionWarmup = sessionWarmup
        self.cooldown = cooldown
        self.betweenSetRest = betweenSetRest
        self.exerciseWarmupSets = exerciseWarmupSets
        self.stationTransition = stationTransition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionWarmup = try container.decodeIfPresent(SessionWarmupPrefs.self, forKey: .sessionWarmup)
            ?? .defaults
        cooldown = try container.decodeIfPresent(CooldownPrefs.self, forKey: .cooldown) ?? .defaults
        betweenSetRest = try container.decodeIfPresent(BetweenSetRestPrefs.self, forKey: .betweenSetRest)
            ?? .defaults
        exerciseWarmupSets = try container
            .decodeIfPresent(ExerciseWarmupSetsPrefs.self, forKey: .exerciseWarmupSets) ?? .defaults
        stationTransition = try container
            .decodeIfPresent(StationTransitionPrefs.self, forKey: .stationTransition) ?? .defaults
    }

    /// Mirrors backend `DEFAULT_PREFS` (cooldown off).
    static let defaults = WorkoutPreferences()

    /// Default warm-up set rows stamped `enrichment_default` for quick-add.
    var defaultWarmupSetRows: [WarmupSetRow] {
        exerciseWarmupSets.defaultSets.map(WarmupSetRow.init(defaultSet:))
    }

    /// Default soft-section activities stamped `enrichment_default` for quick-add.
    var sessionWarmupActivities: [EnrichmentActivity] {
        sessionWarmup.activities.map(EnrichmentActivity.init(pref:))
    }

    var cooldownActivities: [EnrichmentActivity] {
        cooldown.activities.map(EnrichmentActivity.init(pref:))
    }
}

/// Contradictory declared intent — surfaced instead of silently dropping a field.
enum WorkoutPreferencesValidationError: Error, Equatable {
    /// `rest_open == true` requires `rest_sec` to be nil (spec §2 / backend 400).
    case restOpenWithRestSec
    /// AMA-2423 — `transition_open == true` requires `transition_sec` to be nil
    /// (mirrors `restOpenWithRestSec` / backend `_normalize_station_transition`).
    case transitionOpenWithTransitionSec
    /// `ActivityGoal.kind == .open` must not carry a `value` (AMA-2378 backend 422).
    case activityGoalOpenWithValue
    /// `ActivityGoal.kind != .open` requires a `value` (AMA-2378 backend 422).
    case activityGoalRequiresValue
    /// `RampSet.kind == .open` must not carry a `value` (AMA-2378 backend 422).
    case rampSetOpenWithValue
    /// `RampSet.kind != .open` requires a `value` (AMA-2378 backend 422).
    case rampSetRequiresValue
    /// `WarmupSetRow` (backend `DeclaredWarmupSet`) requires `reps` or `kind`.
    case warmupSetRowRequiresRepsOrKind
}
