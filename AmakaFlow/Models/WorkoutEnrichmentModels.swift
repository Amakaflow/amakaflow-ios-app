//
//  WorkoutEnrichmentModels.swift
//  AmakaFlow
//
//  AMA-2336 — declared enrichment contract (spec 2026-07-27 §§1–2).
//  Source of truth: mapper-api `domain/enrichment.py` + `api/routers/enrichment.py`
//  (AMA-2334). Snake_case CodingKeys mirror the backend payloads exactly — no
//  underscore smuggling, one provenance system.
//

import Foundation

/// One enum, two positions: block field (`session_warmup` / `cooldown` only) and
/// tombstone / prefs key (all four kinds).
enum EnrichmentKind: String, Codable, CaseIterable, Equatable, Sendable {
    case sessionWarmup = "session_warmup"
    case cooldown
    case betweenSetRest = "between_set_rest"
    case exerciseWarmupSets = "exercise_warmup_sets"

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

    enum CodingKeys: String, CodingKey {
        case name
        case durationSec = "duration_sec"
        case structureSource = "structure_source"
    }

    init(
        name: String,
        durationSec: Int? = nil,
        structureSource: StructureSource = .enrichmentDefault
    ) {
        self.name = name
        self.durationSec = durationSec
        self.structureSource = structureSource
    }

    init(pref: EnrichmentActivityPref) {
        self.init(name: pref.name, durationSec: pref.durationSec)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        durationSec = try container.decodeIfPresent(Int.self, forKey: .durationSec)
        structureSource = try container.decodeIfPresent(StructureSource.self, forKey: .structureSource)
            ?? .enrichmentDefault
    }
}

/// Declared sibling of `sets: Int` — warm-up sets are rows, `sets` shape is unchanged.
struct WarmupSetRow: Equatable, Codable, Sendable {
    var reps: Int
    var weight: Double?
    var structureSource: StructureSource

    enum CodingKeys: String, CodingKey {
        case reps, weight
        case structureSource = "structure_source"
    }

    init(
        reps: Int,
        weight: Double? = nil,
        structureSource: StructureSource = .enrichmentDefault
    ) {
        self.reps = reps
        self.weight = weight
        self.structureSource = structureSource
    }

    init(defaultSet: WarmupSetDefault) {
        self.init(reps: defaultSet.reps, weight: defaultSet.weight)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reps = try container.decodeIfPresent(Int.self, forKey: .reps) ?? 1
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        structureSource = try container.decodeIfPresent(StructureSource.self, forKey: .structureSource)
            ?? .enrichmentDefault
    }

    /// Lenient list parse from ingest JSON (`warmup_sets`).
    static func parseList(_ raw: Any?) -> [WarmupSetRow]? {
        guard let items = raw as? [[String: Any]] else { return nil }
        let rows: [WarmupSetRow] = items.compactMap { item in
            guard let reps = item["reps"] as? Int else { return nil }
            let weight = (item["weight"] as? Double) ?? (item["weight"] as? Int).map(Double.init)
            let source = (item["structure_source"] as? String)
                .flatMap(StructureSource.init(rawValue:)) ?? .enrichmentDefault
            return WarmupSetRow(reps: reps, weight: weight, structureSource: source)
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

    enum CodingKeys: String, CodingKey {
        case name
        case durationSec = "duration_sec"
    }

    init(name: String, durationSec: Int? = nil, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.durationSec = durationSec
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        name = try container.decode(String.self, forKey: .name)
        durationSec = try container.decodeIfPresent(Int.self, forKey: .durationSec)
    }

    static func == (lhs: EnrichmentActivityPref, rhs: EnrichmentActivityPref) -> Bool {
        lhs.name == rhs.name && lhs.durationSec == rhs.durationSec
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

/// Rest intent prefs. Invalid states are unrepresentable: `rest_open == true`
/// requires `rest_sec == nil` (spec §2 — contradictory intent is rejected, not dropped).
struct BetweenSetRestPrefs: Equatable, Codable, Sendable {
    var enabled: Bool
    private(set) var restSec: Int?
    private(set) var restOpen: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case restSec = "rest_sec"
        case restOpen = "rest_open"
    }

    init(enabled: Bool = true, restSec: Int? = nil, restOpen: Bool = false) throws {
        let validated = try WorkoutEnrichmentMutations.validatedRest(restSec: restSec, restOpen: restOpen)
        self.enabled = enabled
        self.restSec = validated.restSec
        self.restOpen = validated.restOpen
    }

    private init(enabled: Bool, uncheckedRestSec: Int?, restOpen: Bool) {
        self.enabled = enabled
        self.restSec = uncheckedRestSec
        self.restOpen = restOpen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            enabled: container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            restSec: container.decodeIfPresent(Int.self, forKey: .restSec),
            restOpen: container.decodeIfPresent(Bool.self, forKey: .restOpen) ?? false
        )
    }

    mutating func setRest(restSec: Int?, restOpen: Bool) throws {
        let validated = try WorkoutEnrichmentMutations.validatedRest(restSec: restSec, restOpen: restOpen)
        self.restSec = validated.restSec
        self.restOpen = validated.restOpen
    }

    static let defaults = BetweenSetRestPrefs(enabled: true, uncheckedRestSec: 60, restOpen: false)
}

struct ExerciseWarmupSetsPrefs: Equatable, Codable, Sendable {
    var enabled: Bool
    var defaultSets: [WarmupSetDefault]
    /// Normalized name keys — matching runs server-side at enrich time.
    var excludeExerciseKeys: [String]

    enum CodingKeys: String, CodingKey {
        case enabled
        case defaultSets = "default_sets"
        case excludeExerciseKeys = "exclude_exercise_keys"
    }

    init(
        enabled: Bool = true,
        defaultSets: [WarmupSetDefault] = [],
        excludeExerciseKeys: [String] = []
    ) {
        self.enabled = enabled
        self.defaultSets = defaultSets
        self.excludeExerciseKeys = excludeExerciseKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        defaultSets = try container.decodeIfPresent([WarmupSetDefault].self, forKey: .defaultSets) ?? []
        excludeExerciseKeys = try container.decodeIfPresent([String].self, forKey: .excludeExerciseKeys) ?? []
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

    enum CodingKeys: String, CodingKey {
        case sessionWarmup = "session_warmup"
        case cooldown
        case betweenSetRest = "between_set_rest"
        case exerciseWarmupSets = "exercise_warmup_sets"
    }

    init(
        sessionWarmup: SessionWarmupPrefs = .defaults,
        cooldown: CooldownPrefs = .defaults,
        betweenSetRest: BetweenSetRestPrefs = .defaults,
        exerciseWarmupSets: ExerciseWarmupSetsPrefs = .defaults
    ) {
        self.sessionWarmup = sessionWarmup
        self.cooldown = cooldown
        self.betweenSetRest = betweenSetRest
        self.exerciseWarmupSets = exerciseWarmupSets
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
}

// MARK: - Presence + tombstone reads

/// Presence is tested by **type**, never by provenance (spec invariant 1).
enum WorkoutEnrichmentPresence {
    static func hasWarmupBlock(in blocks: [SocialImportBlock]) -> Bool {
        blocks.contains { normalizedType($0) == StructureBlockType.warmup.rawValue }
    }

    static func hasCooldownBlock(in blocks: [SocialImportBlock]) -> Bool {
        blocks.contains { normalizedType($0) == StructureBlockType.cooldown.rawValue }
    }

    static func isTombstoned(
        _ kind: EnrichmentKind,
        exerciseId: String? = nil,
        tombstones: [EnrichmentTombstone]
    ) -> Bool {
        tombstones.contains { tombstone in
            guard tombstone.kind == kind else { return false }
            guard kind == .exerciseWarmupSets else { return tombstone.exerciseId == nil }
            guard let exerciseId, let tombstonedId = tombstone.exerciseId else { return false }
            return tombstonedId == exerciseId
        }
    }

    private static func normalizedType(_ block: SocialImportBlock) -> String {
        block.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

// MARK: - Caller-owned mutations

/// Pure helpers for editor / push callers. Tombstones are written **only** here,
/// never by the enrichment core.
enum WorkoutEnrichmentMutations {
    static let restSecKey = "rest_sec"
    static let restOpenKey = "rest_open"

    /// Stable within-workout identity (`wex_…`) — tombstones key off this, not the name.
    static func mintExerciseId() -> String {
        "wex_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func appendTombstone(
        _ list: inout [EnrichmentTombstone],
        kind: EnrichmentKind,
        exerciseId: String? = nil
    ) {
        let resolvedId = kind == .exerciseWarmupSets ? exerciseId : nil
        // A per-exercise tombstone without an id is rejected by the backend — skip it.
        guard kind != .exerciseWarmupSets || resolvedId != nil else { return }
        let tombstone = EnrichmentTombstone(kind: kind, exerciseId: resolvedId)
        guard !list.contains(tombstone) else { return }
        list.append(tombstone)
    }

    static func clearTombstone(
        _ list: inout [EnrichmentTombstone],
        kind: EnrichmentKind,
        exerciseId: String? = nil
    ) {
        list.removeAll { tombstone in
            WorkoutEnrichmentPresence.isTombstoned(kind, exerciseId: exerciseId, tombstones: [tombstone])
        }
    }

    static func stampRestEnrichmentDefault(fieldProvenance: inout [String: ProvSource]) {
        fieldProvenance[restSecKey] = .enrichmentDefault
        fieldProvenance[restOpenKey] = .enrichmentDefault
    }

    static func stampRestUser(fieldProvenance: inout [String: ProvSource]) {
        fieldProvenance[restSecKey] = .user
        fieldProvenance[restOpenKey] = .user
    }

    /// Reject contradictory rest intent — `rest_open` true with a timed `rest_sec`.
    static func validatedRest(restSec: Int?, restOpen: Bool) throws -> (restSec: Int?, restOpen: Bool) {
        if restOpen, restSec != nil {
            throw WorkoutPreferencesValidationError.restOpenWithRestSec
        }
        return (restSec, restOpen)
    }
}
