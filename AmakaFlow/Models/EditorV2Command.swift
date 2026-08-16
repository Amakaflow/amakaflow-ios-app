//
//  EditorV2Command.swift
//  AmakaFlow
//
//  AMA-2438 P0 — typed command door + transactional apply (spec D1).
//

import Foundation

enum EditorCommand: Equatable, Sendable {
    case addExercises(names: [String], into: String?)
    case removeExercise(String)
    case replaceExercise(String, with: String)
    case updatePrescription(String, EditorV2Exercise)
    case pairSuperset(source: String, target: String)
    case removeFromGroup(String)
    case switchGroupType(String, EditorV2GroupType)
    case updateGroupConfig(String, EditorV2GroupConfig)
    case ungroup(String)
    case deleteGroup(String)
    case addBlock(EditorV2GroupType)
    case move(String, Int)
    case reorder(fromOffsets: IndexSet, toOffset: Int)
    case quickAddSoftSection(EnrichmentKind)
    case removeSoftSection(EditorV2GroupType, EnrichmentKind)
    case addSet(String)
}

enum ApplyResult: Equatable {
    case applied
    case rejected(Violation)
}

enum Violation: String, Equatable {
    case exerciseNotFound
    case groupNotFound
    case invalidGroupMembership
    case emptyGroup
    case duplicateIDs
    case unresolvedReferences
    case formatGroupMissing
    case invalidState
}

extension EditorV2Session {
    mutating func apply(_ command: EditorCommand) -> ApplyResult {
        var copy = self
        // AMA-2438 P2: use D2 implementation
        let result = copy.applyD2(command)
        
        switch result {
        case .applied:
            copy.normalizeD2()
            let validation = copy.validateD2()
            if validation == .applied {
                self = copy
                return .applied
            } else {
                assertionFailure("Command produced invalid state: \(command)")
                return validation
            }
        case .rejected:
            return result
        }
    }
    
    // swiftlint:disable:next function_body_length
    private mutating func applyInternal(_ command: EditorCommand) -> ApplyResult {
        switch command {
        case .addExercises(let names, let into):
            for name in names {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                
                let groupKey = into ?? formatGroupKey
                let groupType = groupKey.flatMap { groups[$0]?.type }
                
                let exercise: EditorV2Exercise
                if let key = groupKey, groupType == .superset {
                    exercise = EditorV2Exercise(
                        name: trimmed,
                        sets: 3,
                        reps: 10,
                        restSeconds: 60,
                        groupKey: key
                    )
                } else if groupType.map { $0 != .superset } ?? false, let key = groupKey {
                    exercise = EditorV2Exercise(name: trimmed, reps: 10, groupKey: key)
                } else {
                    exercise = EditorV2Exercise(
                        name: trimmed,
                        sets: 3,
                        reps: 10,
                        restSeconds: 60,
                        groupKey: nil
                    )
                }
                exercises.append(exercise)
            }
            return .applied
            
        case .removeExercise(let id):
            exercises.removeAll { $0.id == id }
            return .applied
            
        case .replaceExercise(let id, let name):
            guard let index = exercises.firstIndex(where: { $0.id == id }) else {
                return .rejected(.exerciseNotFound)
            }
            exercises[index].name = name
            exercises[index].swapMessage = nil
            exercises[index].swapReplacementName = nil
            return .applied
            
        case .updatePrescription(let id, let updated):
            guard let index = exercises.firstIndex(where: { $0.id == id }) else {
                return .rejected(.exerciseNotFound)
            }
            exercises[index] = updated
            return .applied
            
        case .pairSuperset(let sourceID, let targetID):
            guard let source = exercises.first(where: { $0.id == sourceID }),
                  let target = exercises.first(where: { $0.id == targetID }) else {
                return .rejected(.exerciseNotFound)
            }
            
            var key = target.groupKey
            if let existing = key, groups[existing]?.type == .superset {
                // join existing
            } else {
                let createdKey = "ss\(UUID().uuidString)"
                groups[createdKey] = EditorV2Group(
                    id: createdKey,
                    type: .superset,
                    name: "Superset",
                    config: EditorV2GroupType.superset.defaultConfig,
                    structureSource: .userConfirmed
                )
                key = createdKey
                if let idx = exercises.firstIndex(where: { $0.id == targetID }) {
                    exercises[idx].groupKey = createdKey
                }
            }
            
            guard let key else { return .applied }
            exercises.removeAll { $0.id == sourceID }
            if let targetIndex = exercises.firstIndex(where: { $0.id == targetID }) {
                var moved = source
                moved.groupKey = key
                exercises.insert(moved, at: targetIndex + 1)
            } else {
                var moved = source
                moved.groupKey = key
                exercises.append(moved)
            }
            return .applied
            
        case .removeFromGroup(let exerciseID):
            guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else {
                return .rejected(.exerciseNotFound)
            }
            exercises[index].groupKey = nil
            return .applied
            
        case .switchGroupType(let key, let type):
            guard var group = groups[key] else {
                return .rejected(.groupNotFound)
            }
            let keepCustomName = !EditorV2GroupType.allCases.map(\.label).contains(group.name)
            group.type = type
            group.config = type.defaultConfig
            if !keepCustomName {
                group.name = type.label
            }
            group.structureSource = .userConfirmed
            groups[key] = group
            return .applied
            
        case .updateGroupConfig(let key, let config):
            guard var group = groups[key] else {
                return .rejected(.groupNotFound)
            }
            group.config = config
            groups[key] = group
            return .applied
            
        case .ungroup(let key):
            for index in exercises.indices where exercises[index].groupKey == key {
                exercises[index].groupKey = nil
            }
            groups.removeValue(forKey: key)
            if formatGroupKey == key {
                formatGroupKey = nil
            }
            return .applied
            
        case .deleteGroup(let key):
            exercises.removeAll { $0.groupKey == key }
            groups.removeValue(forKey: key)
            if formatGroupKey == key {
                formatGroupKey = nil
            }
            return .applied
            
        case .addBlock(let type):
            let key = "fmt"
            groups = [
                key: EditorV2Group(
                    id: key,
                    type: type,
                    name: type.label,
                    config: type.defaultConfig,
                    structureSource: .userConfirmed
                )
            ]
            formatGroupKey = key
            exercises = []
            return .applied
            
        case .move(let fromID, let toIndex):
            guard let fromIndex = exercises.firstIndex(where: { $0.id == fromID }) else {
                return .rejected(.exerciseNotFound)
            }
            let item = exercises.remove(at: fromIndex)
            let adjusted = toIndex > fromIndex ? toIndex - 1 : toIndex
            let safeIndex = max(0, min(adjusted, exercises.count))
            exercises.insert(item, at: safeIndex)
            return .applied
            
        case .reorder(let fromOffsets, let toOffset):
            var items = exercises
            let moving = fromOffsets.sorted().map { items[$0] }
            for index in fromOffsets.sorted(by: >) {
                items.remove(at: index)
            }
            var insertAt = toOffset
            for index in fromOffsets where index < toOffset {
                insertAt -= 1
            }
            insertAt = max(0, min(insertAt, items.count))
            items.insert(contentsOf: moving, at: insertAt)
            exercises = items
            return .applied
            
        case .quickAddSoftSection(let kind):
            return quickAddSoftSectionInternal(kind)
            
        case .removeSoftSection(let type, let kind):
            removeSoftSectionInternal(type: type, kind: kind)
            return .applied
            
        case .addSet(let id):
            guard let index = exercises.firstIndex(where: { $0.id == id }) else {
                return .rejected(.exerciseNotFound)
            }
            if let sets = exercises[index].sets {
                exercises[index].sets = sets + 1
            } else {
                exercises[index].sets = 1
                if exercises[index].reps == nil {
                    exercises[index].reps = 10
                }
            }
            return .applied
        }
    }
    
    private mutating func normalize() {
        repairBrokenGroups()
        pruneEmptyGroups()
        refreshSupersetLabels()
    }
    
    private mutating func refreshSupersetLabels() {
        for key in groups.keys where groups[key]?.type == .superset {
            guard var group = groups[key] else { continue }
            let memberCount = exercises.filter { $0.groupKey == key }.count
            let autoNames: Set<String> = ["Superset", "Tri-set", "Tri-sets"]
            guard autoNames.contains(group.name) || group.name.isEmpty else { continue }
            let prefersTriSet = group.name == "Tri-set" || group.name == "Tri-sets"
            if prefersTriSet {
                group.name = "Tri-set"
            } else if memberCount >= 3 {
                group.name = "Tri-set"
            } else {
                group.name = "Superset"
            }
            groups[key] = group
        }
    }
    
    private func validate() -> ApplyResult {
        // I1: Every id reference resolves; membership is a partition
        let allExerciseIDs = Set(exercises.map(\.id))
        guard allExerciseIDs.count == exercises.count else {
            return .rejected(.duplicateIDs)
        }
        
        var usedIDs = Set<String>()
        for exercise in exercises {
            if usedIDs.contains(exercise.id) {
                return .rejected(.duplicateIDs)
            }
            usedIDs.insert(exercise.id)
            
            if let groupKey = exercise.groupKey {
                guard groups[groupKey] != nil else {
                    return .rejected(.unresolvedReferences)
                }
            }
        }
        
        // I2: Every group has ≥1 member OR is formatGroupKey
        for (key, _) in groups {
            let memberCount = exercises.filter { $0.groupKey == key }.count
            if memberCount == 0 && key != formatGroupKey {
                return .rejected(.emptyGroup)
            }
        }
        
        // I3: All ids unique; projection (runs) ids unique
        let runIDs = runs.map(\.id)
        guard Set(runIDs).count == runIDs.count else {
            return .rejected(.duplicateIDs)
        }
        
        // I6: formatGroupKey, if set, resolves to an existing group
        if let fmtKey = formatGroupKey {
            guard groups[fmtKey] != nil else {
                return .rejected(.formatGroupMissing)
            }
        }
        
        return .applied
    }
    
    private mutating func repairBrokenGroups() {
        let keys = Set(exercises.compactMap(\.groupKey))
        for key in keys {
            let indices = exercises.indices.filter { exercises[$0].groupKey == key }
            guard let first = indices.first, let last = indices.last else { continue }
            let contiguous = last - first + 1 == indices.count
            guard !contiguous else { continue }
            for index in indices {
                exercises[index].groupKey = nil
            }
        }
        pruneEmptyGroups()
    }
    
    private mutating func pruneEmptyGroups() {
        let used = Set(exercises.compactMap(\.groupKey))
        for key in groups.keys where !used.contains(key) && key != formatGroupKey {
            groups.removeValue(forKey: key)
        }
    }
    
    private mutating func quickAddSoftSectionInternal(_ kind: EnrichmentKind) -> ApplyResult {
        // This would normally load prefs, but for now return rejected
        // The actual implementation will be called from the existing methods
        return .rejected(.invalidState)
    }
    
    private mutating func removeSoftSectionInternal(type: EditorV2GroupType, kind: EnrichmentKind) {
        let keys = Set(groups.filter { $0.value.type == type }.keys)
        if !keys.isEmpty {
            exercises.removeAll {
                guard let groupKey = $0.groupKey else { return false }
                keys.contains(groupKey)
            }
            for key in keys {
                groups.removeValue(forKey: key)
                if formatGroupKey == key {
                    formatGroupKey = nil
                }
            }
        }
        WorkoutEnrichmentMutations.appendTombstone(&enrichmentTombstones, kind: kind)
        enrichmentTombstonesDirty = true
    }
}
