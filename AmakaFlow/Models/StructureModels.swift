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
    case unknown
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
    case rounds
    case regular

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
        structureSource: StructureSource = .unknown
    ) {
        self.type = type
        self.label = label
        self.rounds = rounds
        self.restSec = restSec
        self.exercises = exercises
        self.structureSource = structureSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(StructureBlockType.self, forKey: .type) ?? .sets
        label = try container.decodeIfPresent(String.self, forKey: .label)
        rounds = try container.decodeIfPresent(Int.self, forKey: .rounds)
        restSec = try container.decodeIfPresent(Int.self, forKey: .restSec)
        exercises = try container.decodeIfPresent([StructureExerciseModel].self, forKey: .exercises) ?? []
        structureSource = try container.decodeIfPresent(StructureSource.self, forKey: .structureSource) ?? .unknown
    }
}

struct StructureSuggestionModel: Codable, Equatable, Sendable {
    var type: StructureBlockType
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
        structureSource: StructureSource = .inferred
    ) {
        self.type = type
        self.label = label
        self.rounds = rounds
        self.restSec = restSec
        self.exerciseNames = exerciseNames
        self.exerciseIndices = exerciseIndices
        self.structureSource = structureSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(StructureBlockType.self, forKey: .type)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        rounds = try container.decodeIfPresent(Int.self, forKey: .rounds)
        restSec = try container.decodeIfPresent(Int.self, forKey: .restSec)
        exerciseNames = try container.decodeIfPresent([String].self, forKey: .exerciseNames) ?? []
        exerciseIndices = try container.decodeIfPresent([Int].self, forKey: .exerciseIndices) ?? []
        structureSource = try container.decodeIfPresent(StructureSource.self, forKey: .structureSource) ?? .inferred
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
    /// UI provenance tag copy (screens-clarify.jsx).
    func clarifyTag(typeLabel: String) -> String {
        switch self {
        case .userConfirmed:
            return "\(typeLabel.uppercased()) ✓"
        case .userNote:
            return "FROM YOUR NOTE · \(typeLabel.uppercased())"
        case .explicit, .inferred, .unknown:
            return "SUGGESTED · \(typeLabel.uppercased())"
        }
    }
}
