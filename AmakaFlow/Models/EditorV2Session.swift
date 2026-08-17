//
//  EditorV2Session.swift
//  AmakaFlow
//
//  AMA-2307 — pure Editor v2 state: flat exercises + group dict (screens-editor2.jsx).
//
// swiftlint:disable file_length

import Foundation

/// AMA-2443: Pre-state snapshot for undo. Captures the state before a command runs.
struct EditorV2SessionSnapshot: Equatable, Sendable {
    let title: String
    let order: [EditorV2Row]
    let groups: [String: EditorV2Group]
    let exercises: [String: EditorV2Exercise]
    let formatGroupKey: String?
    let enrichmentTombstones: [EnrichmentTombstone]
    let enrichmentTombstonesDirty: Bool
    
    init(from session: EditorV2Session) {
        self.title = session.title
        self.order = session.order
        self.groups = session.groups
        self.exercises = session.exercises
        self.formatGroupKey = session.formatGroupKey
        self.enrichmentTombstones = session.enrichmentTombstones
        self.enrichmentTombstonesDirty = session.enrichmentTombstonesDirty
    }
    
    func restore(to session: inout EditorV2Session) {
        session.title = title
        session.order = order
        session.groups = groups
        session.exercises = exercises
        session.formatGroupKey = formatGroupKey
        session.enrichmentTombstones = enrichmentTombstones
        session.enrichmentTombstonesDirty = enrichmentTombstonesDirty
    }
}

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
    /// AMA-2443: Session Memento undo stack (capped at 50 snapshots).
    private var undoStack: [EditorV2SessionSnapshot] = []

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
                // Skip empty groups - canvas uses formatGroupKey directly for insertion slot
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
    
    /// AMA-2443: Undo the last command by restoring the previous snapshot.
    /// Returns true if undo succeeded, false if the stack was empty.
    mutating func undo() -> Bool {
        guard !undoStack.isEmpty else { return false }
        let snapshot = undoStack.removeLast()
        snapshot.restore(to: &self)
        // Re-run validation after restore per spec §Memento
        let validation = validateD2()
        assert(validation == .applied, "Undo produced invalid state: \(validation)")
        return true
    }
    
    /// AMA-2443: Check if undo is available (stack not empty).
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    /// AMA-2443: Clear undo history (called on save/reload).
    mutating func clearUndoHistory() {
        undoStack.removeAll()
    }
}

// MARK: - Undo grouping (AMA-2443 sheet commit)

extension EditorV2Session {
    /// Begin an undo group. Commands within the group will be captured as a single undo entry.
    /// The snapshot is taken when the group begins, before any commands run.
    mutating func beginUndoGroup() {
        pushUndoSnapshot(EditorV2SessionSnapshot(from: self))
    }

    /// The only writer of the (private) undo stack — apply() and group
    /// begins both come through here so the cap lives in one place.
    mutating func pushUndoSnapshot(_ snapshot: EditorV2SessionSnapshot) {
        undoStack.append(snapshot)
        // Cap the stack at 50
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }
    
    /// Drop the most recent snapshot — used when a begun group turned out
    /// to change nothing, so UNDO never pops a do-nothing entry.
    mutating func discardLastUndoSnapshot() {
        guard !undoStack.isEmpty else { return }
        undoStack.removeLast()
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
        let result = apply(.quickAddSoftSection(
            .sessionWarmup,
            activities: activities,
            clearingTombstone: clearingTombstone
        ))
        return result == .applied
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
        let result = apply(.quickAddSoftSection(
            .cooldown,
            activities: activities,
            clearingTombstone: clearingTombstone
        ))
        return result == .applied
    }
    
    /// Delete = remove content **and** write the tombstone (callers own tombstones).
    mutating func removeSessionWarmup() {
        _ = apply(.removeSoftSection(.warmup, .sessionWarmup))
    }

    mutating func removeCooldown() {
        _ = apply(.removeSoftSection(.cooldown, .cooldown))
    }

    /// Warm-up sets are a sibling list — `sets: Int` is untouched. Strength shapes only.
    @discardableResult
    mutating func addDefaultWarmupSets(
        to id: String,
        rows: [WarmupSetRow],
        clearingTombstone: Bool = false
    ) -> Bool {
        let result = apply(.addWarmupSets(
            exerciseID: id,
            rows: rows,
            clearingTombstone: clearingTombstone
        ))
        return result == .applied
    }

    /// Per-exercise tombstone keys off `exercise_id` (rename-safe), so mint when missing.
    @discardableResult
    mutating func removeWarmupSets(from id: String) -> String? {
        guard let exercise = exercises[id] else { return nil }
        let exerciseId = exercise.exerciseId ?? WorkoutEnrichmentMutations.mintExerciseId()
        _ = apply(.removeWarmupSets(exerciseID: id))
        return exerciseId
    }

    /// Save path — stable ids for tombstones written after this save.
    mutating func mintMissingExerciseIDs() {
        for id in exercises.keys where exercises[id]?.exerciseId == nil {
            if var exercise = exercises[id] {
                exercise.exerciseId = WorkoutEnrichmentMutations.mintExerciseId()
                exercises[id] = exercise
            }
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
        _ = apply(.beginNextSupersetGroup(preferredName: preferredName))
        return formatGroupKey ?? "fmt"
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
