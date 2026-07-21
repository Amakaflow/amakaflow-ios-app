//
//  StructureClarifySession+Factory.swift
//  AmakaFlow
//
//  AMA-2305 — session factories from suggest / apply payloads.
//

import Foundation

extension StructureClarifySession {
    /// Build session from BFF suggest result (suggestions as pending groups; curls stay flat).
    static func fromSuggest(
        _ result: StructureSuggestResult,
        fallbackExercises: [StructureExerciseModel] = []
    ) -> StructureClarifySession {
        let exercises = result.exercises.isEmpty ? fallbackExercises : result.exercises
        guard !exercises.isEmpty else {
            return StructureClarifySession()
        }

        // Prefer pre-built blocks when backend already materialised suggestions as blocks
        // with inferred/explicit provenance (still pending confirmation).
        if !result.blocks.isEmpty,
           result.blocks.contains(where: { $0.structureSource == .inferred || $0.structureSource == .explicit }) {
            return StructureClarifySession(units: units(fromBlocks: result.blocks, pendingSourceOverride: nil))
        }

        var claimed = Set<Int>()
        var units: [StructureClarifyUnit] = []
        let suggestions = result.suggestions.sorted { lhs, rhs in
            (lhs.exerciseIndices.min() ?? Int.max) < (rhs.exerciseIndices.min() ?? Int.max)
        }

        var cursor = 0
        while cursor < exercises.count {
            if claimed.contains(cursor) {
                cursor += 1
                continue
            }

            if let suggestion = suggestions.first(where: { sug in
                guard let first = sug.exerciseIndices.min() else { return false }
                return first == cursor && sug.exerciseIndices.allSatisfy { !claimed.contains($0) }
            }) {
                let indices = suggestion.exerciseIndices.sorted()
                let members: [StructureClarifyExercise] = indices.compactMap { idx in
                    guard exercises.indices.contains(idx) else { return nil }
                    claimed.insert(idx)
                    let model = exercises[idx]
                    return StructureClarifyExercise(
                        name: model.name,
                        summary: StructureClarifyExercise.summary(for: model),
                        sets: model.sets,
                        reps: model.reps,
                        restSec: model.restSec,
                        distanceM: model.distanceM,
                        notes: model.notes
                    )
                }
                if members.count >= 1 {
                    let label = suggestion.label
                        ?? members.map(\.name).joined(separator: " + ")
                    units.append(
                        .group(
                            StructureClarifyGroup(
                                type: suggestion.type,
                                label: label,
                                rounds: suggestion.rounds,
                                restSec: suggestion.restSec,
                                exercises: members,
                                status: .pending,
                                structureSource: suggestion.structureSource
                            )
                        )
                    )
                }
                cursor += 1
                continue
            }

            let model = exercises[cursor]
            claimed.insert(cursor)
            units.append(
                .row(
                    StructureClarifyRow(
                        exercise: StructureClarifyExercise(
                            name: model.name,
                            summary: StructureClarifyExercise.summary(for: model),
                            sets: model.sets,
                            reps: model.reps,
                            restSec: model.restSec,
                            distanceM: model.distanceM,
                            notes: model.notes
                        )
                    )
                )
            )
            cursor += 1
        }

        return StructureClarifySession(units: units)
    }

    /// Build from apply response — noted groups stay pending with `user_note` provenance.
    static func fromAppliedBlocks(_ blocks: [StructureBlockModel]) -> StructureClarifySession {
        StructureClarifySession(units: units(fromBlocks: blocks, pendingSourceOverride: nil))
    }

    static func units(
        fromBlocks blocks: [StructureBlockModel],
        pendingSourceOverride: StructureSource?
    ) -> [StructureClarifyUnit] {
        blocks.flatMap { block -> [StructureClarifyUnit] in
            let exercises = block.exercises.map { model in
                StructureClarifyExercise(
                    name: model.name,
                    summary: StructureClarifyExercise.summary(for: model),
                    sets: model.sets,
                    reps: model.reps,
                    restSec: model.restSec,
                    distanceM: model.distanceM,
                    notes: model.notes
                )
            }
            guard !exercises.isEmpty else { return [] }

            let source = pendingSourceOverride ?? block.structureSource
            let isFlatSets = block.type.canonical == .sets && exercises.count == 1
                && (source == .unknown || source == .userConfirmed)

            if isFlatSets && source != .userNote {
                return exercises.map { .row(StructureClarifyRow(exercise: $0)) }
            }

            let status: StructureClarifyStatus = {
                switch source {
                case .userConfirmed:
                    return .confirmed
                case .userNote, .inferred, .explicit, .unknown:
                    return .pending
                }
            }()

            // Flat user_confirmed from leave-flat should stay rows when saving again —
            // but for display after leave-flat we usually dismiss. Treat multi-exercise
            // or typed blocks as groups.
            if block.type.canonical == .sets && exercises.count == 1 && source == .userConfirmed {
                return exercises.map { .row(StructureClarifyRow(exercise: $0)) }
            }

            return [
                .group(
                    StructureClarifyGroup(
                        type: block.type,
                        label: block.label ?? exercises.map(\.name).joined(separator: " + "),
                        rounds: block.rounds,
                        restSec: block.restSec,
                        exercises: exercises,
                        status: status,
                        structureSource: source == .userConfirmed && status == .pending
                            ? .inferred
                            : source
                    )
                )
            ]
        }
    }
}
