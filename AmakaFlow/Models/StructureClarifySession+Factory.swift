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

    /// AMA-2326 I4 — land ingest draft blocks when they already carry structure.
    /// Returns nil when blocks are a single unlabeled flat list (fall back to suggest).
    static func fromIngestDraft(_ draft: SocialImportDraft) -> StructureClarifySession? {
        let models = draft.blocks.compactMap(Self.structureBlock(from:))
        guard !models.isEmpty else { return nil }

        let hasProvenance = models.contains {
            $0.structureSource == .inferred
                || $0.structureSource == .explicit
                || $0.structureSource == .userConfirmed
                || $0.structureSource == .userNote
        }
        let hasTypedStructure = models.contains {
            $0.type.canonical != .sets && $0.type.canonical != .regular
        }
        let hasMultiExerciseGroup = models.contains { $0.exercises.count >= 2 }
        guard hasProvenance || hasTypedStructure || (hasMultiExerciseGroup && models.count > 1) else {
            return nil
        }

        return StructureClarifySession(units: units(fromBlocks: models, pendingSourceOverride: nil))
    }

    private static func structureBlock(from block: SocialImportBlock) -> StructureBlockModel? {
        let exercises = block.exercises.map { exercise in
            StructureExerciseModel(
                name: exercise.name,
                sets: exercise.sets,
                reps: exercise.reps,
                restSec: exercise.restSeconds,
                distanceM: exercise.distanceMeters,
                notes: exercise.detailInstruction ?? exercise.notes
            )
        }
        guard !exercises.isEmpty else { return nil }

        let rawType = (block.type ?? "sets").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let type: StructureBlockType = {
            switch rawType {
            case "for_time", "for-time": return .forTime
            case "cool-down", "cooldown", "cool_down": return .sets
            default: return StructureBlockType(rawValue: rawType) ?? .sets
            }
        }()
        let sourceRaw = block.structureSource?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let source = sourceRaw.flatMap(StructureSource.init(rawValue:)) ?? .unknown
        let label: String? = {
            if rawType == "cool-down" || rawType == "cooldown" || rawType == "cool_down" {
                return block.label ?? "Cool Down"
            }
            return block.label
        }()

        return StructureBlockModel(
            type: type,
            label: label,
            rounds: block.rounds,
            restSec: block.restSec,
            exercises: exercises,
            structureSource: source
        )
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
                && (block.label == nil || block.label?.isEmpty == true)

            if isFlatSets && source != .userNote {
                return exercises.map { .row(StructureClarifyRow(exercise: $0)) }
            }

            let status: StructureClarifyStatus = {
                switch source {
                case .userConfirmed, .explicit, .userAdded, .enrichmentDefault:
                    // AMA-2326 — EXPLICIT ships committed by default (Confirm optional).
                    // AMA-2336 — user_added / enrichment_default are committed (standing consent).
                    return .confirmed
                case .userNote, .inferred, .unknown:
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
