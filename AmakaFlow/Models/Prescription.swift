import Foundation

enum ProvSource: String, Codable, Sendable {
    case explicit
    case inferred
    case user
}

struct RepsRange: Equatable, Codable, Sendable {
    var low: Int
    var high: Int
    var qualifier: String?

    var display: String { "\(low)-\(high)" }

    static func parse(_ raw: String?) -> RepsRange? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let pattern = #"^\s*(\d+)\s*(?:to|[–-])\s*(\d+)\s*(.*?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, options: [], range: range),
            let lowRange = Range(match.range(at: 1), in: text),
            let highRange = Range(match.range(at: 2), in: text),
            let low = Int(text[lowRange]),
            let high = Int(text[highRange])
        else {
            return nil
        }

        if low == high { return nil }

        var qualifier: String?
        if match.numberOfRanges > 3, let tailRange = Range(match.range(at: 3), in: text) {
            let tail = text[tailRange]
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: " ,;-")))
            if !tail.isEmpty {
                qualifier = String(tail)
            }
        }

        return RepsRange(low: low, high: high, qualifier: qualifier)
    }
}

enum PrescriptionPrimary: Equatable, Sendable {
    case duration(seconds: Int, sets: Int?)
    case distance(meters: Int, sets: Int?)
    case calories(Int, sets: Int?)
    case reps(Int, sets: Int?)
    case repsRange(RepsRange, sets: Int?)
    case none(sets: Int?)
}

struct EffectivePrescription: Equatable, Sendable {
    var primary: PrescriptionPrimary
    var secondary: [String]
}

enum PrescriptionFormatter {
    static func effective(from exercise: Exercise) -> EffectivePrescription {
        let plainReps = parsePlainReps(from: exercise.reps)
        let repsRange = RepsRange.parse(exercise.reps)
        var secondary = secondaryParts(
            load: exercise.load,
            notes: exercise.notes,
            restSeconds: exercise.restSeconds,
            rangeQualifier: repsRange?.qualifier
        )

        let primary = resolvePrimaryMetric(
            durationSeconds: exercise.durationSeconds,
            distanceMeters: exercise.distance.map { Int($0.rounded()) },
            calories: nil,
            plainReps: plainReps,
            repsRange: repsRange,
            sets: exercise.sets
        )

        if case .repsRange(let range, _) = primary, let qualifier = range.qualifier {
            if !secondary.contains(qualifier) {
                secondary.append(qualifier)
            }
        }

        return EffectivePrescription(primary: primary, secondary: secondary)
    }

    static func resolvePrimaryMetric(
        durationSeconds: Int?,
        distanceMeters: Int?,
        calories: Int?,
        plainReps: Int?,
        repsRange: RepsRange?,
        sets: Int?
    ) -> PrescriptionPrimary {
        if let durationSeconds {
            return .duration(seconds: durationSeconds, sets: sets)
        }
        if let distanceMeters {
            return .distance(meters: distanceMeters, sets: sets)
        }
        if let calories {
            return .calories(calories, sets: sets)
        }
        if let plainReps {
            return .reps(plainReps, sets: sets)
        }
        if let repsRange {
            return .repsRange(repsRange, sets: sets)
        }
        return .none(sets: sets)
    }

    static func line(_ prescription: EffectivePrescription) -> String {
        var parts: [String] = []
        if let primaryText = primaryLine(prescription.primary), !primaryText.isEmpty {
            parts.append(primaryText)
        }
        parts.append(contentsOf: prescription.secondary)
        return parts.joined(separator: " · ")
    }

    private static func parsePlainReps(from reps: String?) -> Int? {
        guard let reps else { return nil }
        let trimmed = reps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value != 0 else { return nil }
        return value
    }

    private static func secondaryParts(
        load: ExerciseLoad?,
        notes: String?,
        restSeconds: Int?,
        rangeQualifier: String?
    ) -> [String] {
        var parts: [String] = []

        if let loadText = formattedLoad(load) {
            parts.append(loadText)
        }

        if let notes {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               !Exercise.looksLikeMuscleFocus(trimmed),
               trimmed != rangeQualifier {
                parts.append(trimmed)
            }
        }

        if let restSeconds {
            parts.append("\(restSeconds)S REST")
        }

        return parts
    }

    private static func formattedLoad(_ load: ExerciseLoad?) -> String? {
        guard let load else { return nil }
        if load.unit == "bodyweight" { return "bodyweight" }
        if load.value > 0 {
            let valueText = load.value.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(load.value))
                : String(load.value)
            let unit = load.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            return unit.isEmpty ? valueText : "\(valueText) \(unit)"
        }
        let unit = load.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? nil : unit
    }

    private static func primaryLine(_ primary: PrescriptionPrimary) -> String? {
        switch primary {
        case .duration(let seconds, let sets):
            let metric = seconds >= 60 ? "\(seconds / 60) min" : "\(seconds) sec"
            return prefixedSets(sets, metric: metric)
        case .distance(let meters, let sets):
            let metric = meters >= 1000
                ? String(format: "%.1f km", Double(meters) / 1000)
                : "\(meters) m"
            return prefixedSets(sets, metric: metric)
        case .calories(let calories, let sets):
            return prefixedSets(sets, metric: "\(calories) CAL")
        case .reps(let reps, let sets):
            return prefixedSets(sets, metric: "\(reps)")
        case .repsRange(let range, let sets):
            return prefixedSets(sets, metric: range.display)
        case .none(let sets):
            if let sets { return "\(sets) SETS" }
            return nil
        }
    }

    private static func prefixedSets(_ sets: Int?, metric: String) -> String {
        if let sets, sets > 0 {
            return "\(sets) × \(metric)"
        }
        return metric
    }
}
