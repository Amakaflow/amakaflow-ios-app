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

    /// Split a reps string into plain integer reps or a structured range.
    static func splitPrescription(_ raw: String?) -> (reps: Int?, range: RepsRange?) {
        guard let raw else { return (nil, nil) }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (nil, nil) }
        if let value = Int(text), value != 0 { return (value, nil) }
        if let range = parse(text) { return (nil, range) }
        return (nil, nil)
    }

    static func isValidRangeText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^\d+\s*[–-]\s*\d+$"#) else {
            return false
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    static func fromRangeText(_ text: String, preservingQualifier: String? = nil) -> RepsRange? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidRangeText(trimmed), let parsed = parse(trimmed) else { return nil }
        return RepsRange(low: parsed.low, high: parsed.high, qualifier: preservingQualifier)
    }

    static func ingestDisplay(from value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let dict = value as? [String: Any],
           let low = dict["low"] as? Int,
           let high = dict["high"] as? Int {
            if low == high { return String(low) }
            var display = "\(low)-\(high)"
            if let qualifier = dict["qualifier"] as? String,
               !qualifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                display += " \(qualifier)"
            }
            return display
        }
        return nil
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

struct PrescriptionMetricInputs: Equatable, Sendable {
    var durationSeconds: Int?
    var distanceMeters: Int?
    var calories: Int?
    var plainReps: Int?
    var repsRange: RepsRange?
    var sets: Int?
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
            PrescriptionMetricInputs(
                durationSeconds: exercise.durationSeconds,
                distanceMeters: exercise.distance.map { Int($0.rounded()) },
                calories: nil,
                plainReps: plainReps,
                repsRange: repsRange,
                sets: exercise.sets
            )
        )

        if case .repsRange(let range, _) = primary, let qualifier = range.qualifier {
            if !secondary.contains(qualifier) {
                secondary.append(qualifier)
            }
        }

        return EffectivePrescription(primary: primary, secondary: secondary)
    }

    static func resolvePrimaryMetric(_ inputs: PrescriptionMetricInputs) -> PrescriptionPrimary {
        if let durationSeconds = inputs.durationSeconds {
            return .duration(seconds: durationSeconds, sets: inputs.sets)
        }
        if let distanceMeters = inputs.distanceMeters {
            return .distance(meters: distanceMeters, sets: inputs.sets)
        }
        if let calories = inputs.calories {
            return .calories(calories, sets: inputs.sets)
        }
        if let plainReps = inputs.plainReps {
            return .reps(plainReps, sets: inputs.sets)
        }
        if let repsRange = inputs.repsRange {
            return .repsRange(repsRange, sets: inputs.sets)
        }
        return .none(sets: inputs.sets)
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

    static func secondaryParts(
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
