//
//  EditorV2Session.swift
//  AmakaFlow
//
//  AMA-2307 — pure Editor v2 state: flat exercises + group dict (screens-editor2.jsx).
//

// swiftlint:disable file_length

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
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        patch(&exercises[index])
    }

    mutating func removeExercise(_ id: String) {
        exercises.removeAll { $0.id == id }
        pruneEmptyGroups()
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

    /// Format-first chip — pins a group; adds land inside.
    @discardableResult
    mutating func startFormat(_ type: EditorV2GroupType) -> String {
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
        return key
    }

    /// Add exercise — defaults 3×10 · 60s flat, or plain reps inside timed formats.
    /// Superset / tri-set format pins also land inside the active group so the
    /// list shows one banded block (not loose straight-set cards).
    @discardableResult
    mutating func addExercise(named name: String) -> EditorV2Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fmtKey = formatGroupKey
        let fmtType = fmtKey.flatMap { groups[$0]?.type }
        let exercise: EditorV2Exercise
        if let fmtKey, fmtType == .superset {
            exercise = EditorV2Exercise(
                name: trimmed,
                sets: 3,
                reps: 10,
                restSeconds: 60,
                groupKey: fmtKey
            )
            exercises.append(exercise)
            refreshSupersetGroupLabel(fmtKey)
            return exercise
        }
        let timed = fmtType.map { $0 != .superset } ?? false
        if timed, let fmtKey {
            exercise = EditorV2Exercise(name: trimmed, reps: 10, groupKey: fmtKey)
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
        return exercise
    }

    /// Close the current superset/tri-set and pin a fresh group for the next adds.
    @discardableResult
    mutating func beginNextSupersetGroup(preferredName: String? = nil) -> String {
        let key = "ss\(UUID().uuidString)"
        let priorName = formatGroupKey.flatMap { groups[$0]?.name }
        let name: String = {
            if let preferredName, !preferredName.isEmpty { return preferredName }
            if priorName == "Tri-set" || priorName == "Tri-sets" { return "Tri-set" }
            return "Superset"
        }()
        groups[key] = EditorV2Group(
            id: key,
            type: .superset,
            name: name,
            config: EditorV2GroupType.superset.defaultConfig,
            structureSource: .userConfirmed
        )
        formatGroupKey = key
        return key
    }

    mutating func updateGroup(_ key: String, patch: (inout EditorV2Group) -> Void) {
        guard var group = groups[key] else { return }
        patch(&group)
        groups[key] = group
    }

    mutating func switchGroupType(_ key: String, to type: EditorV2GroupType) {
        guard var group = groups[key] else { return }
        let keepCustomName = !EditorV2GroupType.allCases.map(\.label).contains(group.name)
        group.type = type
        group.config = type.defaultConfig
        if !keepCustomName {
            group.name = type.label
        }
        group.structureSource = .userConfirmed
        groups[key] = group
    }

    mutating func ungroup(_ key: String) {
        for index in exercises.indices where exercises[index].groupKey == key {
            exercises[index].groupKey = nil
        }
        groups.removeValue(forKey: key)
        if formatGroupKey == key {
            formatGroupKey = nil
        }
    }

    /// Delete a mistaken superset / tri-set (members included) and pin a fresh empty
    /// group with the same display name so format-first building continues — does
    /// **not** fall back to ungrouped straight-set adds.
    @discardableResult
    mutating func discardAndRepinSupersetGroup(_ key: String) -> String? {
        guard let group = groups[key], group.type == .superset else { return nil }
        let preferredName: String = {
            if group.name.localizedCaseInsensitiveContains("tri") { return "Tri-set" }
            let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Superset" : trimmed
        }()
        exercises.removeAll { $0.groupKey == key }
        groups.removeValue(forKey: key)
        if formatGroupKey == key {
            formatGroupKey = nil
        }
        return beginNextSupersetGroup(preferredName: preferredName)
    }

    /// Pin an existing group as the add destination (resume after the pin was lost).
    mutating func focusFormatGroup(_ key: String) {
        guard groups[key] != nil else { return }
        formatGroupKey = key
    }

    mutating func removeFromSuperset(_ exerciseID: String) {
        updateExercise(exerciseID) { $0.groupKey = nil }
        pruneEmptyGroups()
    }

    /// Hevy "Superset X with:" — src moves adjacent to target and joins/creates group.
    /// Three or more members keep the same structure type but display as a Tri-set.
    mutating func pairSuperset(sourceID: String, targetID: String) {
        guard let source = exercises.first(where: { $0.id == sourceID }),
              let target = exercises.first(where: { $0.id == targetID }) else { return }

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
            updateExercise(targetID) { $0.groupKey = createdKey }
        }

        guard let key else { return }
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
        refreshSupersetGroupLabel(key)
        pruneEmptyGroups()
    }

    /// Auto labels: keep an intentional Tri-set name while building (1–2 moves),
    /// upgrade a Superset → Tri-set at 3+, never downgrade Tri-set → Superset.
    mutating func refreshSupersetGroupLabel(_ key: String) {
        guard var group = groups[key], group.type == .superset else { return }
        let memberCount = exercises.filter { $0.groupKey == key }.count
        let autoNames: Set<String> = ["Superset", "Tri-set", "Tri-sets"]
        guard autoNames.contains(group.name) || group.name.isEmpty else { return }
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

    mutating func moveExercise(from fromID: String, to toID: String) {
        guard fromID != toID,
              let fromIndex = exercises.firstIndex(where: { $0.id == fromID }),
              let toIndex = exercises.firstIndex(where: { $0.id == toID }) else { return }
        let item = exercises.remove(at: fromIndex)
        let adjusted = toIndex > fromIndex ? toIndex - 1 : toIndex
        exercises.insert(item, at: adjusted)
        repairBrokenGroups()
    }

    mutating func reorder(fromOffsets: IndexSet, toOffset: Int) {
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
        repairBrokenGroups()
    }

    /// If a reorder splits a group, clear those groupKeys so runs stay contiguous.
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

    /// Rest intent lives on the row the editor edits; delivery owns end conditions.
    @discardableResult
    mutating func quickAddBetweenSetRest(
        to id: String,
        restSec: Int?,
        restOpen: Bool,
        clearingTombstone: Bool = false
    ) throws -> Bool {
        let validated = try WorkoutEnrichmentMutations.validatedRest(restSec: restSec, restOpen: restOpen)
        if clearingTombstone {
            clearEnrichmentTombstone(.betweenSetRest)
        }
        guard !WorkoutEnrichmentPresence.isTombstoned(
            .betweenSetRest,
            tombstones: enrichmentTombstones
        ) else { return false }
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return false }
        // Ownership is monotonic — never refresh rest the user owns (spec §5 rule a).
        let provenance = exercises[index].fieldProvenance
        guard provenance[WorkoutEnrichmentMutations.restSecKey] != .user,
              provenance[WorkoutEnrichmentMutations.restOpenKey] != .user else { return false }
        try exercises[index].applyEnrichmentDefaultRest(
            restSeconds: validated.restSec,
            restOpen: validated.restOpen
        )
        return true
    }

    /// Warm-up sets are a sibling list — `sets: Int` is untouched. Strength shapes only.
    @discardableResult
    mutating func addDefaultWarmupSets(
        to id: String,
        rows: [WarmupSetRow],
        clearingTombstone: Bool = false
    ) -> Bool {
        guard !rows.isEmpty, let index = exercises.firstIndex(where: { $0.id == id }) else { return false }
        guard exercises[index].sets != nil else { return false }
        guard exercises[index].warmupSets.isEmpty else { return false }
        let exerciseId = exercises[index].exerciseId ?? WorkoutEnrichmentMutations.mintExerciseId()
        if clearingTombstone {
            clearEnrichmentTombstone(.exerciseWarmupSets, exerciseId: exerciseId)
        }
        guard !WorkoutEnrichmentPresence.isTombstoned(
            .exerciseWarmupSets,
            exerciseId: exerciseId,
            tombstones: enrichmentTombstones
        ) else { return false }
        exercises[index].exerciseId = exerciseId
        exercises[index].warmupSets = rows
        return true
    }

    /// Delete = remove content **and** write the tombstone (callers own tombstones).
    mutating func removeSessionWarmup() {
        removeSoftSection(type: .warmup, kind: .sessionWarmup)
    }

    mutating func removeCooldown() {
        removeSoftSection(type: .cooldown, kind: .cooldown)
    }

    mutating func removeBetweenSetRest(from id: String) {
        if let index = exercises.firstIndex(where: { $0.id == id }) {
            exercises[index].clearRestIntent()
        }
        WorkoutEnrichmentMutations.appendTombstone(&enrichmentTombstones, kind: .betweenSetRest)
        enrichmentTombstonesDirty = true
    }

    /// Per-exercise tombstone keys off `exercise_id` (rename-safe), so mint when missing.
    @discardableResult
    mutating func removeWarmupSets(from id: String) -> String? {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return nil }
        let exerciseId = exercises[index].exerciseId ?? WorkoutEnrichmentMutations.mintExerciseId()
        exercises[index].exerciseId = exerciseId
        exercises[index].warmupSets = []
        WorkoutEnrichmentMutations.appendTombstone(
            &enrichmentTombstones,
            kind: .exerciseWarmupSets,
            exerciseId: exerciseId
        )
        enrichmentTombstonesDirty = true
        return exerciseId
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

    /// Save path — stable ids for tombstones written after this save.
    mutating func mintMissingExerciseIDs() {
        for index in exercises.indices where exercises[index].exerciseId == nil {
            exercises[index].exerciseId = WorkoutEnrichmentMutations.mintExerciseId()
        }
    }

    private mutating func quickAddSoftSection(
        type: EditorV2GroupType,
        kind: EnrichmentKind,
        activities: [EnrichmentActivity],
        prepend: Bool,
        clearingTombstone: Bool
    ) -> Bool {
        guard !activities.isEmpty else { return false }
        guard !groups.values.contains(where: { $0.type == type }) else { return false }
        if clearingTombstone {
            clearEnrichmentTombstone(kind)
        }
        guard !WorkoutEnrichmentPresence.isTombstoned(kind, tombstones: enrichmentTombstones) else {
            return false
        }

        let key = "\(kind.rawValue)-\(UUID().uuidString)"
        groups[key] = EditorV2Group(
            id: key,
            type: type,
            name: type.label,
            config: type.defaultConfig,
            structureSource: .enrichmentDefault,
            enrichmentKind: kind
        )
        let rows = activities.map { activity in
            EditorV2Exercise(
                name: activity.name,
                durationSeconds: activity.durationSec,
                groupKey: key,
                structureSource: activity.structureSource
            )
        }
        if prepend {
            exercises.insert(contentsOf: rows, at: 0)
        } else {
            exercises.append(contentsOf: rows)
        }
        return true
    }

    private mutating func removeSoftSection(type: EditorV2GroupType, kind: EnrichmentKind) {
        let keys = Set(groups.filter { $0.value.type == type }.keys)
        if !keys.isEmpty {
            exercises.removeAll { exercise in
                guard let groupKey = exercise.groupKey else { return false }
                return keys.contains(groupKey)
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
                if let ex = exercises[id], ex.name == name {
                    return ex
                }
            case .group(let key):
                if let group = groups[key], let lastID = group.memberIDs.last,
                   let ex = exercises[lastID], ex.name == name {
                    return ex
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
        _ = apply(.move(fromID, to: toIndex))
    }
    
    mutating func reorder(fromOffsets: IndexSet, toOffset: Int) {
        _ = apply(.reorder(fromOffsets: fromOffsets, toOffset: toOffset))
    }
    
    mutating func replaceExercise(_ id: String, with name: String) {
        _ = apply(.replaceExercise(id, with: name))
    }
    
    mutating func removeExercise(_ id: String) {
        _ = apply(.removeExercise(id))
    }
    
    mutating func addSet(to id: String) {
        _ = apply(.addSet(to: id))
    }
    
    mutating func switchGroupType(_ key: String, to type: EditorV2GroupType) {
        _ = apply(.switchGroupType(key, type))
    }
    
    mutating func updateExercise(_ id: String, patch: (inout EditorV2Exercise) -> Void) {
        guard var exercise = exercises[id] else { return }
        patch(&exercise)
        _ = apply(.updatePrescription(id, exercise))
    }
}
