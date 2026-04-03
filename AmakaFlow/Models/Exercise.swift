import Foundation

struct ExerciseLoad: Codable, Hashable {
    let value: Double
    let unit: String
}

struct Exercise: Codable, Hashable, Identifiable {
    let name: String
    let canonicalName: String?
    let sets: Int?
    let reps: String?
    let durationSeconds: Int?
    let load: ExerciseLoad?
    let restSeconds: Int?
    let distance: Double?
    let notes: String?
    let supersetGroup: Int?

    /// Stable unique identity. Stored UUID avoids collisions when the same
    /// exercise appears multiple times in a block.
    let id: String

    // CodingKeys use default camelCase case names so they work correctly
    // with JSONDecoder's .convertFromSnakeCase strategy (which the app uses
    // everywhere). Explicit snake_case raw values would double-convert and break.
    // id is excluded — generated locally, not in API JSON.
    enum CodingKeys: String, CodingKey {
        case name, canonicalName, sets, reps
        case durationSeconds, load
        case restSeconds, distance, notes
        case supersetGroup
    }

    init(
        name: String,
        canonicalName: String?,
        sets: Int?,
        reps: String?,
        durationSeconds: Int?,
        load: ExerciseLoad?,
        restSeconds: Int?,
        distance: Double?,
        notes: String?,
        supersetGroup: Int?
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.canonicalName = canonicalName
        self.sets = sets
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.load = load
        self.restSeconds = restSeconds
        self.distance = distance
        self.notes = notes
        self.supersetGroup = supersetGroup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID().uuidString
        self.name = try container.decode(String.self, forKey: .name)
        self.canonicalName = try container.decodeIfPresent(String.self, forKey: .canonicalName)
        self.sets = try container.decodeIfPresent(Int.self, forKey: .sets)
        self.reps = try container.decodeIfPresent(String.self, forKey: .reps)
        self.durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        self.load = try container.decodeIfPresent(ExerciseLoad.self, forKey: .load)
        self.restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        self.distance = try container.decodeIfPresent(Double.self, forKey: .distance)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.supersetGroup = try container.decodeIfPresent(Int.self, forKey: .supersetGroup)
    }

    var formattedDetail: String {
        if let sets = sets, let reps = reps { return "\(sets)x\(reps)" }
        else if let reps = reps { return "\(reps) reps" }
        else if let duration = durationSeconds {
            return duration >= 60 ? "\(duration / 60) min" : "\(duration) sec"
        } else if let distance = distance {
            return distance >= 1000 ? String(format: "%.1f km", distance / 1000) : "\(Int(distance))m"
        }
        return ""
    }

    var formattedLoad: String? {
        guard let load = load else { return nil }
        if load.unit == "bodyweight" { return "BW" }
        let valStr = load.value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(load.value)) : String(load.value)
        return "@ \(valStr)\(load.unit)"
    }
}
