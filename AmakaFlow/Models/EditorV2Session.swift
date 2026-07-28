//
//  EditorV2Session.swift
//  AmakaFlow
//
//  AMA-2307 — pure Editor v2 state: flat exercises + group dict (screens-editor2.jsx).
//

import Foundation

struct EditorV2Session: Equatable, Sendable {
    var title: String
    var groups: [String: EditorV2Group]
    var exercises: [EditorV2Exercise]
    /// Pinned format group key from empty-state chips (`fmt` in the prototype).
    var formatGroupKey: String?
    /// AMA-2336 — workout-level enrichment deletes. Written here, read by enrich.
    var enrichmentTombstones: [EnrichmentTombstone]

    init(
        title: String = "",
        groups: [String: EditorV2Group] = [:],
        exercises: [EditorV2Exercise] = [],
        formatGroupKey: String? = nil,
        enrichmentTombstones: [EnrichmentTombstone] = []
    ) {
        self.title = title
        self.groups = groups
        self.exercises = exercises
        self.formatGroupKey = formatGroupKey
        self.enrichmentTombstones = enrichmentTombstones
    }

    var runs: [EditorV2Run] {
        var result: [EditorV2Run] = []
        for exercise in exercises {
            if let key = exercise.groupKey,
               let last = result.last,
               last.groupKey == key {
                var updated = last
                updated.exercises.append(exercise)
                result[result.count - 1] = updated
            } else {
                result.append(
                    EditorV2Run(
                        id: exercise.groupKey ?? exercise.id,
                        groupKey: exercise.groupKey,
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
    @discardableResult
    mutating func addExercise(named name: String) -> EditorV2Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fmtKey = formatGroupKey
        let fmtType = fmtKey.flatMap { groups[$0]?.type }
        let timed = fmtType.map { $0 != .superset } ?? false
        let exercise: EditorV2Exercise
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

    mutating func removeFromSuperset(_ exerciseID: String) {
        updateExercise(exerciseID) { $0.groupKey = nil }
        pruneEmptyGroups()
    }

    /// Hevy "Superset X with:" — src moves adjacent to target and joins/creates group.
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
        pruneEmptyGroups()
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
        return exerciseId
    }

    /// Push-sheet apply of a tombstoned kind: caller clears, then enrich runs.
    mutating func clearEnrichmentTombstone(_ kind: EnrichmentKind, exerciseId: String? = nil) {
        WorkoutEnrichmentMutations.clearTombstone(
            &enrichmentTombstones,
            kind: kind,
            exerciseId: exerciseId
        )
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
    }
}
