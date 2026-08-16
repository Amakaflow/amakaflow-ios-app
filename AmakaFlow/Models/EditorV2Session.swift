//
//  EditorV2Session.swift
//  AmakaFlow
//
//  AMA-2307 — pure Editor v2 state: flat exercises + group dict (screens-editor2.jsx).
//

import Foundation

struct EditorV2Session: Equatable, Sendable {
    var title: String
    /// AMA-2438 D2: canvas owns block order. Adjacency carries no meaning.
    var order: [EditorV2Row]
    var groups: [String: EditorV2Group]
    /// AMA-2438 D2: exercises keyed by ID (no longer flat array with back-pointers).
    var exercises: [String: EditorV2Exercise]
    /// Pinned format group key from empty-state chips (`fmt` in the prototype).
    var formatGroupKey: String?
    /// AMA-2336 — workout-level enrichment deletes. Written here, read by enrich.
    var enrichmentTombstones: [EnrichmentTombstone]
    /// True once this session appends/clears tombstones — save then rewrites metadata.
    /// Untouched sessions omit the key so a library reload without seeded tombstones
    /// cannot wipe server markers (nil = leave alone, [] = clear after re-opt-in).
    var enrichmentTombstonesDirty: Bool

    init(
        title: String = "",
        order: [EditorV2Row] = [],
        groups: [String: EditorV2Group] = [:],
        exercises: [String: EditorV2Exercise] = [:],
        formatGroupKey: String? = nil,
        enrichmentTombstones: [EnrichmentTombstone] = [],
        enrichmentTombstonesDirty: Bool = false
    ) {
        self.title = title
        self.order = order
        self.groups = groups
        self.exercises = exercises
        self.formatGroupKey = formatGroupKey
        self.enrichmentTombstones = enrichmentTombstones
        self.enrichmentTombstonesDirty = enrichmentTombstonesDirty
    }

    /// AMA-2438 D2: runs projection from declared membership (trivial now).
    var runs: [EditorV2Run] {
        var result: [EditorV2Run] = []
        for row in order {
            switch row {
            case .group(let key):
                guard let group = groups[key] else { continue }
                let members = group.memberIDs.compactMap { exercises[$0] }
                guard !members.isEmpty else { continue }
                result.append(
                    EditorV2Run(
                        id: key,
                        groupKey: key,
                        exercises: members
                    )
                )
            case .loose(let id):
                guard let exercise = exercises[id] else { continue }
                result.append(
                    EditorV2Run(
                        id: id,
                        groupKey: nil,
                        exercises: [exercise]
                    )
                )
            }
        }
        return result
    }

    mutating func updateExercise(_ id: String, patch: (inout EditorV2Exercise) -> Void) {
        guard var exercise = exercises[id] else { return }
        patch(&exercise)
        exercises[id] = exercise
    }

    mutating func removeExercise(_ id: String) {
        _ = apply(.removeExercise(id))
    }

    mutating func addSet(to id: String) {
        updateExercise(id) { exercise in
            if let sets = exercise.sets {
                exercise.sets = sets + 1
            } else {
                exercise.sets = 1
                if exercise.reps == nil { exercise.reps = 10 }
            }
        }
    }

    mutating func replaceExercise(_ id: String, with name: String) {
        updateExercise(id) { exercise in
            exercise.name = name
            exercise.swapMessage = nil
            exercise.swapReplacementName = nil
        }
    }
}

// MARK: - Enrichment quick add / delete (AMA-2336 §5)

extension EditorV2Session {
    /// Presence by **type**, never provenance — any warm-up section blocks injection.
    var hasWarmupSection: Bool {
        groups.values.contains { $0.type == .warmup }
    }

    var hasCooldownSection: Bool {
        groups.values.contains { $0.type == .cooldown }
    }

    /// Quick-add the session warm-up from prefs. No-op when prefs are off.
    ///
    /// `clearingTombstone` is the explicit editor / push-sheet re-opt-in: the user
    /// asked for this kind again, so the delete marker is dropped first. Presence
    /// by type still blocks a second warm-up section.
    @discardableResult
    mutating func quickAddSessionWarmup(
        from prefs: WorkoutPreferences,
        clearingTombstone: Bool = false
    ) -> Bool {
        guard prefs.sessionWarmup.enabled else { return false }
        return quickAddSessionWarmup(
            activities: prefs.sessionWarmupActivities,
            clearingTombstone: clearingTombstone
        )
    }

    @discardableResult
    mutating func quickAddSessionWarmup(
        activities: [EnrichmentActivity],
        clearingTombstone: Bool = false
    ) -> Bool {
        quickAddSoftSection(
            type: .warmup,
            kind: .sessionWarmup,
            activities: activities,
            prepend: true,
            clearingTombstone: clearingTombstone
        )
    }

    @discardableResult
    mutating func quickAddCooldown(
        from prefs: WorkoutPreferences,
        clearingTombstone: Bool = false
    ) -> Bool {
        guard prefs.cooldown.enabled else { return false }
        return quickAddCooldown(
            activities: prefs.cooldownActivities,
            clearingTombstone: clearingTombstone
        )
    }

    @discardableResult
    mutating func quickAddCooldown(
        activities: [EnrichmentActivity],
        clearingTombstone: Bool = false
    ) -> Bool {
        quickAddSoftSection(
            type: .cooldown,
            kind: .cooldown,
            activities: activities,
            prepend: false,
            clearingTombstone: clearingTombstone
        )
    }
    
    private mutating func quickAddSoftSection(
        type: EditorV2GroupType,
        kind: EnrichmentKind,
        activities: [EnrichmentActivity],
        prepend: Bool,
        clearingTombstone: Bool
    ) -> Bool {
        guard type.isSoftSection else { return false }
        
        let key = UUID().uuidString
        let config = type.defaultConfig
        
        var memberIDs: [String] = []
        for activity in activities {
            let exerciseID = UUID().uuidString
            let exercise = EditorV2Exercise(
                id: exerciseID,
                name: activity.name,
                sets: activity.sets,
                durationSeconds: activity.durationSeconds,
                groupKey: key,
                structureSource: clearingTombstone ? .userAdded : .enrichmentDefault
            )
            exercises[exerciseID] = exercise
            memberIDs.append(exerciseID)
        }
        
        let group = EditorV2Group(
            id: key,
            name: type.label,
            type: type,
            memberIDs: memberIDs,
            config: config,
            letter: nil,
            enrichmentKind: kind
        )
        groups[key] = group
        
        if prepend {
            order.insert(.group(key), at: 0)
        } else {
            order.append(.group(key))
        }
        
        return true
    }

    /// Delete = remove content **and** write the tombstone (callers own tombstones).
    mutating func removeSessionWarmup() {
        removeSoftSection(type: .warmup, kind: .sessionWarmup)
    }

    mutating func removeCooldown() {
        removeSoftSection(type: .cooldown, kind: .cooldown)
    }

    /// Warm-up sets are a sibling list — `sets: Int` is untouched. Strength shapes only.
    @discardableResult
    mutating func addDefaultWarmupSets(
        to id: String,
        rows: [WarmupSetRow],
        clearingTombstone: Bool = false
    ) -> Bool {
        guard !rows.isEmpty, var exercise = exercises[id] else { return false }
        guard exercise.sets != nil else { return false }
        guard exercise.warmupSets.isEmpty else { return false }
        let exerciseId = exercise.exerciseId ?? WorkoutEnrichmentMutations.mintExerciseId()
        if clearingTombstone {
            clearEnrichmentTombstone(.exerciseWarmupSets, exerciseId: exerciseId)
        }
        guard !WorkoutEnrichmentPresence.isTombstoned(
            .exerciseWarmupSets,
            exerciseId: exerciseId,
            tombstones: enrichmentTombstones
        ) else { return false }
        exercise.exerciseId = exerciseId
        exercise.warmupSets = rows
        exercises[id] = exercise
        return true
    }

    /// Per-exercise tombstone keys off `exercise_id` (rename-safe), so mint when missing.
    @discardableResult
    mutating func removeWarmupSets(from id: String) -> String? {
        guard var exercise = exercises[id] else { return nil }
        let exerciseId = exercise.exerciseId ?? WorkoutEnrichmentMutations.mintExerciseId()
        exercise.exerciseId = exerciseId
        exercise.warmupSets = []
        exercises[id] = exercise
        WorkoutEnrichmentMutations.appendTombstone(
            &enrichmentTombstones,
            kind: .exerciseWarmupSets,
            exerciseId: exerciseId
        )
        enrichmentTombstonesDirty = true
        return exerciseId
    }

    /// Save path — stable ids for tombstones written after this save.
    mutating func mintMissingExerciseIDs() {
        for id in exercises.keys where exercises[id]?.exerciseId == nil {
            exercises[id]?.exerciseId = WorkoutEnrichmentMutations.mintExerciseId()
        }
    }

    /// Push-sheet apply of a tombstoned kind: caller clears, then enrich runs.
    mutating func clearEnrichmentTombstone(_ kind: EnrichmentKind, exerciseId: String? = nil) {
        WorkoutEnrichmentMutations.clearTombstone(
            &enrichmentTombstones,
            kind: kind,
            exerciseId: exerciseId
        )
        enrichmentTombstonesDirty = true
    }

    private mutating func removeSoftSection(type: EditorV2GroupType, kind: EnrichmentKind) {
        let keys = Set(groups.filter { $0.value.type == type }.keys)
        if !keys.isEmpty {
            exercises = exercises.filter {
                guard let groupKey = $0.value.groupKey else { return true }
                return !keys.contains(groupKey)
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

// MARK: - AMA-2438 D2 Migration from adjacency to declared membership

extension EditorV2Session {
    // swiftlint:disable function_parameter_count
    /// Migrate from old adjacency model (flat array + groupKey back-pointers) to D2.
    static func fromLegacyExercises(
        title: String,
        groups: [String: EditorV2Group],
        exercisesArray: [EditorV2Exercise],
        formatGroupKey: String?,
        enrichmentTombstones: [EnrichmentTombstone],
        enrichmentTombstonesDirty: Bool
    ) -> EditorV2Session {
        var order: [EditorV2Row] = []
        var newGroups = groups
        var exercisesDict: [String: EditorV2Exercise] = [:]
        
        // Build order and memberIDs from adjacency
        var currentGroupKey: String?
        var currentMembers: [String] = []
        
        for exercise in exercisesArray {
            exercisesDict[exercise.id] = exercise
            
            if let groupKey = exercise.groupKey {
                if groupKey != currentGroupKey {
                    // Flush previous group
                    if let prevKey = currentGroupKey, !currentMembers.isEmpty {
                        newGroups[prevKey]?.memberIDs = currentMembers
                        order.append(.group(prevKey))
                        currentMembers = []
                    }
                    currentGroupKey = groupKey
                }
                currentMembers.append(exercise.id)
            } else {
                // Loose exercise - flush any in-progress group first
                if let prevKey = currentGroupKey, !currentMembers.isEmpty {
                    newGroups[prevKey]?.memberIDs = currentMembers
                    order.append(.group(prevKey))
                    currentMembers = []
                    currentGroupKey = nil
                }
                order.append(.loose(exercise.id))
            }
        }
        
        // Flush final group
        if let prevKey = currentGroupKey, !currentMembers.isEmpty {
            newGroups[prevKey]?.memberIDs = currentMembers
            order.append(.group(prevKey))
        }
        
        return EditorV2Session(
            title: title,
            order: order,
            groups: newGroups,
            exercises: exercisesDict,
            formatGroupKey: formatGroupKey,
            enrichmentTombstones: enrichmentTombstones,
            enrichmentTombstonesDirty: enrichmentTombstonesDirty
        )
    }
    // swiftlint:enable function_parameter_count
}

// MARK: - Compatibility methods for tests (wrap commands)

extension EditorV2Session {
    @discardableResult
    mutating func addExercise(named name: String) -> EditorV2Exercise {
        _ = apply(.addExercises(names: [name], into: nil))
        // Find the newly added exercise
        for row in order.reversed() {
            switch row {
            case .loose(let id):
                if let exercise = exercises[id], exercise.name == name {
                    return exercise
                }
            case .group(let key):
                if let group = groups[key], let lastID = group.memberIDs.last,
                   let exercise = exercises[lastID], exercise.name == name {
                    return exercise
                }
            }
        }
        fatalError("Exercise not found after add")
    }
    
    @discardableResult
    mutating func startFormat(_ type: EditorV2GroupType) -> String {
        _ = apply(.addBlock(type))
        return "fmt"
    }
    
    mutating func beginNextSupersetGroup(preferredName: String? = nil) -> String {
        let key = "ss\(UUID().uuidString)"
        let letter = nextSupersetLetter()
        groups[key] = EditorV2Group(
            id: key,
            type: .superset,
            name: preferredName ?? "Superset",
            letter: letter,
            config: EditorV2GroupType.superset.defaultConfig,
            memberIDs: [],
            structureSource: .userConfirmed
        )
        formatGroupKey = key
        order.append(.group(key))
        return key
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
    
    mutating func updateGroup(_ key: String, patch: (inout EditorV2Group) -> Void) {
        guard var group = groups[key] else { return }
        patch(&group)
        groups[key] = group
    }
    
    mutating func ungroup(_ key: String) {
        _ = apply(.ungroup(key))
    }
    
    mutating func discardAndRepinSupersetGroup(_ key: String) -> String? {
        guard let group = groups[key], group.type == .superset else { return nil }
        let preferredName: String = {
            if group.name.localizedCaseInsensitiveContains("tri") { return "Tri-set" }
            let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Superset" : trimmed
        }()
        _ = apply(.deleteGroup(key))
        return beginNextSupersetGroup(preferredName: preferredName)
    }
    
    mutating func focusFormatGroup(_ key: String) {
        guard groups[key] != nil else { return }
        formatGroupKey = key
    }
    
    mutating func removeFromSuperset(_ exerciseID: String) {
        _ = apply(.removeFromGroup(exerciseID))
    }
    
    mutating func pairSuperset(sourceID: String, targetID: String) {
        _ = apply(.pairSuperset(source: sourceID, target: targetID))
    }
    
    mutating func moveExercise(from fromID: String, to toID: String) {
        // Find toID's position in order
        var toIndex = 0
        for (idx, row) in order.enumerated() {
            switch row {
            case .loose(let id) where id == toID:
                toIndex = idx
            case .group(let key):
                if let group = groups[key], group.memberIDs.contains(toID) {
                    toIndex = idx
                }
            default:
                break
            }
        }
        _ = apply(.move(fromID, toIndex))
    }
    
    mutating func reorder(fromOffsets: IndexSet, toOffset: Int) {
        _ = apply(.reorder(fromOffsets: fromOffsets, toOffset: toOffset))
    }
    
    mutating func switchGroupType(_ key: String, to type: EditorV2GroupType) {
        _ = apply(.switchGroupType(key, type))
    }
}
