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

    init(
        id: String,
        name: String,
        planned: ExerciseActualPlanned,
        confirmation: ExerciseActualConfirmation? = nil,
        actualSets: Int? = nil,
        actualReps: Int? = nil,
        actualWeightKg: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.planned = planned
        self.confirmation = confirmation
        self.actualSets = actualSets ?? planned.sets
        self.actualReps = actualReps ?? planned.reps
        self.actualWeightKg = actualWeightKg ?? planned.weightKg
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
