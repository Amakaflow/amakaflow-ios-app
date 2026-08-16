import Foundation

enum BlockStructure: String, Codable, CaseIterable {
    case straight, superset, circuit, amrap, emom, tabata
    case timedCircuit = "timed_circuit"
    // AMA-2438 P3: widen for warm-up, cooldown, for-time
    case warmup = "warmup"
    case cooldown = "cooldown"
    case fortime = "fortime"

    var displayName: String {
        switch self {
        case .straight: return "Straight"
        case .superset: return "Superset"
        case .circuit: return "Circuit"
        case .amrap: return "AMRAP"
        case .emom: return "EMOM"
        case .tabata: return "Tabata"
        case .timedCircuit: return "Timed Circuit"
        case .warmup: return "Warm-up"
        case .cooldown: return "Cooldown"
        case .fortime: return "For Time"
        }
    }
}

struct Block: Codable, Hashable, Identifiable {
    let label: String?
    let structure: BlockStructure
    let rounds: Int
    let exercises: [Exercise]
    let restBetweenSeconds: Int?
    /// AMA-2438 P3: add time cap for AMRAP/for-time blocks
    let timeCapSec: Int?

    /// Stable identity for SwiftUI. Always a unique UUID — never derived from label,
    /// which can repeat across blocks.
    let id: String

    enum CodingKeys: String, CodingKey {
        case label, structure, rounds, exercises
        // The backend sends "rest_between_sec" which .convertFromSnakeCase converts
        // to "restBetweenSec". We use camelCase raw value to match the converted key.
        case restBetweenSeconds = "restBetweenSec"
        case timeCapSec = "timeCapSec"
        // id is excluded — generated locally, not in API JSON
    }

    init(
        label: String?,
        structure: BlockStructure = .straight,
        rounds: Int = 1,
        exercises: [Exercise],
        restBetweenSeconds: Int? = nil,
        timeCapSec: Int? = nil
    ) {
        self.id = UUID().uuidString
        self.label = label
        self.structure = structure
        self.rounds = rounds
        self.exercises = exercises
        self.restBetweenSeconds = restBetweenSeconds
        self.timeCapSec = timeCapSec
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedLabel = try container.decodeIfPresent(String.self, forKey: .label)
        self.label = decodedLabel
        self.id = UUID().uuidString
        // Decode structure gracefully — unknown values fall back to .straight
        if let rawStructure = try container.decodeIfPresent(String.self, forKey: .structure) {
            structure = BlockStructure(rawValue: rawStructure) ?? .straight
        } else {
            structure = .straight
        }
        rounds = try container.decodeIfPresent(Int.self, forKey: .rounds) ?? 1
        exercises = try container.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
        restBetweenSeconds = try container.decodeIfPresent(Int.self, forKey: .restBetweenSeconds)
        timeCapSec = try container.decodeIfPresent(Int.self, forKey: .timeCapSec)
    }

    var exerciseCount: Int { exercises.count }
}
