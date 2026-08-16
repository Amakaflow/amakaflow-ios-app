//
//  EditorV2StructureCodec.swift
//  AmakaFlow
//
//  AMA-2438 P3 — D4 round-trip codec for EditorV2Session ↔ SocialImportBlock.
//

import Foundation

// MARK: - Structure Codec (D4)

extension EditorV2Session {
    /// AMA-2438 P3 D4: Encode session to SocialImportBlock payload (save format).
    /// Law: decode(encode(s)) == normalize(s) for all valid sessions.
    func encodeToBlocks() -> [SocialImportBlock] {
        // Reuse existing toSocialImportBlocks which already handles P2 D2 model
        return toSocialImportBlocks()
    }
    
    /// AMA-2438 P3 D4: Decode SocialImportBlock payload to session (reload format).
    /// Preserves warm-up, cooldown, for-time + time caps.
    static func decodeFromBlocks(title: String, blocks: [SocialImportBlock]) -> EditorV2Session {
        var order: [EditorV2Row] = []
        var groups: [String: EditorV2Group] = [:]
        var exercises: [String: EditorV2Exercise] = [:]
        
        for block in blocks {
            // Determine if this is a structured group or loose exercises
            let structureType = StructureBlockType(rawValue: block.type ?? "") ?? .sets
            
            if structureType == .sets || structureType == .regular {
                // Straight sets - add as loose exercises
                for blockExercise in block.exercises {
                    let exercise = blockExercise.asEditorV2(groupKey: nil)
                    exercises[exercise.id] = exercise
                    order.append(.loose(exercise.id))
                }
            } else {
                // Structured block - create a group
                let key = UUID().uuidString
                var memberIDs: [String] = []
                
                for blockExercise in block.exercises {
                    let exercise = blockExercise.asEditorV2(groupKey: nil)
                    exercises[exercise.id] = exercise
                    memberIDs.append(exercise.id)
                }
                
                // Map StructureBlockType to EditorV2GroupType
                guard let groupType = mapBlockTypeToGroupType(structureType) else {
                    // Unknown type - treat as loose
                    for id in memberIDs {
                        order.append(.loose(id))
                    }
                    continue
                }
                
                let restSeconds: Int? = block.restSec
                let timeCapSec: Int? = block.timeCapSec
                let capMinutes: Int? = {
                    guard let seconds = timeCapSec, seconds > 0 else { return nil }
                    return max(1, seconds / 60)
                }()
                
                // Determine rounds (AMRAP/for-time use cap as duration, not round count)
                let rounds: Int = {
                    switch groupType {
                    case .amrap, .fortime:
                        1  // Don't use round count for these types
                    default:
                        max(1, block.rounds ?? 1)
                    }
                }()
                
                let config = EditorV2GroupConfig(
                    rounds: rounds,
                    restSeconds: restSeconds,
                    capMinutes: capMinutes,
                    workSeconds: nil
                )
                
                // D3: parse letter from label if present (e.g. "Superset A" → letter: "A")
                let (baseName, letter) = parseNameAndLetter(block.label, type: groupType)
                
                let group = EditorV2Group(
                    id: key,
                    type: groupType,
                    name: baseName ?? groupType.label,
                    letter: letter,
                    config: config,
                    memberIDs: memberIDs,
                    structureSource: StructureSource(rawValue: block.structureSource ?? "") ?? .userConfirmed,
                    enrichmentKind: block.enrichmentKind.flatMap { EnrichmentKind(rawValue: $0) }
                )
                
                groups[key] = group
                order.append(.group(key))
            }
        }
        
        return EditorV2Session(
            title: title,
            order: order,
            groups: groups,
            exercises: exercises,
            formatGroupKey: nil,
            enrichmentTombstones: [],
            enrichmentTombstonesDirty: false
        )
    }
    
    private static func mapBlockTypeToGroupType(_ type: StructureBlockType) -> EditorV2GroupType? {
        switch type {
        case .superset:
            return .superset
        case .circuit, .rounds:
            return .circuit
        case .timedCircuit:
            return .timedCircuit
        case .emom:
            return .emom
        case .amrap:
            return .amrap
        case .tabata:
            return .tabata
        case .forTime, .fortime:
            return .fortime
        case .warmup:
            return .warmup
        case .cooldown:
            return .cooldown
        case .sets, .regular, .unknown:
            return nil
        }
    }
    
    private static func parseNameAndLetter(_ label: String?, type: EditorV2GroupType) -> (String?, String?) {
        guard let label = label, type == .superset else { return (label, nil) }
        
        // Pattern: "Superset A", "Tri-set B", "Giant set C"
        let pattern = #"^(Superset|Tri-set|Giant set)\s+([A-Z])$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
           match.numberOfRanges == 3 {
            let baseRange = Range(match.range(at: 1), in: label)
            let letterRange = Range(match.range(at: 2), in: label)
            
            if let baseRange = baseRange, let letterRange = letterRange {
                let base = String(label[baseRange])
                let letter = String(label[letterRange])
                return (base, letter)
            }
        }
        
        // No match - return as-is
        return (label, nil)
    }
}

private extension SocialImportExercise {
    func asEditorV2(groupKey: String?) -> EditorV2Exercise {
        let repsRangeConverted = RepsRange.parse(repsRange)
        
        var provenance: [String: ProvSource] = [:]
        if let fieldProvenance = fieldProvenance {
            for (key, value) in fieldProvenance {
                if let source = ProvSource(rawValue: value) {
                    provenance[key] = source
                }
            }
        }
        
        let warmupSetsConverted = warmupSets ?? []
        
        return EditorV2Exercise(
            id: exerciseId ?? UUID().uuidString,
            name: name,
            sets: sets,
            reps: reps,
            repsRange: repsRangeConverted,
            durationSeconds: seconds,
            distanceMeters: distanceMeters,
            weightKg: nil,
            isBodyweight: false,
            restSeconds: restSeconds,
            calories: calories,
            openGoal: openGoal ?? false,
            groupKey: groupKey,
            swapMessage: nil,
            swapReplacementName: nil,
            fieldProvenance: provenance,
            exerciseId: exerciseId,
            warmupSets: warmupSetsConverted,
            restOpen: restOpen,
            structureSource: structureSource.flatMap { StructureSource(rawValue: $0) }
        )
    }
}
