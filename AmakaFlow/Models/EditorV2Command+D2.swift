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
            // Validate explicit destination early (shape B constraint)
            if let into, groups[into] == nil {
                return .rejected(.invalidGroupMembership)
            }
            
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
                if var group = groups[key] {
                    group.memberIDs.removeAll { $0 == id }
                    groups[key] = group
                }
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
                if var group = groups[groupKey] {
                    group.memberIDs.removeAll { $0 == sourceID }
                    groups[groupKey] = group
                }
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
            
            // Update groupKey fields (will be synced again in normalize)
            if var sourceEx = exercises[sourceID] {
                sourceEx.groupKey = key
                exercises[sourceID] = sourceEx
            }
            if var targetEx = exercises[targetID] {
                targetEx.groupKey = key
                exercises[targetID] = targetEx
            }
            
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
            
            // Clear groupKey field (will be synced again in normalize)
            if var exercise = exercises[exerciseID] {
                exercise.groupKey = nil
                exercises[exerciseID] = exercise
            }
            
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
                    // Clear groupKey field (will be synced again in normalize)
                    if var exercise = exercises[memberID] {
                        exercise.groupKey = nil
                        exercises[memberID] = exercise
                    }
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
            
        case .setExerciseSets(let id, let sets):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            // Intentional: sets can be nil. No validator opinion on a sets-less rep exercise.
            exercise.sets = sets
            exercises[id] = exercise
            return .applied
            
        case .setExerciseReps(let id, let reps):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.reps = reps
            exercise.repsRange = nil
            exercises[id] = exercise
            return .applied
            
        case .setExerciseRepsRange(let id, let range):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.repsRange = range
            if range != nil {
                exercise.reps = nil
            }
            exercises[id] = exercise
            return .applied
            
        case .setExerciseDuration(let id, let durationSeconds):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.durationSeconds = durationSeconds
            exercises[id] = exercise
            return .applied
            
        case .setExerciseDistance(let id, let distanceMeters):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.distanceMeters = distanceMeters
            exercises[id] = exercise
            return .applied
            
        case .setExerciseWeight(let id, let weightKg):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.weightKg = weightKg
            if weightKg != nil {
                exercise.isBodyweight = false
            }
            exercises[id] = exercise
            return .applied
            
        case .setExerciseBodyweight(let id, let isBodyweight):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.isBodyweight = isBodyweight
            if isBodyweight {
                exercise.weightKg = nil
            }
            exercises[id] = exercise
            return .applied
            
        case .setExerciseRest(let id, let restSeconds):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.restSeconds = restSeconds
            exercises[id] = exercise
            return .applied
            
        case .setExerciseCalories(let id, let calories):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.calories = calories
            exercises[id] = exercise
            return .applied
            
        case .setExerciseOpenGoal(let id, let openGoal):
            guard var exercise = exercises[id] else {
                return .rejected(.exerciseNotFound)
            }
            exercise.openGoal = openGoal
            exercises[id] = exercise
            return .applied
            
        case .quickAddSoftSection(let kind, let activities, let clearingTombstone):
            let type: EditorV2GroupType = kind == .cooldown ? .cooldown : .warmup
            guard type.isSoftSection else { return .rejected(.invalidState) }
            
            // Check tombstone unless explicitly clearing it
            if !clearingTombstone && enrichmentTombstones.contains(where: { $0.kind == kind }) {
                return .rejected(.invalidState)
            }
            
            // Check if this type already exists (blocked by presence)
            if groups.values.contains(where: { $0.type == type }) {
                return .rejected(.invalidState)
            }
            
            // Clear tombstone if requested
            if clearingTombstone {
                enrichmentTombstones.removeAll { $0.kind == kind }
                enrichmentTombstonesDirty = true
            }
            
            let key = UUID().uuidString
            let config = type.defaultConfig
            let prepend = (type == .warmup)
            
            var memberIDs: [String] = []
            for activity in activities {
                let exerciseID = UUID().uuidString
                let exercise = EditorV2Exercise(
                    id: exerciseID,
                    name: activity.name,
                    durationSeconds: activity.durationSec,
                    groupKey: nil,
                    structureSource: clearingTombstone ? .userAdded : .enrichmentDefault
                )
                exercises[exerciseID] = exercise
                memberIDs.append(exerciseID)
            }
            
            let group = EditorV2Group(
                id: key,
                type: type,
                name: type.label,
                letter: nil,
                config: config,
                memberIDs: memberIDs,
                structureSource: .enrichmentDefault,
                enrichmentKind: kind
            )
            groups[key] = group
            
            if prepend {
                order.insert(.group(key), at: 0)
            } else {
                order.append(.group(key))
            }
            
            return .applied
            
        case .removeSoftSection(let type, let kind):
            guard type.isSoftSection else { return .rejected(.invalidState) }
            
            let keys = Set(groups.filter { $0.value.type == type }.keys)
            if !keys.isEmpty {
                // Remove exercises that are members of these groups
                for key in keys {
                    if let group = groups[key] {
                        for memberID in group.memberIDs {
                            exercises.removeValue(forKey: memberID)
                        }
                    }
                    groups.removeValue(forKey: key)
                    if formatGroupKey == key {
                        formatGroupKey = nil
                    }
                }
                // Remove groups from order
                order.removeAll { row in
                    if case .group(let key) = row {
                        return keys.contains(key)
                    }
                    return false
                }
            }
            WorkoutEnrichmentMutations.appendTombstone(&enrichmentTombstones, kind: kind)
            enrichmentTombstonesDirty = true
            return .applied
            
        case .beginNextSupersetGroup(let preferredName):
            let key = "ss\(UUID().uuidString)"
            let letter = nextSupersetLetter()
            
            // Infer name from previous formatGroupKey if building tri-sets
            let defaultName: String = {
                if let prevKey = formatGroupKey, let prevGroup = groups[prevKey] {
                    let triSetNames: Set<String> = ["Tri-set", "Tri-sets"]
                    if triSetNames.contains(prevGroup.name) {
                        return "Tri-set"
                    }
                }
                return "Superset"
            }()
            
            groups[key] = EditorV2Group(
                id: key,
                type: .superset,
                name: preferredName ?? defaultName,
                letter: letter,
                config: EditorV2GroupType.superset.defaultConfig,
                memberIDs: [],
                structureSource: .userConfirmed
            )
            formatGroupKey = key
            order.append(.group(key))
            return .applied
            
        case .addWarmupSets(let exerciseID, let rows, let clearingTombstone):
            guard !rows.isEmpty, var exercise = exercises[exerciseID] else { return .rejected(.exerciseNotFound) }
            guard exercise.sets != nil else { return .rejected(.invalidState) }
            guard exercise.warmupSets.isEmpty else { return .rejected(.invalidState) }
            let exerciseId = exercise.exerciseId ?? WorkoutEnrichmentMutations.mintExerciseId()
            if clearingTombstone {
                clearEnrichmentTombstone(.exerciseWarmupSets, exerciseId: exerciseId)
            }
            guard !WorkoutEnrichmentPresence.isTombstoned(
                .exerciseWarmupSets,
                exerciseId: exerciseId,
                tombstones: enrichmentTombstones
            ) else { return .rejected(.invalidState) }
            exercise.exerciseId = exerciseId
            exercise.warmupSets = rows
            exercises[exerciseID] = exercise
            return .applied
            
        case .removeWarmupSets(let exerciseID):
            guard var exercise = exercises[exerciseID] else { return .rejected(.exerciseNotFound) }
            let exerciseId = exercise.exerciseId ?? WorkoutEnrichmentMutations.mintExerciseId()
            exercise.exerciseId = exerciseId
            exercise.warmupSets = []
            exercises[exerciseID] = exercise
            WorkoutEnrichmentMutations.appendTombstone(
                &enrichmentTombstones,
                kind: .exerciseWarmupSets,
                exerciseId: exerciseId
            )
            enrichmentTombstonesDirty = true
            return .applied
        }
    }
    
    private func nextSupersetLetter() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let usedLetters = Set(groups.values.compactMap(\.letter))
        for letter in letters {
            let str = String(letter)
            if !usedLetters.contains(str) {
                return str
            }
        }
        return "A"
    }
}

extension EditorV2Session {
    mutating func normalizeD2() {
        repairOrderCoverageD2()
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
        
        // Check 2: Group members appear as loose (split group)
        var looseIDs: Set<String> = []
        for row in order {
            if case .loose(let id) = row {
                looseIDs.insert(id)
            }
        }
        for (key, group) in groups {
            // If ANY member of this group appears as loose in order, the group is split
            let hasSplitMember = group.memberIDs.contains { memberID in
                looseIDs.contains(memberID)
            }
            if hasSplitMember {
                keysToUngroup.insert(key)
            }
        }
        
        // Ungroup all split groups
        for key in keysToUngroup {
            guard let group = groups[key] else { continue }
            // Replace group references with loose members, keep loose members as-is
            var newOrder: [EditorV2Row] = []
            var looseIDsInNewOrder: Set<String> = []
            for row in order {
                if case .group(key) = row {
                    for memberID in group.memberIDs {
                        guard !looseIDsInNewOrder.contains(memberID) else { continue }
                        newOrder.append(.loose(memberID))
                        looseIDsInNewOrder.insert(memberID)
                    }
                } else {
                    if case .loose(let id) = row {
                        guard !looseIDsInNewOrder.contains(id) else { continue }
                        newOrder.append(row)
                        looseIDsInNewOrder.insert(id)
                    } else {
                        newOrder.append(row)
                    }
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

    private mutating func repairOrderCoverageD2() {
        // Ensure every declared group appears once on the canvas order.
        var presentGroupKeys = Set<String>()
        var looseIDs = Set<String>()
        for row in order {
            if case .group(let key) = row {
                presentGroupKeys.insert(key)
            } else if case .loose(let id) = row {
                looseIDs.insert(id)
            }
        }
        for key in groups.keys.sorted() where !presentGroupKeys.contains(key) {
            // If any member already appears as loose, this is a split shape.
            // Leave it for repairSplitGroupsD2 instead of re-inserting the group row.
            if let group = groups[key],
               group.memberIDs.contains(where: { looseIDs.contains($0) }) {
                continue
            }
            order.append(.group(key))
        }

        // Ensure every exercise is represented either as loose or via a group's memberIDs.
        var representedExerciseIDs = Set<String>()
        for row in order {
            switch row {
            case .group(let key):
                if let group = groups[key] {
                    representedExerciseIDs.formUnion(group.memberIDs)
                }
            case .loose(let id):
                representedExerciseIDs.insert(id)
            }
        }
        for id in exercises.keys.sorted() where !representedExerciseIDs.contains(id) {
            order.append(.loose(id))
        }
    }
    
    private mutating func syncGroupKeyFieldsD2() {
        // Clear all groupKey fields first
        for id in exercises.keys {
            if var exercise = exercises[id] {
                exercise.groupKey = nil
                exercises[id] = exercise
            }
        }
        // Set groupKey for all members
        for (key, group) in groups {
            for memberID in group.memberIDs {
                if var exercise = exercises[memberID] {
                    exercise.groupKey = key
                    exercises[memberID] = exercise
                }
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
            
            // Don't refresh format group name - it stays as the target name while building
            if key == formatGroupKey {
                continue
            }
            
            let memberCount = group.memberIDs.count
            
            // D3: use displayName function for derived labels
            let autoNames: Set<String> = ["Superset", "Tri-set", "Tri-sets", "Giant set"]
            if autoNames.contains(group.name) || group.name.isEmpty {
                let newName = group.displayName(memberCount: memberCount)
                var updatedGroup = group
                updatedGroup.name = newName
                groups[key] = updatedGroup
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
