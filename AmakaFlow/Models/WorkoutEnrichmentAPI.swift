//
//  WorkoutEnrichmentAPI.swift
//  AmakaFlow
//
//  AMA-2336 — POST `/workout/enrich` request / response shapes (mapper-api
//  `api/routers/enrichment.py`). Declared snake_case keys, untyped `blocks_json`.
//

import Foundation

enum EnrichMode: String, Codable, Sendable {
    case editor
    case push
}

/// Disjoint summary buckets (spec §3).
struct EnrichmentAppliedSummary: Equatable, Codable, Sendable {
    var prefsSource: String
    var added: [String]
    var refreshed: [String]
    var skippedTombstoned: [String]
    var skippedAlreadyPresent: [String]
    /// Exercise names skipped for `warmup_sets` (no `exercise_id`).
    var skippedNoIdentity: [String]
    /// `exercise_id` values skipped for per-exercise tombstones.
    var skippedTombstonedExercises: [String]

    enum CodingKeys: String, CodingKey {
        case prefsSource = "prefs_source"
        case added, refreshed
        case skippedTombstoned = "skipped_tombstoned"
        case skippedAlreadyPresent = "skipped_already_present"
        case skippedNoIdentity = "skipped_no_identity"
        case skippedTombstonedExercises = "skipped_tombstoned_exercises"
    }

    init(
        prefsSource: String = "defaults",
        added: [String] = [],
        refreshed: [String] = [],
        skippedTombstoned: [String] = [],
        skippedAlreadyPresent: [String] = [],
        skippedNoIdentity: [String] = [],
        skippedTombstonedExercises: [String] = []
    ) {
        self.prefsSource = prefsSource
        self.added = added
        self.refreshed = refreshed
        self.skippedTombstoned = skippedTombstoned
        self.skippedAlreadyPresent = skippedAlreadyPresent
        self.skippedNoIdentity = skippedNoIdentity
        self.skippedTombstonedExercises = skippedTombstonedExercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prefsSource = try container.decodeIfPresent(String.self, forKey: .prefsSource) ?? "defaults"
        added = try container.decodeIfPresent([String].self, forKey: .added) ?? []
        refreshed = try container.decodeIfPresent([String].self, forKey: .refreshed) ?? []
        skippedTombstoned = try container.decodeIfPresent([String].self, forKey: .skippedTombstoned) ?? []
        skippedAlreadyPresent = try container
            .decodeIfPresent([String].self, forKey: .skippedAlreadyPresent) ?? []
        skippedNoIdentity = try container.decodeIfPresent([String].self, forKey: .skippedNoIdentity) ?? []
        skippedTombstonedExercises = try container
            .decodeIfPresent([String].self, forKey: .skippedTombstonedExercises) ?? []
    }
}

/// Request body for POST `/workout/enrich`. `blocks_json` stays untyped — mirror of
/// the backend `dict` field, same pattern as `ApplyStructureRequest.ops`.
struct EnrichRequest: Equatable {
    var blocksJSON: [String: Any]
    var prefs: WorkoutPreferences?
    var tombstones: [EnrichmentTombstone]?
    var mode: EnrichMode

    init(
        blocksJSON: [String: Any],
        prefs: WorkoutPreferences? = nil,
        tombstones: [EnrichmentTombstone]? = nil,
        mode: EnrichMode = .push
    ) {
        self.blocksJSON = blocksJSON
        self.prefs = prefs
        self.tombstones = tombstones
        self.mode = mode
    }

    static func == (lhs: EnrichRequest, rhs: EnrichRequest) -> Bool {
        lhs.prefs == rhs.prefs
            && lhs.tombstones == rhs.tombstones
            && lhs.mode == rhs.mode
            && NSDictionary(dictionary: lhs.blocksJSON).isEqual(to: rhs.blocksJSON)
    }

    func jsonObject() throws -> [String: Any] {
        var root: [String: Any] = [
            "blocks_json": blocksJSON,
            "mode": mode.rawValue
        ]
        if let prefs {
            root["prefs"] = try WorkoutEnrichmentJSON.object(from: prefs)
        }
        if let tombstones {
            root["tombstones"] = try tombstones.map { try WorkoutEnrichmentJSON.object(from: $0) }
        }
        return root
    }

    func jsonData() throws -> Data {
        let object = try jsonObject()
        guard JSONSerialization.isValidJSONObject(object) else {
            throw EncodingError.invalidValue(
                object,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "blocks_json contains values that are not JSON-serializable"
                )
            )
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

/// Response for POST `/workout/enrich`.
struct EnrichResponse: Equatable {
    var blocksJSON: [String: Any]
    var enrichmentApplied: EnrichmentAppliedSummary?

    init(blocksJSON: [String: Any], enrichmentApplied: EnrichmentAppliedSummary? = nil) {
        self.blocksJSON = blocksJSON
        self.enrichmentApplied = enrichmentApplied
    }

    static func == (lhs: EnrichResponse, rhs: EnrichResponse) -> Bool {
        lhs.enrichmentApplied == rhs.enrichmentApplied
            && NSDictionary(dictionary: lhs.blocksJSON).isEqual(to: rhs.blocksJSON)
    }

    static func from(data: Data) throws -> EnrichResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocksJSON = root["blocks_json"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Missing blocks_json in enrich response")
            )
        }
        var summary: EnrichmentAppliedSummary?
        if let applied = root["enrichment_applied"] as? [String: Any] {
            let appliedData = try JSONSerialization.data(withJSONObject: applied)
            summary = try WorkoutEnrichmentJSON.decoder.decode(EnrichmentAppliedSummary.self, from: appliedData)
        }
        return EnrichResponse(blocksJSON: blocksJSON, enrichmentApplied: summary)
    }
}

enum WorkoutEnrichmentJSON {
    /// Explicit CodingKeys already carry snake_case — no key strategy conversion.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()

    static func object<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Expected a JSON object")
            )
        }
        return object
    }
}

/// `normalize_exercise_key` parity for UX preview only — exclusion matching runs
/// server-side at enrich time so client and server cannot diverge (spec §2).
enum ExerciseKeyNormalizer {
    static func normalize(_ name: String) -> String {
        let nfkc = name.precomposedStringWithCompatibilityMapping
        let trimmed = nfkc.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.split { $0.isWhitespace }.joined(separator: " ")
        return collapsed.lowercased()
    }
}
