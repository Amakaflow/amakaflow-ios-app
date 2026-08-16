//
//  EditorV2Command+D2.swift
//  AmakaFlow
//
//  AMA-2438 P2 — D2 command implementations for declared membership model.
//
// swiftlint:disable file_length

import Foundation

extension EditorV2Session {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    mutating func applyD2(_ command: EditorCommand) -> ApplyResult {
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
                        groupKey: nil  // D2: no back-pointer
                    )
                } else if groupType.map({ $0 != .superset }) ?? false {
                    exercise = EditorV2Exercise(name: trimmed, reps: 10, groupKey: nil)
                } else {
                    exercise = EditorV2Exercise(
                        name: trimmed,
                        sets: 3,
                        reps: 10,
                        restSeconds: 60,
                        groupKey: nil
                    )
                }
                
                exercises[exercise.id] = exercise
                
                if let key = groupKey {
                    // Add to group's memberIDs
                    groups[key]?.memberIDs.append(exercise.id)
                    // Ensure group is in order
                    if !order.contains(where: { if case .group(key) = $0 { return true }; return false }) {
                        order.append(.group(key))
                    }
                } else {
                    // Loose exercise
                    order.append(.loose(exercise.id))
                }
            }
            return .applied
            
        case .removeExercise(let id):
            // Remove from exercises dict
            exercises.removeValue(forKey: id)
            
            // Remove from any group's memberIDs
            for key in groups.keys {
                groups[key]?.memberIDs.removeAll { $0 == id }
            }
            
            // Remove from order
            order.removeAll {
                if case .loose(id) = $0 { return true }
                return false
            }
            
            return .applied
            
        case .replaceExercise(let id, let name):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.name = name
            exercise.swapMessage = nil
            exercise.swapReplacementName = nil
            exercises[id] = exercise
            return .applied
            
        case .updatePrescription(let id, let updated):
            guard exercises[id] != nil else {
                return .rejected(.exerciseNotFound)
            }
            exercises[id] = updated
            return .applied
            
        case .pairSuperset(let sourceID, let targetID):
            guard let source = exercises[sourceID],
                  exercises[targetID] != nil else {
                return .rejected(.exerciseNotFound)
            }
            
            // Find target's group if any
            var targetGroupKey: String?
            for (key, group) in groups where group.memberIDs.contains(targetID) {
                targetGroupKey = key
                break
            }
            
            var key: String
            if let existing = targetGroupKey, groups[existing]?.type == .superset {
                // Join existing superset
                key = existing
            } else if let existing = targetGroupKey {
                // Target is in a non-superset group - reject (need explicit extract)
                return .rejected(.invalidGroupMembership)
            } else {
                // Create new superset group
                let createdKey = "ss\(UUID().uuidString)"
                groups[createdKey] = EditorV2Group(
                    id: createdKey,
                    type: .superset,
                    name: "Superset",
                    config: EditorV2GroupType.superset.defaultConfig,
                    memberIDs: [targetID],
                    structureSource: .userConfirmed
                )
                key = createdKey
                
                // Replace target's loose row with group row
                if let targetIdx = order.firstIndex(where: {
                    if case .loose(targetID) = $0 { return true }
                    return false
                }) {
                    order[targetIdx] = .group(key)
                }
            }
            
            // Remove source from its current location
            // First remove from any group
            for groupKey in groups.keys {
                groups[groupKey]?.memberIDs.removeAll { $0 == sourceID }
            }
            // Remove from order
            order.removeAll {
                if case .loose(sourceID) = $0 { return true }
                return false
            }
            
            // Add source to target's group, adjacent to target
            if let targetIdx = groups[key]?.memberIDs.firstIndex(of: targetID) {
                groups[key]?.memberIDs.insert(sourceID, at: targetIdx + 1)
            } else {
                groups[key]?.memberIDs.append(sourceID)
            }
            
            // Update groupKey fields
            exercises[sourceID]?.groupKey = key
            exercises[targetID]?.groupKey = key
            
            return .applied
            
        case .removeFromGroup(let exerciseID):
            guard exercises[exerciseID] != nil else {
                return .rejected(.exerciseNotFound)
            }
            
            // Find and remove from group
            var foundGroupKey: String?
            for key in groups.keys where groups[key]?.memberIDs.contains(exerciseID) == true {
                if let idx = groups[key]?.memberIDs.firstIndex(of: exerciseID) {
                    groups[key]?.memberIDs.remove(at: idx)
                    foundGroupKey = key
                    break
                }
            }
            
            guard let groupKey = foundGroupKey else {
                return .applied  // Already loose
            }
            
            // Add as loose exercise after the group
            if let groupIdx = order.firstIndex(where: {
                if case .group(groupKey) = $0 { return true }
                return false
            }) {
                order.insert(.loose(exerciseID), at: groupIdx + 1)
            } else {
                order.append(.loose(exerciseID))
            }
            
            // Clear groupKey field
            exercises[exerciseID]?.groupKey = nil
            
            return .applied
            
        case .switchGroupType(let key, let type):
            guard var group = groups[key] else {
                return .rejected(.groupNotFound)
            }
            // Check if name is auto-generated (type labels + superset variants)
            let autoNames: Set<String> = Set(EditorV2GroupType.allCases.map(\.label))
                .union(["Tri-set", "Tri-sets", "Giant set"])
            let keepCustomName = !autoNames.contains(group.name)
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
            guard let group = groups[key] else {
                return .rejected(.groupNotFound)
            }
            
            // Find group's position in order
            if let groupIdx = order.firstIndex(where: {
                if case .group(key) = $0 { return true }
                return false
            }) {
                // Replace group with loose exercises
                order.remove(at: groupIdx)
                for (idx, memberID) in group.memberIDs.enumerated() {
                    order.insert(.loose(memberID), at: groupIdx + idx)
                    // Clear groupKey field
                    exercises[memberID]?.groupKey = nil
                }
            }
            
            groups.removeValue(forKey: key)
            if formatGroupKey == key {
                formatGroupKey = nil
            }
            return .applied
            
        case .deleteGroup(let key):
            guard let group = groups[key] else {
                return .rejected(.groupNotFound)
            }
            
            // Remove all member exercises
            for memberID in group.memberIDs {
                exercises.removeValue(forKey: memberID)
            }
            
            // Remove from order
            order.removeAll {
                if case .group(key) = $0 { return true }
                return false
            }
            
            groups.removeValue(forKey: key)
            if formatGroupKey == key {
                formatGroupKey = nil
            }
            return .applied
            
        case .addBlock(let type):
            let key = "fmt"
            order = [.group(key)]
            groups = [
                key: EditorV2Group(
                    id: key,
                    type: type,
                    name: type.label,
                    config: type.defaultConfig,
                    memberIDs: [],
                    structureSource: .userConfirmed
                )
            ]
            formatGroupKey = key
            exercises = [:]
            return .applied
            
        case .move(let fromID, let toIndex):
            // Find and remove from current position
            var removed: EditorV2Row?
            
            // Check if it's loose
            if let idx = order.firstIndex(where: {
                if case .loose(fromID) = $0 { return true }
                return false
            }) {
                removed = order.remove(at: idx)
            } else {
                // Find in groups
                for (key, group) in groups where group.memberIDs.contains(fromID) {
                    if let memberIdx = group.memberIDs.firstIndex(of: fromID) {
                        groups[key]?.memberIDs.remove(at: memberIdx)
                        // If last member and not format group, remove group from order
                        if group.memberIDs.count == 1 && key != formatGroupKey {
                            order.removeAll {
                                if case .group(key) = $0 { return true }
                                return false
                            }
                        }
                        removed = .loose(fromID)
                        break
                    }
                }
            }
            
            guard let row = removed else {
                return .rejected(.exerciseNotFound)
            }
            
            let safeIndex = max(0, min(toIndex, order.count))
            order.insert(row, at: safeIndex)
            return .applied
            
        case .reorder(let fromOffsets, let toOffset):
            var items = order
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
            order = items
            return .applied
            
        case .addSet(let id):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            if let sets = exercise.sets {
                exercise.sets = sets + 1
            } else {
                exercise.sets = 1
                if exercise.reps == nil {
                    exercise.reps = 10
                }
            }
            exercises[id] = exercise
            return .applied
            
        case .quickAddSoftSection, .removeSoftSection:
            // These remain unimplemented for now
            return .rejected(.invalidState)
        }
    }
}

extension EditorV2Session {
    mutating func normalizeD2() {
        syncGroupKeyFieldsD2()
        repairSplitGroupsD2()
        syncGroupKeyFieldsD2()  // Sync again after repair in case groups were ungrouped
        pruneEmptyGroupsD2()
        refreshSupersetLabelsD2()
    }
    
    // swiftlint:disable cyclomatic_complexity
    private mutating func repairSplitGroupsD2() {
        // Detect groups whose members are split across order (appear as loose when they should be in group)
        var keysToUngroup: Set<String> = []
        
        // Check 1: Group appears multiple times in order
        var groupPositions: [String: [Int]] = [:]
        for (idx, row) in order.enumerated() {
            if case .group(let key) = row {
                groupPositions[key, default: []].append(idx)
            }
        }
        for (key, positions) in groupPositions where positions.count > 1 {
            keysToUngroup.insert(key)
        }
        
        // Check 2: Group members appear as loose when group exists in order
        var looseIDs: Set<String> = []
        for row in order {
            if case .loose(let id) = row {
                looseIDs.insert(id)
            }
        }
        for (key, group) in groups {
            for memberID in group.memberIDs where looseIDs.contains(memberID) {
                keysToUngroup.insert(key)
                break
            }
        }
        
        // Ungroup all split groups
        for key in keysToUngroup {
            guard let group = groups[key] else { continue }
            // Replace group references with loose members, keep loose members as-is
            var newOrder: [EditorV2Row] = []
            for row in order {
                if case .group(key) = row {
                    for memberID in group.memberIDs {
                        newOrder.append(.loose(memberID))
                    }
                } else {
                    newOrder.append(row)
                }
            }
            order = newOrder
            groups.removeValue(forKey: key)
            if formatGroupKey == key {
                formatGroupKey = nil
            }
        }
    }
    // swiftlint:enable cyclomatic_complexity
    
    private mutating func syncGroupKeyFieldsD2() {
        // Clear all groupKey fields first
        for id in exercises.keys {
            exercises[id]?.groupKey = nil
        }
        // Set groupKey for all members
        for (key, group) in groups {
            for memberID in group.memberIDs {
                exercises[memberID]?.groupKey = key
            }
        }
    }
    
    private mutating func pruneEmptyGroupsD2() {
        var keysToRemove: [String] = []
        for (key, group) in groups {
            if group.memberIDs.isEmpty && key != formatGroupKey {
                keysToRemove.append(key)
            }
        }
        
        for key in keysToRemove {
            groups.removeValue(forKey: key)
            order.removeAll {
                if case .group(key) = $0 { return true }
                return false
            }
        }
    }
    
    private mutating func refreshSupersetLabelsD2() {
        for key in groups.keys where groups[key]?.type == .superset {
            guard let group = groups[key] else { continue }
            let memberCount = group.memberIDs.count
            
            // D3: use displayName function for derived labels
            let autoNames: Set<String> = ["Superset", "Tri-set", "Tri-sets", "Giant set"]
            if autoNames.contains(group.name) || group.name.isEmpty {
                let newName = group.displayName(memberCount: memberCount)
                groups[key]?.name = newName
            }
        }
    }
    
    // swiftlint:disable:next cyclomatic_complexity
    func validateD2() -> ApplyResult {
        // I1: Partition invariant - every exercise in exactly one place
        var seen = Set<String>()
        for row in order {
            switch row {
            case .group(let key):
                guard let group = groups[key] else {
                    return .rejected(.unresolvedReferences)
                }
                for memberID in group.memberIDs {
                    guard !seen.contains(memberID) else {
                        return .rejected(.duplicateIDs)
                    }
                    guard exercises[memberID] != nil else {
                        return .rejected(.unresolvedReferences)
                    }
                    seen.insert(memberID)
                }
            case .loose(let id):
                guard !seen.contains(id) else {
                    return .rejected(.duplicateIDs)
                }
                guard exercises[id] != nil else {
                    return .rejected(.unresolvedReferences)
                }
                seen.insert(id)
            }
        }
        
        // All exercises must be in order
        for id in exercises.keys {
            guard seen.contains(id) else {
                return .rejected(.invalidGroupMembership)
            }
        }
        
        // I2: Every group has ≥1 member OR is formatGroupKey
        for (key, group) in groups {
            if group.memberIDs.isEmpty && key != formatGroupKey {
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
}
