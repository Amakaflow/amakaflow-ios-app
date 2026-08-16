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
        // AMA-2438 P3: reload from SocialImportBlock payload, not DDEditorBlockDraft
        // Convert DDEditorBlockDraft → SocialImportBlock for codec
        let socialBlocks = blocks.map { block -> SocialImportBlock in
            let structureType: String = {
                if let groupType = EditorV2GroupType.from(dd: block.structure) {
                    return groupType.structureBlockType.rawValue
                }
                return StructureBlockType.sets.rawValue
            }()
            
            return SocialImportBlock(
                label: block.label,
                rounds: block.rounds,
                exercises: block.exercises.map { $0.asSocialImportExercise },
                type: structureType,
                restSec: block.restBetweenRoundsSeconds,
                timeCapSec: block.timeCapSeconds,
                structureSource: StructureSource.userConfirmed.rawValue,
                enrichmentKind: nil
            )
        }
        
        // Use P3 D4 codec
        return EditorV2Session.decodeFromBlocks(title: title, blocks: socialBlocks)
    }

    /// Round-trip ADR-017 blocks for WorkoutSaveRequest (preserve structure_source).
    func toSocialImportBlocks() -> [SocialImportBlock] { // swiftlint:disable:this cyclomatic_complexity
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
                    structureSource: StructureSource.userConfirmed.rawValue
                )
            )
            flatBuffer = []
        }

        for row in order {
            switch row {
            case .group(let key):
                guard let group = groups[key] else { continue }
                let members = group.memberIDs.compactMap { exercises[$0] }
                flushFlat()
                let restSec: Int? = {
                    switch group.type {
                    case .superset, .circuit, .timedCircuit, .warmup, .cooldown:
                        return group.config.restSeconds
                    case .tabata:
                        return group.config.restSeconds
                    case .emom, .amrap, .fortime:
                        return nil
                    }
                }()
                // AMRAP / For time: cap is duration, not round count. Stuffing
                // `capMinutes` into `rounds` made fill-in show "60 ROUNDS".
                let rounds: Int = {
                    switch group.type {
                    case .amrap, .fortime:
                        return 1
                    default:
                        return group.config.rounds ?? 1
                    }
                }()
                let timeCapSec: Int? = {
                    switch group.type {
                    case .amrap, .fortime:
                        guard let minutes = group.config.capMinutes, minutes > 0 else { return nil }
                        return minutes * 60
                    default:
                        return nil
                    }
                }()
                let label: String? = {
                    switch group.type {
                    case .amrap, .fortime:
                        return group.metaLine
                    case .superset:
                        // AMA-2438 D3: use derived display name
                        return group.displayName(memberCount: members.count)
                    default:
                        return group.name
                    }
                }()
                blocks.append(
                    SocialImportBlock(
                        label: label,
                        rounds: max(1, rounds),
                        exercises: members.map(\.asSocialImportExercise),
                        type: group.type.structureBlockType.rawValue,
                        restSec: restSec,
                        timeCapSec: timeCapSec,
                        structureSource: group.structureSource.rawValue,
                        enrichmentKind: group.enrichmentKind?.rawValue
                    )
                )
            case .loose(let id):
                guard let exercise = exercises[id] else { continue }
                flatBuffer.append(exercise.asSocialImportExercise)
            }
        }
        flushFlat()
        return blocks
    }

    func toSaveIntervals() -> [WorkoutSaveInterval] {
        // AMA-2438 D2: preserve order for intervals (dict iteration is undefined)
        var result: [WorkoutSaveInterval] = []
        for row in order {
            switch row {
            case .group(let key):
                guard let group = groups[key] else { continue }
                for memberID in group.memberIDs {
                    guard let exercise = exercises[memberID] else { continue }
                    result.append(PrescriptionFormatter.saveInterval(from: exercise))
                }
            case .loose(let id):
                guard let exercise = exercises[id] else { continue }
                result.append(PrescriptionFormatter.saveInterval(from: exercise))
            }
        }
        return result
    }
}

private extension DDEditorExerciseDraft {
    func asEditorV2(groupKey: String?) -> EditorV2Exercise {
        EditorV2Exercise(
            id: id,
            name: name,
            sets: sets,
            reps: reps,
            repsRange: repsRange,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            weightKg: weightKg,
            restSeconds: restSeconds,
            calories: calories,
            groupKey: groupKey,
            swapMessage: swapMessage,
            swapReplacementName: swapReplacementName
        )
    }
    
    var asSocialImportExercise: SocialImportExercise {
        SocialImportExercise(
            name: name,
            sets: sets,
            reps: reps,
            repsRange: repsRange?.display,
            seconds: durationSeconds,
            distanceMeters: distanceMeters,
            calories: calories,
            restSeconds: restSeconds
        )
    }
}

private extension EditorV2Exercise {
    /// AMA-2336 — mint `exercise_id` on the save payload when the row has none, so
    /// tombstones written later key off a stable id (`mintMissingExerciseIDs` keeps
    /// the session in step).
    var asSocialImportExercise: SocialImportExercise {
        var provenance: [String: String] = [:]
        for (key, value) in fieldProvenance {
            provenance[key] = value.rawValue
        }
        return SocialImportExercise(
            name: name,
            sets: sets,
            reps: reps,
            repsRange: repsRange?.display,
            seconds: durationSeconds,
            distanceMeters: distanceMeters,
            calories: calories,
            openGoal: openGoal,
            restSeconds: restSeconds,
            load: exportLoadString,
            fieldProvenance: provenance.isEmpty ? nil : provenance,
            exerciseId: exerciseId ?? WorkoutEnrichmentMutations.mintExerciseId(),
            warmupSets: warmupSets.isEmpty ? nil : warmupSets,
            restOpen: restOpen,
            structureSource: structureSource?.rawValue
        )
    }
}
