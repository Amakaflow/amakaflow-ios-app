//
//  ActualsGhostFeed.swift
//  AmakaFlow
//
//  AMA-2387: editor ghosts prefer last verified actual over prescription.
//

import Foundation

struct ActualsGhostPrescription: Equatable {
    var sets: Int?
    var reps: Int?
    var weightKg: Double?
}

struct ActualsGhostActual: Equatable {
    var sets: Int
    var reps: Int
    var weightKg: Double?
}

enum ActualsGhostSource: String, Equatable, Codable {
    case lastActual
    case prescription
}

struct ActualsGhostResolved: Equatable {
    var sets: Int?
    var reps: Int?
    var weightKg: Double?
    var source: ActualsGhostSource

    var showsLastTime: Bool { source == .lastActual }
}

/// Looks up the latest verified actual for an exercise key (slug or name).
protocol ActualsGhostLookingUp: AnyObject {
    func latestActual(exerciseKey: String) throws -> ActualsGhostActual?
}

enum ActualsGhostFeed {
    /// Last actual wins when present; otherwise prescription values unchanged.
    static func resolve(
        prescription: ActualsGhostPrescription,
        lastActual: ActualsGhostActual?
    ) -> ActualsGhostResolved {
        guard let lastActual else {
            return ActualsGhostResolved(
                sets: prescription.sets,
                reps: prescription.reps,
                weightKg: prescription.weightKg,
                source: .prescription
            )
        }
        return ActualsGhostResolved(
            sets: lastActual.sets,
            reps: lastActual.reps,
            weightKg: lastActual.weightKg ?? prescription.weightKg,
            source: .lastActual
        )
    }

    /// Stable key for matching saved actuals to editor exercises.
    static func exerciseKey(forName name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "_", options: .regularExpression)
    }

    static func apply(to draft: inout DDEditorExerciseDraft, lastActual: ActualsGhostActual?) {
        let resolved = resolve(
            prescription: ActualsGhostPrescription(
                sets: draft.sets,
                reps: draft.reps,
                weightKg: draft.weightKg
            ),
            lastActual: lastActual
        )
        draft.sets = resolved.sets
        draft.reps = resolved.reps
        draft.weightKg = resolved.weightKg
        draft.showsLastTime = resolved.showsLastTime
    }

    static func applyGhosts(
        to blocks: inout [DDEditorBlockDraft],
        lookup: ActualsGhostLookingUp
    ) {
        for blockIndex in blocks.indices {
            for exerciseIndex in blocks[blockIndex].exercises.indices {
                let name = blocks[blockIndex].exercises[exerciseIndex].name
                let key = exerciseKey(forName: name)
                let last = try? lookup.latestActual(exerciseKey: key)
                apply(to: &blocks[blockIndex].exercises[exerciseIndex], lastActual: last)
            }
        }
    }
}
