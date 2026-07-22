//
//  EditorV2Session+Persistence.swift
//  AmakaFlow
//
//  AMA-2307 — seed from DDEditor / Workout and export blocks + intervals.
//

import Foundation

extension EditorV2Session {
    /// Build session from legacy seed blocks (edit / import / new).
    static func from(mode: DDEditorMode, workout: Workout?) -> EditorV2Session {
        let seed = DDEditorSeed.initialState(mode: mode, workout: workout)
        return from(title: seed.title, blocks: seed.blocks)
    }

    static func from(title: String, blocks: [DDEditorBlockDraft]) -> EditorV2Session {
        var groups: [String: EditorV2Group] = [:]
        var exercises: [EditorV2Exercise] = []

        for block in blocks {
            if let groupType = EditorV2GroupType.from(dd: block.structure) {
                let key = block.id
                let capMinutes: Int? = {
                    guard let seconds = block.timeCapSeconds else { return nil }
                    return max(1, seconds / 60)
                }()
                groups[key] = EditorV2Group(
                    id: key,
                    type: groupType,
                    name: block.label,
                    config: EditorV2GroupConfig(
                        rounds: block.rounds,
                        restSeconds: block.restBetweenRoundsSeconds,
                        capMinutes: capMinutes
                    ),
                    structureSource: .userConfirmed
                )
                for exercise in block.exercises {
                    exercises.append(exercise.asEditorV2(groupKey: key))
                }
            } else {
                // Straight sets / cooldown → flat cards (no structure pill).
                for exercise in block.exercises {
                    exercises.append(exercise.asEditorV2(groupKey: nil))
                }
            }
        }

        return EditorV2Session(title: title, groups: groups, exercises: exercises)
    }

    /// Round-trip ADR-017 blocks for WorkoutSaveRequest (preserve structure_source).
    func toSocialImportBlocks() -> [SocialImportBlock] {
        var blocks: [SocialImportBlock] = []
        var flatBuffer: [SocialImportExercise] = []

        func flushFlat() {
            guard !flatBuffer.isEmpty else { return }
            blocks.append(
                SocialImportBlock(
                    label: nil,
                    rounds: 1,
                    exercises: flatBuffer,
                    type: StructureBlockType.sets.rawValue,
                    restSec: nil,
                    structureSource: StructureSource.unknown.rawValue
                )
            )
            flatBuffer = []
        }

        for run in runs {
            if let key = run.groupKey, let group = groups[key] {
                flushFlat()
                let restSec: Int? = {
                    switch group.type {
                    case .superset, .circuit, .warmup:
                        return group.config.restSeconds
                    case .tabata:
                        return group.config.restSeconds
                    case .emom, .amrap, .fortime:
                        return nil
                    }
                }()
                let rounds: Int = {
                    switch group.type {
                    case .amrap, .fortime:
                        return group.config.capMinutes ?? 1
                    default:
                        return group.config.rounds ?? 1
                    }
                }()
                blocks.append(
                    SocialImportBlock(
                        label: group.name,
                        rounds: max(1, rounds),
                        exercises: run.exercises.map(\.asSocialImportExercise),
                        type: group.type.structureBlockType.rawValue,
                        restSec: restSec,
                        structureSource: group.structureSource.rawValue
                    )
                )
            } else {
                flatBuffer.append(contentsOf: run.exercises.map(\.asSocialImportExercise))
            }
        }
        flushFlat()
        return blocks
    }

    func toSaveIntervals() -> [WorkoutSaveInterval] {
        exercises.map { exercise in
            let load = exercise.weightKg.map { weight in
                weight.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(weight)) kg"
                    : String(format: "%.1f kg", weight)
            }
            if let meters = exercise.distanceMeters, meters > 0 {
                return WorkoutSaveInterval(
                    type: "distance",
                    name: exercise.name,
                    meters: meters,
                    restSeconds: exercise.restSeconds,
                    load: load
                )
            }
            return WorkoutSaveInterval(
                type: "reps",
                name: exercise.name,
                sets: exercise.sets ?? 1,
                reps: exercise.reps ?? 10,
                restSeconds: exercise.restSeconds ?? 60,
                load: load
            )
        }
    }
}

private extension DDEditorExerciseDraft {
    func asEditorV2(groupKey: String?) -> EditorV2Exercise {
        EditorV2Exercise(
            id: id,
            name: name,
            sets: sets,
            reps: reps,
            distanceMeters: distanceMeters,
            weightKg: weightKg,
            restSeconds: restSeconds,
            groupKey: groupKey,
            swapMessage: swapMessage,
            swapReplacementName: swapReplacementName
        )
    }
}

private extension EditorV2Exercise {
    var asSocialImportExercise: SocialImportExercise {
        SocialImportExercise(
            name: name,
            sets: sets,
            reps: reps,
            distanceMeters: distanceMeters,
            load: weightKg.map { weight in
                weight.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(weight)) kg"
                    : String(format: "%.1f kg", weight)
            }
        )
    }
}
