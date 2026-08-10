//
//  ExerciseActual.swift
//  AmakaFlow
//
//  AMA-2387: per-exercise actuals for fill-in (planned vs done).
//

import Foundation

enum ExerciseActualConfirmation: String, Equatable, Codable {
    case asPlanned
    case adjusted
}

struct ExerciseActualPlanned: Equatable, Codable {
    var sets: Int
    var reps: Int
    var weightKg: Double?
    /// Freeform planned note (e.g. "SLOW", "2×20 KG") when not pure sets×reps×kg.
    var note: String?

    var displayLine: String {
        if let note, !note.isEmpty, weightKg == nil {
            // Timed / distance notes: "6 × 3:00" reads as rounds × work, not "6 × 1 · 3:00".
            // Single pass (sets ≤ 1) shows just the clock / distance.
            if reps == 1 {
                return sets <= 1 ? note : "\(sets) × \(note)"
            }
            return "\(sets) × \(reps) · \(note)"
        }
        if let kilograms = weightKg {
            let kgText = kilograms == floor(kilograms) ? "\(Int(kilograms))" : String(format: "%.1f", kilograms)
            return "\(sets) × \(reps) · \(kgText) KG"
        }
        return "\(sets) × \(reps)"
    }
}

struct ExerciseActual: Identifiable, Equatable, Codable {
    /// Stable slug for a11y + persistence (e.g. "back_squat").
    let id: String
    let name: String
    let planned: ExerciseActualPlanned
    var confirmation: ExerciseActualConfirmation?
    var actualSets: Int
    var actualReps: Int
    var actualWeightKg: Double?
    /// Display header for the structure band (e.g. `TRI-SET · 3 ROUNDS`), shared with Strava.
    var structureHeader: String?
    /// Contiguous group index from the Library/editor blocks.
    var structureBlockIndex: Int?

    init(
        id: String,
        name: String,
        planned: ExerciseActualPlanned,
        confirmation: ExerciseActualConfirmation? = nil,
        actualSets: Int? = nil,
        actualReps: Int? = nil,
        actualWeightKg: Double? = nil,
        structureHeader: String? = nil,
        structureBlockIndex: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.planned = planned
        self.confirmation = confirmation
        self.actualSets = actualSets ?? planned.sets
        self.actualReps = actualReps ?? planned.reps
        self.actualWeightKg = actualWeightKg ?? planned.weightKg
        self.structureHeader = structureHeader
        self.structureBlockIndex = structureBlockIndex
    }

    var isConfirmed: Bool { confirmation != nil }

    var accessibilityRowID: String { "af_actuals_row_\(id)" }
    var accessibilityAsPlannedID: String { "af_actuals_row_\(id)_asplanned" }
    var accessibilityAdjustID: String { "af_actuals_row_\(id)_adjust" }
}

struct ActualsFillInSession: Equatable {
    let id: String
    let title: String
    /// Mono subtitle, e.g. "LOWER BODY — POSTERIOR · MON 17:20".
    let subtitle: String
    var exercises: [ExerciseActual]
    var rpe: Int?
    var verified: Bool
    /// AMA-2396: originating Strava activity id — non-nil only for sessions that
    /// came from a synced Strava activity (drives write-back eligibility).
    var stravaActivityId: String?
    /// Raw Strava sport/type — required before write-back so skip rules can fire.
    var stravaActivityType: String?
    /// Current Strava description before our write (skipDescribed / preserve-append).
    var stravaCurrentDescription: String?
    var stravaRecordingApp: String?
    var stravaIsRace: Bool
    /// Full Library/structure text for Strava (rounds + every step + emoji).
    var structureBody: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        exercises: [ExerciseActual],
        rpe: Int? = nil,
        verified: Bool,
        stravaActivityId: String? = nil,
        stravaActivityType: String? = nil,
        stravaCurrentDescription: String? = nil,
        stravaRecordingApp: String? = nil,
        stravaIsRace: Bool = false,
        structureBody: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.exercises = exercises
        self.rpe = rpe
        self.verified = verified
        self.stravaActivityId = stravaActivityId
        self.stravaActivityType = stravaActivityType
        self.stravaCurrentDescription = stravaCurrentDescription
        self.stravaRecordingApp = stravaRecordingApp
        self.stravaIsRace = stravaIsRace
        self.structureBody = structureBody
        // Recover TRI-SET / SUPERSET bands for sessions saved before per-row structure.
        self.exercises = StravaWorkoutStructureText.stampingStructureHeaders(
            onto: exercises,
            from: structureBody
        )
    }

    /// Group consecutive rows that share a structure band (for fill-in / verified UI).
    var structureSections: [ActualsStructureSection] {
        ActualsStructureSection.sections(from: exercises)
    }

    /// Write-back must not run with fabricated skip inputs.
    var canEvaluateStravaWriteBack: Bool {
        stravaActivityId != nil && stravaActivityType != nil
    }

    /// Prefer the stored Library structure; fall back to emoji-decorated rows.
    var stravaStructureBody: String {
        if let structureBody {
            let trimmed = structureBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return StravaWorkoutStructureText.structureBody(fromExercises: exercises)
    }

    var confirmedCount: Int {
        exercises.filter(\.isConfirmed).count
    }

    var unconfirmedCount: Int {
        exercises.count - confirmedCount
    }

    /// Design-handoff sample (screens-actuals.jsx panel 4).
    static func lowerBodyPosteriorSample(id: String = "fill_in_lower_posterior") -> ActualsFillInSession {
        ActualsFillInSession(
            id: id,
            title: "Lower body — posterior",
            subtitle: "LOWER BODY — POSTERIOR · MON 17:20",
            exercises: [
                ExerciseActual(
                    id: "back_squat",
                    name: "Back squat",
                    planned: ExerciseActualPlanned(sets: 3, reps: 5, weightKg: 85)
                ),
                ExerciseActual(
                    id: "rdl",
                    name: "Romanian deadlift",
                    planned: ExerciseActualPlanned(sets: 3, reps: 8, weightKg: 70)
                ),
                ExerciseActual(
                    id: "split_squat",
                    name: "Split squat",
                    planned: ExerciseActualPlanned(sets: 2, reps: 10, note: "2×20 KG")
                ),
                ExerciseActual(
                    id: "nordic_curl",
                    name: "Nordic curl",
                    planned: ExerciseActualPlanned(sets: 2, reps: 6, note: "SLOW")
                )
            ],
            rpe: nil,
            verified: false
        )
    }
}

struct ActualsStructureSection: Identifiable, Equatable {
    let id: String
    let header: String?
    let exercises: [ExerciseActual]

    static func sections(from exercises: [ExerciseActual]) -> [ActualsStructureSection] {
        var result: [ActualsStructureSection] = []
        var buffer: [ExerciseActual] = []
        var currentHeader: String?
        var currentBlock: Int?

        func flush() {
            guard !buffer.isEmpty else { return }
            let id = [
                currentBlock.map(String.init) ?? "flat",
                String(result.count),
                buffer[0].id
            ].joined(separator: "_")
            result.append(
                ActualsStructureSection(id: id, header: currentHeader, exercises: buffer)
            )
            buffer = []
        }

        for exercise in exercises {
            let header = exercise.structureHeader
            let block = exercise.structureBlockIndex
            if buffer.isEmpty {
                currentHeader = header
                currentBlock = block
                buffer.append(exercise)
                continue
            }
            let sameBlock = block != nil && block == currentBlock
            let sameHeader = header == currentHeader
            if sameBlock || (block == nil && currentBlock == nil && sameHeader) {
                buffer.append(exercise)
            } else {
                flush()
                currentHeader = header
                currentBlock = block
                buffer.append(exercise)
            }
        }
        flush()
        return result
    }
}
