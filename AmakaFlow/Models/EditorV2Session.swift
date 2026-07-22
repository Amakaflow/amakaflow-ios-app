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

    init(
        title: String = "",
        groups: [String: EditorV2Group] = [:],
        exercises: [EditorV2Exercise] = [],
        formatGroupKey: String? = nil
    ) {
        self.title = title
        self.groups = groups
        self.exercises = exercises
        self.formatGroupKey = formatGroupKey
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
            let createdKey = "ss\(Int(Date().timeIntervalSince1970 * 1000) % 100_000)"
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
    }

    mutating func moveExercise(from fromID: String, to toID: String) {
        guard fromID != toID,
              let fromIndex = exercises.firstIndex(where: { $0.id == fromID }),
              let toIndex = exercises.firstIndex(where: { $0.id == toID }) else { return }
        let item = exercises.remove(at: fromIndex)
        let adjusted = toIndex > fromIndex ? toIndex - 1 : toIndex
        exercises.insert(item, at: adjusted)
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
    }

    private mutating func pruneEmptyGroups() {
        let used = Set(exercises.compactMap(\.groupKey))
        for key in groups.keys where !used.contains(key) && key != formatGroupKey {
            groups.removeValue(forKey: key)
        }
    }
}
