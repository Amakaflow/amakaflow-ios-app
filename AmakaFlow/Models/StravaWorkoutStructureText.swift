//
//  StravaWorkoutStructureText.swift
//  AmakaFlow
//
//  AMA-2396: plain-text workout structure for Strava descriptions —
//  rounds, every step, and equipment emoji decoration.
//

import Foundation

enum StravaWorkoutStructureText {
    /// Full Library workout → Strava structure body (no ownership signature).
    static func structureBody(from workout: Workout) -> String {
        var blocks: [String] = []
        for block in workout.blocks where !block.exercises.isEmpty {
            if let section = formatBlock(block) {
                blocks.append(section)
            }
        }
        if blocks.isEmpty {
            return workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return blocks.joined(separator: "\n\n")
    }

    /// Seed fill-in rows from the matched Library workout (timed steps keep M:SS notes).
    static func fillInExercises(from workout: Workout) -> [ExerciseActual] {
        var rows: [ExerciseActual] = []
        var seen = Set<String>()
        for (blockIndex, block) in workout.blocks.enumerated() {
            for (exerciseIndex, exercise) in block.exercises.enumerated() {
                let base = slug(exercise.name)
                var key = "\(base)_\(blockIndex)_\(exerciseIndex)"
                if seen.contains(key) {
                    key = "\(key)_\(rows.count)"
                }
                seen.insert(key)
                rows.append(
                    ExerciseActual(
                        id: key,
                        name: exercise.name,
                        planned: planned(from: exercise)
                    )
                )
            }
        }
        return Array(rows.prefix(24))
    }

    /// Fallback when we only have fill-in rows (no stored structure body).
    static func structureBody(
        fromExercises exercises: [ExerciseActual],
        header: String? = nil
    ) -> String {
        var lines: [String] = []
        if let header {
            let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        for exercise in exercises {
            let prescription: String = {
                if let note = exercise.planned.note, !note.isEmpty,
                   exercise.planned.weightKg == nil {
                    if exercise.planned.sets > 0 {
                        return "\(exercise.planned.sets) × \(note)"
                    }
                    return note
                }
                return exercise.planned.displayLine
            }()
            lines.append("\(emoji(forExerciseName: exercise.name)) \(exercise.name) — \(prescription)")
        }
        return lines.joined(separator: "\n")
    }

    static func emoji(forExerciseName name: String) -> String {
        let symbol = WorkoutSportHonesty.systemImage(forExerciseName: name)
        switch symbol {
        case "bicycle": return "🚴"
        case "figure.skiing.crosscountry": return "⛷️"
        case "figure.rower": return "🚣"
        case "figure.run": return "🏃"
        case "figure.elliptical": return "🔄"
        case "figure.stair.stepper": return "🪜"
        case "figure.jumprope": return "🪢"
        case "figure.pool.swim": return "🏊"
        case "figure.flexibility": return "🧘"
        default: return "🏋️"
        }
    }

    // MARK: - Private

    private static func formatBlock(_ block: Block) -> String? {
        guard !block.exercises.isEmpty else { return nil }
        var lines: [String] = []
        let header = blockHeader(block)
        if !header.isEmpty { lines.append(header) }
        for exercise in block.exercises {
            let detail = PrescriptionFormatter.lineForDetailList(from: exercise)
            let prescription = detail.isEmpty ? "as built" : detail
            lines.append("\(emoji(forExerciseName: exercise.name)) \(exercise.name) — \(prescription)")
        }
        return lines.joined(separator: "\n")
    }

    private static func blockHeader(_ block: Block) -> String {
        let rounds = max(1, block.rounds)
        let structureName = block.structure.displayName.uppercased()
        if let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty,
           !isGenericBlockLabel(label) {
            if rounds > 1 {
                return "\(label.uppercased()) · \(rounds) ROUNDS"
            }
            return label.uppercased()
        }
        switch block.structure {
        case .circuit, .timedCircuit, .amrap, .emom, .tabata:
            if rounds > 1 {
                return "\(structureName) · \(rounds) ROUNDS"
            }
            return structureName
        case .superset:
            return rounds > 1 ? "SUPERSET · \(rounds) ROUNDS" : "SUPERSET"
        case .straight:
            return rounds > 1 ? "\(rounds) ROUNDS" : ""
        }
    }

    private static func isGenericBlockLabel(_ label: String) -> Bool {
        let lowered = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "main", "main block", "block", "work", "workout",
            "circuit", "amrap", "emom", "tabata", "for time", "for-time"
        ].contains(lowered)
    }

    private static func planned(from exercise: Exercise) -> ExerciseActualPlanned {
        let sets = max(1, exercise.sets ?? 1)
        if let seconds = exercise.durationSeconds, seconds > 0 {
            return ExerciseActualPlanned(
                sets: sets,
                reps: 1,
                note: formatClock(seconds)
            )
        }
        if let meters = exercise.distance, meters > 0 {
            let distanceText = meters >= 1000
                ? String(format: "%.1f km", meters / 1000)
                : "\(Int(meters.rounded())) m"
            return ExerciseActualPlanned(sets: sets, reps: 1, note: distanceText)
        }
        if let load = exercise.load {
            let reps = Int(exercise.reps ?? "") ?? 1
            let unit = load.unit.lowercased()
            let kilograms: Double? = (unit == "kg" || unit == "kilograms") ? load.value : nil
            let note: String? = kilograms == nil
                ? PrescriptionFormatter.lineForDetailList(from: exercise)
                : nil
            return ExerciseActualPlanned(
                sets: sets,
                reps: max(1, reps),
                weightKg: kilograms,
                note: note
            )
        }
        if let reps = Int(exercise.reps ?? ""), reps > 0 {
            return ExerciseActualPlanned(sets: sets, reps: reps)
        }
        let detail = PrescriptionFormatter.lineForDetailList(from: exercise)
        if !detail.isEmpty {
            return ExerciseActualPlanned(sets: sets, reps: 1, note: detail)
        }
        return ExerciseActualPlanned(sets: sets, reps: 1, note: "AS BUILT")
    }

    private static func formatClock(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let rem = seconds % 60
        return String(format: "%d:%02d", minutes, rem)
    }

    private static func slug(_ name: String) -> String {
        let raw = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return raw.isEmpty ? "move" : raw
    }
}
