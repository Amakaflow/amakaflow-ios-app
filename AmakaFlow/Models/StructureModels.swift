//
//  StructureModels.swift
//  AmakaFlow
//
//  AMA-2305 / ADR-017 — BFF camelCase models for structure suggest + apply.
//  Source of truth: mobile-bff app/schemas.py (StructureBlockModel, …).
//

import Foundation

/// Provenance for a structure block (UI face of ADR-017 `structureSource`).
enum StructureSource: String, Codable, CaseIterable, Equatable, Sendable {
    case explicit
    case inferred
    case userConfirmed = "user_confirmed"
    case userNote = "user_note"
    /// AMA-2336 — user inserted via editor / push apply.
    case userAdded = "user_added"
    /// AMA-2336 — applied from enrichment prefs at enrich time (standing consent).
    case enrichmentDefault = "enrichment_default"
    case unknown

    /// Unknown-tolerant decode (AMA-2336 §2): literals this build predates map to `.unknown`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StructureSource(rawValue: raw) ?? .unknown
    }
}

/// Canonical block types from ADR-017 / BFF `StructureBlockTypeLiteral`.
enum StructureBlockType: String, Codable, CaseIterable, Equatable, Sendable {
    case sets
    case superset
    case circuit
    case emom
    case amrap
    case tabata
    case forTime = "for-time"
    case fortime
    case warmup
    case cooldown
    case rounds
    case regular
    /// Timed circuit (2026-08-05 spec §2.1) — fixed-duration station rotation.
    case timedCircuit = "timed_circuit"
    /// Literals this build predates map here (same pattern as StructureSource).
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StructureBlockType(rawValue: raw) ?? .unknown
    }

    /// Display label for clarify pills (screens-clarify.jsx `DC_TYPES`).
    var displayLabel: String {
        switch self {
        case .sets, .regular: return "Sets"
        case .superset: return "Superset"
        case .circuit, .rounds: return "Circuit"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .tabata: return "Tabata"
        case .forTime, .fortime: return "For time"
        case .warmup: return "Warm-up"
        case .cooldown: return "Cool-down"
        case .timedCircuit: return "Timed circuit"
        case .unknown: return "Block"
        }
    }

    /// Normalize aliases used by the backend.
    var canonical: StructureBlockType {
        switch self {
        case .fortime: return .forTime
        case .regular: return .sets
        case .rounds: return .circuit
        default: return self
        }
    }
}

struct StructureExerciseModel: Codable, Equatable, Sendable {
    var name: String
    var sets: Int?
    var reps: Int?
    var restSec: Int?
    var distanceM: Int?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, notes
        case restSec
        case distanceM
    }
}

struct StructureBlockModel: Codable, Equatable, Sendable {
    var type: StructureBlockType
    /// Original wire `type` string when decoded as `.unknown` (not in CodingKeys).
    var rawType: String?
    var label: String?
    var rounds: Int?
    var restSec: Int?
    var exercises: [StructureExerciseModel]
    var structureSource: StructureSource

    enum CodingKeys: String, CodingKey {
        case type, label, rounds, exercises
        case restSec
        case structureSource
    }

    init(
        type: StructureBlockType = .sets,
        label: String? = nil,
        rounds: Int? = nil,
        restSec: Int? = nil,
        exercises: [StructureExerciseModel] = [],
        structureSource: StructureSource = .unknown,
        rawType: String? = nil
    ) {
        self.type = type
        self.rawType = rawType
        self.label = label
        self.rounds = rounds
        self.restSec = restSec
        self.exercises = exercises
        self.structureSource = structureSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTypeString = try container.decodeIfPresent(String.self, forKey: .type)
        rawType = rawTypeString
        type = rawTypeString.map { StructureBlockType(rawValue: $0) ?? .unknown } ?? .sets
        label = try container.decodeIfPresent(String.self, forKey: .label)
        rounds = try container.decodeIfPresent(Int.self, forKey: .rounds)
        restSec = try container.decodeIfPresent(Int.self, forKey: .restSec)
        exercises = try container.decodeIfPresent([StructureExerciseModel].self, forKey: .exercises) ?? []
        structureSource = try container.decodeIfPresent(StructureSource.self, forKey: .structureSource) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type == .unknown ? (rawType ?? type.rawValue) : type.rawValue, forKey: .type)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(rounds, forKey: .rounds)
        try container.encodeIfPresent(restSec, forKey: .restSec)
        try container.encode(exercises, forKey: .exercises)
        try container.encode(structureSource, forKey: .structureSource)
    }
}

struct StructureSuggestionModel: Codable, Equatable, Sendable {
    var type: StructureBlockType
    /// Original wire `type` string when decoded as `.unknown` (not in CodingKeys).
    var rawType: String?
    var label: String?
    var rounds: Int?
    var restSec: Int?
    var exerciseNames: [String]
    var exerciseIndices: [Int]
    var structureSource: StructureSource

    enum CodingKeys: String, CodingKey {
        case type, label, rounds
        case restSec
        case exerciseNames
        case exerciseIndices
        case structureSource
    }

    init(
        type: StructureBlockType,
        label: String? = nil,
        rounds: Int? = nil,
        restSec: Int? = nil,
        exerciseNames: [String] = [],
        exerciseIndices: [Int] = [],
        structureSource: StructureSource = .inferred,
        rawType: String? = nil
    ) {
        self.type = type
        self.rawType = rawType
        self.label = label
        self.rounds = rounds
        self.restSec = restSec
        self.exerciseNames = exerciseNames
        self.exerciseIndices = exerciseIndices
        self.structureSource = structureSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTypeString = try container.decodeIfPresent(String.self, forKey: .type)
        rawType = rawTypeString
        type = rawTypeString.map { StructureBlockType(rawValue: $0) ?? .unknown } ?? .sets
        label = try container.decodeIfPresent(String.self, forKey: .label)
        rounds = try container.decodeIfPresent(Int.self, forKey: .rounds)
        restSec = try container.decodeIfPresent(Int.self, forKey: .restSec)
        exerciseNames = try container.decodeIfPresent([String].self, forKey: .exerciseNames) ?? []
        exerciseIndices = try container.decodeIfPresent([Int].self, forKey: .exerciseIndices) ?? []
        structureSource = try container.decodeIfPresent(StructureSource.self, forKey: .structureSource) ?? .inferred
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type == .unknown ? (rawType ?? type.rawValue) : type.rawValue, forKey: .type)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(rounds, forKey: .rounds)
        try container.encodeIfPresent(restSec, forKey: .restSec)
        try container.encode(exerciseNames, forKey: .exerciseNames)
        try container.encode(exerciseIndices, forKey: .exerciseIndices)
        try container.encode(structureSource, forKey: .structureSource)
    }
}

struct StructureSuggestRequest: Encodable, Equatable, Sendable {
    var text: String
    var source: String?
}

struct StructureSuggestResult: Codable, Equatable, Sendable {
    var exercises: [StructureExerciseModel]
    var suggestions: [StructureSuggestionModel]
    var blocks: [StructureBlockModel]

    init(
        exercises: [StructureExerciseModel] = [],
        suggestions: [StructureSuggestionModel] = [],
        blocks: [StructureBlockModel] = []
    ) {
        self.exercises = exercises
        self.suggestions = suggestions
        self.blocks = blocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exercises = try container.decodeIfPresent([StructureExerciseModel].self, forKey: .exercises) ?? []
        suggestions = try container.decodeIfPresent([StructureSuggestionModel].self, forKey: .suggestions) ?? []
        blocks = try container.decodeIfPresent([StructureBlockModel].self, forKey: .blocks) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case exercises, suggestions, blocks
    }
}

/// Request body for POST `/v1/ingest/structure/apply`.
/// `ops` stays loosely typed to match ADR utterance patches / BFF Dict payloads.
struct ApplyStructureRequest: Equatable, Sendable {
    var blocks: [StructureBlockModel]
    var ops: [[String: Any]]?
    var note: String?

    static func == (lhs: ApplyStructureRequest, rhs: ApplyStructureRequest) -> Bool {
        lhs.blocks == rhs.blocks
            && lhs.note == rhs.note
            && NSDictionary(dictionary: ["ops": lhs.ops ?? []])
            .isEqual(to: ["ops": rhs.ops ?? []])
    }

    /// Encode camelCase JSON matching BFF `ApplyStructureRequest`.
    func jsonData(encoder: JSONEncoder = StructureJSON.encoder) throws -> Data {
        var root: [String: Any] = [:]
        let blocksData = try encoder.encode(blocks)
        guard let blocksJSON = try JSONSerialization.jsonObject(with: blocksData) as? [[String: Any]] else {
            throw EncodingError.invalidValue(
                blocks,
                EncodingError.Context(codingPath: [], debugDescription: "Unable to encode structure blocks")
            )
        }
        root["blocks"] = blocksJSON
        if let ops, !ops.isEmpty {
            root["ops"] = ops
        }
        if let note {
            root["note"] = note
        }
        return try JSONSerialization.data(withJSONObject: root)
    }
}

struct ApplyStructureResult: Codable, Equatable, Sendable {
    var blocks: [StructureBlockModel]

    init(blocks: [StructureBlockModel] = []) {
        self.blocks = blocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try container.decodeIfPresent([StructureBlockModel].self, forKey: .blocks) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case blocks
    }
}

enum StructureJSON {
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
}

extension StructureSource {
    /// UI provenance tag copy (ADR-017 / AMA-2326 — EXPLICIT is distinct from SUGGESTED).
    func clarifyTag(typeLabel: String) -> String {
        switch self {
        case .userConfirmed, .userAdded:
            return "\(typeLabel.uppercased()) ✓"
        case .userNote:
            return "FROM YOUR NOTE · \(typeLabel.uppercased())"
        case .explicit:
            return "EXPLICIT · \(typeLabel.uppercased())"
        case .enrichmentDefault:
            return "DEFAULT · \(typeLabel.uppercased())"
        case .inferred, .unknown:
            return "SUGGESTED · \(typeLabel.uppercased())"
        }
    }
}
