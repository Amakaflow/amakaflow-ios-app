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

    var id: String { "\(name)-\(sets ?? 0)-\(reps ?? "")" }

    enum CodingKeys: String, CodingKey {
        case name, canonicalName = "canonical_name", sets, reps
        case durationSeconds = "duration_seconds", load
        case restSeconds = "rest_seconds", distance, notes
        case supersetGroup = "superset_group"
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
