import Foundation

enum BlockStructure: String, Codable, CaseIterable {
    case straight, superset, circuit, amrap, emom, tabata

    var displayName: String {
        switch self {
        case .straight: return "Straight"
        case .superset: return "Superset"
        case .circuit: return "Circuit"
        case .amrap: return "AMRAP"
        case .emom: return "EMOM"
        case .tabata: return "Tabata"
        }
    }
}

struct Block: Codable, Hashable, Identifiable {
    let label: String?
    let structure: BlockStructure
    let rounds: Int
    let exercises: [Exercise]
    let restBetweenSeconds: Int?

    var id: String { label ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case label, structure, rounds, exercises
        case restBetweenSeconds = "rest_between_sec"
    }

    init(label: String?, structure: BlockStructure = .straight, rounds: Int = 1, exercises: [Exercise], restBetweenSeconds: Int? = nil) {
        self.label = label
        self.structure = structure
        self.rounds = rounds
        self.exercises = exercises
        self.restBetweenSeconds = restBetweenSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        structure = try container.decodeIfPresent(BlockStructure.self, forKey: .structure) ?? .straight
        rounds = try container.decodeIfPresent(Int.self, forKey: .rounds) ?? 1
        exercises = try container.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
        restBetweenSeconds = try container.decodeIfPresent(Int.self, forKey: .restBetweenSeconds)
    }

    var exerciseCount: Int { exercises.count }
}
