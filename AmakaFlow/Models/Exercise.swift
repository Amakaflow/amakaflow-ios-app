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
    /// Target muscles / focus from post or mapper (e.g. "Quads · Glutes").
    let focus: String?
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
        case durationSeconds, durationSec
        case load
        case restSeconds, distance, notes
        case focus, muscleGroup, muscleGroups
        case weight, weightUnit
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
        focus: String? = nil,
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
        self.focus = focus
        self.supersetGroup = supersetGroup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID().uuidString
        self.name = try container.decode(String.self, forKey: .name)
        self.canonicalName = try container.decodeIfPresent(String.self, forKey: .canonicalName)
        self.sets = try container.decodeIfPresent(Int.self, forKey: .sets)
        if let repsString = try? container.decode(String.self, forKey: .reps) {
            self.reps = repsString
        } else if let repsInt = try? container.decode(Int.self, forKey: .reps) {
            self.reps = String(repsInt)
        } else {
            self.reps = nil
        }
        self.durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
            ?? (try? container.decodeIfPresent(Int.self, forKey: .durationSec))
        if let decodedLoad = try container.decodeIfPresent(ExerciseLoad.self, forKey: .load) {
            self.load = decodedLoad
        } else if let weight = try container.decodeIfPresent(Double.self, forKey: .weight) {
            let unit = try container.decodeIfPresent(String.self, forKey: .weightUnit) ?? "kg"
            self.load = ExerciseLoad(value: weight, unit: unit)
        } else {
            self.load = nil
        }
        self.restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        self.distance = try container.decodeIfPresent(Double.self, forKey: .distance)
        var decodedNotes = try container.decodeIfPresent(String.self, forKey: .notes)
        var decodedFocus = Self.decodeFocus(from: container)
        if decodedFocus == nil,
           let notes = decodedNotes,
           Self.looksLikeMuscleFocus(notes) {
            decodedFocus = Self.formatFocusLabel(notes)
            decodedNotes = nil
        }
        self.notes = decodedNotes
        self.focus = decodedFocus
        self.supersetGroup = try container.decodeIfPresent(Int.self, forKey: .supersetGroup)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(canonicalName, forKey: .canonicalName)
        try container.encodeIfPresent(sets, forKey: .sets)
        try container.encodeIfPresent(reps, forKey: .reps)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(load, forKey: .load)
        try container.encodeIfPresent(restSeconds, forKey: .restSeconds)
        try container.encodeIfPresent(distance, forKey: .distance)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(focus, forKey: .focus)
        try container.encodeIfPresent(supersetGroup, forKey: .supersetGroup)
    }

    private static func decodeFocus(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let explicit = try? container.decode(String.self, forKey: .focus),
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return formatFocusLabel(explicit)
        }
        if let muscleGroup = try? container.decode(String.self, forKey: .muscleGroup),
           !muscleGroup.isEmpty {
            return formatFocusLabel(muscleGroup)
        }
        if let groups = try? container.decode([String].self, forKey: .muscleGroups), !groups.isEmpty {
            return groups.map(formatFocusLabel).joined(separator: " · ")
        }
        return nil
    }

    static func looksLikeMuscleFocus(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let keywords = [
            "quad", "glute", "hamstring", "chest", "back", "shoulder", "bicep", "tricep",
            "core", "abs", "lat", "hip", "calve", "full body", "aerobic", "legs"
        ]
        return keywords.contains { lowered.contains($0) }
    }

    private static func formatFocusLabel(_ raw: String) -> String {
        raw.split(separator: "·").map { part in
            part.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }.joined(separator: " · ")
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
