//
//  StructureClarifySession.swift
//  AmakaFlow
//
//  AMA-2305 / ADR-017 — pure state machine for the "Check the structure" step.
//  Hard guards: never persist inferred unconfirmed; Leave flat = user_confirmed;
//  re-apply replaces, never stacks.
//

import Foundation

enum StructureClarifyStatus: Equatable, Sendable {
    /// Parser / note suggestion awaiting ✓.
    case pending
    /// User tapped Confirm (or chip-grouped).
    case confirmed
}

struct StructureClarifyExercise: Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var summary: String
    var sets: Int?
    var reps: Int?
    var restSec: Int?
    var distanceM: Int?
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        sets: Int? = nil,
        reps: Int? = nil,
        restSec: Int? = nil,
        distanceM: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.sets = sets
        self.reps = reps
        self.restSec = restSec
        self.distanceM = distanceM
        self.notes = notes
    }

    func toModel() -> StructureExerciseModel {
        StructureExerciseModel(
            name: name,
            sets: sets,
            reps: reps,
            restSec: restSec,
            distanceM: distanceM,
            notes: notes
        )
    }

    static func summary(for model: StructureExerciseModel) -> String {
        var parts: [String] = []
        if let distance = model.distanceM, distance > 0 {
            parts.append("\(distance) M")
        }
        if let sets = model.sets, let reps = model.reps {
            parts.append("\(sets) × \(reps)")
        } else if let reps = model.reps {
            parts.append("\(reps) REPS")
        } else if let sets = model.sets {
            parts.append("\(sets) SETS")
        }
        if let rest = model.restSec, rest > 0 {
            parts.append(restMeta(rest))
        }
        if let notes = model.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(notes.uppercased())
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    static func restMeta(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            let mins = seconds / 60
            return "\(mins) MIN REST"
        }
        return "\(seconds)S REST"
    }
}

struct StructureClarifyGroup: Equatable, Identifiable, Sendable {
    let id: UUID
    var type: StructureBlockType
    var label: String
    var rounds: Int?
    var restSec: Int?
    var exercises: [StructureClarifyExercise]
    var status: StructureClarifyStatus
    /// Provenance driving the UI tag (inferred / explicit / user_note / …).
    var structureSource: StructureSource

    init(
        id: UUID = UUID(),
        type: StructureBlockType,
        label: String,
        rounds: Int? = nil,
        restSec: Int? = nil,
        exercises: [StructureClarifyExercise],
        status: StructureClarifyStatus = .pending,
        structureSource: StructureSource = .inferred
    ) {
        self.id = id
        self.type = type.canonical
        self.label = label
        self.rounds = rounds
        self.restSec = restSec
        self.exercises = exercises
        self.status = status
        self.structureSource = structureSource
    }

    var metaLine: String {
        var parts: [String] = []
        if let rounds, rounds > 0 {
            parts.append("\(rounds) ROUNDS")
        }
        if let restSec, restSec > 0 {
            parts.append(StructureClarifyExercise.restMeta(restSec))
        } else if type.canonical == .circuit || type.canonical == .forTime {
            parts.append("FOR TIME")
        }
        return parts.joined(separator: " · ")
    }

    var provenanceTag: String {
        switch status {
        case .confirmed:
            return "\(type.displayLabel.uppercased()) ✓"
        case .pending:
            if structureSource == .userNote {
                return "FROM YOUR NOTE · \(type.displayLabel.uppercased())"
            }
            return "SUGGESTED · \(type.displayLabel.uppercased())"
        }
    }

    func markIndex(at index: Int) -> String {
        switch type.canonical {
        case .superset:
            return "A\(index + 1)"
        default:
            return "\(index + 1)"
        }
    }
}

struct StructureClarifyRow: Equatable, Identifiable, Sendable {
    let id: UUID
    var exercise: StructureClarifyExercise

    init(id: UUID = UUID(), exercise: StructureClarifyExercise) {
        self.id = id
        self.exercise = exercise
    }
}

enum StructureClarifyUnit: Equatable, Identifiable, Sendable {
    case group(StructureClarifyGroup)
    case row(StructureClarifyRow)

    var id: UUID {
        switch self {
        case .group(let group): return group.id
        case .row(let row): return row.id
        }
    }
}

/// Pure clarify session — no networking, no SwiftUI.
struct StructureClarifySession: Equatable, Sendable {
    var units: [StructureClarifyUnit]
    var selectedRowIDs: Set<UUID>

    init(units: [StructureClarifyUnit] = [], selectedRowIDs: Set<UUID> = []) {
        self.units = units
        self.selectedRowIDs = selectedRowIDs
    }

    var groups: [StructureClarifyGroup] {
        units.compactMap {
            if case .group(let group) = $0 { return group }
            return nil
        }
    }

    var pendingGroupCount: Int {
        groups.filter { $0.status == .pending }.count
    }

    var confirmedGroupCount: Int {
        groups.filter { $0.status == .confirmed }.count
    }

    var exerciseCount: Int {
        units.reduce(0) { partial, unit in
            switch unit {
            case .group(let group): return partial + group.exercises.count
            case .row: return partial + 1
            }
        }
    }

    // MARK: - Mutations

    mutating func confirm(groupID: UUID) {
        units = units.map { unit in
            guard case .group(var group) = unit, group.id == groupID else { return unit }
            group.status = .confirmed
            if group.structureSource != .userNote {
                group.structureSource = .userConfirmed
            }
            return .group(group)
        }
    }

    mutating func confirmAll() {
        for group in groups where group.status == .pending {
            confirm(groupID: group.id)
        }
    }

    /// Undo / Ungroup — dissolve to flat rows (replace, never stack leftovers).
    mutating func undo(groupID: UUID) {
        units = units.flatMap { unit -> [StructureClarifyUnit] in
            guard case .group(let group) = unit, group.id == groupID else { return [unit] }
            return group.exercises.map { .row(StructureClarifyRow(exercise: $0)) }
        }
        selectedRowIDs = []
    }

    mutating func bumpRounds(groupID: UUID, delta: Int) {
        units = units.map { unit in
            guard case .group(var group) = unit, group.id == groupID else { return unit }
            let current = group.rounds ?? 1
            group.rounds = min(20, max(1, current + delta))
            return .group(group)
        }
    }

    mutating func toggleRowSelection(_ rowID: UUID) {
        guard units.contains(where: {
            if case .row(let row) = $0 { return row.id == rowID }
            return false
        }) else { return }
        if selectedRowIDs.contains(rowID) {
            selectedRowIDs.remove(rowID)
        } else {
            selectedRowIDs.insert(rowID)
        }
    }

    mutating func clearSelection() {
        selectedRowIDs = []
    }

    /// Chip bar — group 2+ selected flat rows as a confirmed structure.
    mutating func groupSelected(as type: StructureBlockType) {
        let selected = units.compactMap { unit -> StructureClarifyRow? in
            guard case .row(let row) = unit, selectedRowIDs.contains(row.id) else { return nil }
            return row
        }
        guard selected.count >= 2 else { return }

        let group = StructureClarifyGroup(
            type: type,
            label: selected.map(\.exercise.name).joined(separator: " + "),
            rounds: type.canonical == .superset ? 3 : 4,
            restSec: type.canonical == .superset ? 60 : nil,
            exercises: selected.map(\.exercise),
            status: .confirmed,
            structureSource: .userConfirmed
        )

        var out: [StructureClarifyUnit] = []
        var placed = false
        for unit in units {
            if case .row(let row) = unit, selectedRowIDs.contains(row.id) {
                if !placed {
                    out.append(.group(group))
                    placed = true
                }
                continue
            }
            out.append(unit)
        }
        units = out
        selectedRowIDs = []
    }

    /// Replace session from apply-structure result (idempotent — never stacks).
    mutating func replace(withAppliedBlocks blocks: [StructureBlockModel]) {
        units = Self.units(fromBlocks: blocks, pendingSourceOverride: nil)
        selectedRowIDs = []
    }

    // MARK: - Save payloads (hard guards)

    /// Build blocks for Library save. Never includes unconfirmed inferred structure.
    func blocksForSave(leaveFlat: Bool) -> [StructureBlockModel] {
        if leaveFlat {
            return flatBlocks(structureSource: .userConfirmed)
        }

        var result: [StructureBlockModel] = []
        for unit in units {
            switch unit {
            case .group(let group):
                if group.status == .confirmed {
                    result.append(
                        StructureBlockModel(
                            type: group.type.canonical,
                            label: group.label,
                            rounds: group.rounds,
                            restSec: group.restSec,
                            exercises: group.exercises.map { $0.toModel() },
                            structureSource: group.structureSource == .userNote ? .userNote : .userConfirmed
                        )
                    )
                } else {
                    // Unconfirmed suggestions save flat — never persist inferred.
                    for exercise in group.exercises {
                        result.append(
                            StructureBlockModel(
                                type: .sets,
                                label: nil,
                                rounds: nil,
                                restSec: exercise.restSec,
                                exercises: [exercise.toModel()],
                                structureSource: .unknown
                            )
                        )
                    }
                }
            case .row(let row):
                result.append(
                    StructureBlockModel(
                        type: .sets,
                        label: nil,
                        rounds: nil,
                        restSec: row.exercise.restSec,
                        exercises: [row.exercise.toModel()],
                        structureSource: .unknown
                    )
                )
            }
        }
        return result
    }

    /// Current blocks for apply-structure (pre-confirm working set).
    func workingBlocksForApply() -> [StructureBlockModel] {
        units.flatMap { unit -> [StructureBlockModel] in
            switch unit {
            case .group(let group):
                return [
                    StructureBlockModel(
                        type: group.type.canonical,
                        label: group.label,
                        rounds: group.rounds,
                        restSec: group.restSec,
                        exercises: group.exercises.map { $0.toModel() },
                        structureSource: group.structureSource
                    )
                ]
            case .row(let row):
                return [
                    StructureBlockModel(
                        type: .sets,
                        exercises: [row.exercise.toModel()],
                        structureSource: .unknown
                    )
                ]
            }
        }
    }

    private func flatBlocks(structureSource: StructureSource) -> [StructureBlockModel] {
        units.flatMap { unit -> [StructureBlockModel] in
            switch unit {
            case .group(let group):
                return group.exercises.map {
                    StructureBlockModel(
                        type: .sets,
                        exercises: [$0.toModel()],
                        structureSource: structureSource
                    )
                }
            case .row(let row):
                return [
                    StructureBlockModel(
                        type: .sets,
                        exercises: [row.exercise.toModel()],
                        structureSource: structureSource
                    )
                ]
            }
        }
    }

    // MARK: - Factories

    /// Build session from BFF suggest result (suggestions as pending groups; curls stay flat).
    static func fromSuggest(
        _ result: StructureSuggestResult,
        fallbackExercises: [StructureExerciseModel] = []
    ) -> StructureClarifySession {
        let exercises = result.exercises.isEmpty ? fallbackExercises : result.exercises
        guard !exercises.isEmpty else {
            return StructureClarifySession()
        }

        // Prefer pre-built blocks when backend already materialised suggestions as blocks
        // with inferred/explicit provenance (still pending confirmation).
        if !result.blocks.isEmpty,
           result.blocks.contains(where: { $0.structureSource == .inferred || $0.structureSource == .explicit }) {
            return StructureClarifySession(units: units(fromBlocks: result.blocks, pendingSourceOverride: nil))
        }

        var claimed = Set<Int>()
        var units: [StructureClarifyUnit] = []
        let suggestions = result.suggestions.sorted { lhs, rhs in
            (lhs.exerciseIndices.min() ?? Int.max) < (rhs.exerciseIndices.min() ?? Int.max)
        }

        var cursor = 0
        while cursor < exercises.count {
            if claimed.contains(cursor) {
                cursor += 1
                continue
            }

            if let suggestion = suggestions.first(where: { sug in
                guard let first = sug.exerciseIndices.min() else { return false }
                return first == cursor && sug.exerciseIndices.allSatisfy { !claimed.contains($0) }
            }) {
                let indices = suggestion.exerciseIndices.sorted()
                let members: [StructureClarifyExercise] = indices.compactMap { idx in
                    guard exercises.indices.contains(idx) else { return nil }
                    claimed.insert(idx)
                    let model = exercises[idx]
                    return StructureClarifyExercise(
                        name: model.name,
                        summary: StructureClarifyExercise.summary(for: model),
                        sets: model.sets,
                        reps: model.reps,
                        restSec: model.restSec,
                        distanceM: model.distanceM,
                        notes: model.notes
                    )
                }
                if members.count >= 1 {
                    let label = suggestion.label
                        ?? members.map(\.name).joined(separator: " + ")
                    units.append(
                        .group(
                            StructureClarifyGroup(
                                type: suggestion.type,
                                label: label,
                                rounds: suggestion.rounds,
                                restSec: suggestion.restSec,
                                exercises: members,
                                status: .pending,
                                structureSource: suggestion.structureSource
                            )
                        )
                    )
                }
                cursor += 1
                continue
            }

            let model = exercises[cursor]
            claimed.insert(cursor)
            units.append(
                .row(
                    StructureClarifyRow(
                        exercise: StructureClarifyExercise(
                            name: model.name,
                            summary: StructureClarifyExercise.summary(for: model),
                            sets: model.sets,
                            reps: model.reps,
                            restSec: model.restSec,
                            distanceM: model.distanceM,
                            notes: model.notes
                        )
                    )
                )
            )
            cursor += 1
        }

        return StructureClarifySession(units: units)
    }

    /// Build from apply response — noted groups stay pending with `user_note` provenance.
    static func fromAppliedBlocks(_ blocks: [StructureBlockModel]) -> StructureClarifySession {
        StructureClarifySession(units: units(fromBlocks: blocks, pendingSourceOverride: nil))
    }

    private static func units(
        fromBlocks blocks: [StructureBlockModel],
        pendingSourceOverride: StructureSource?
    ) -> [StructureClarifyUnit] {
        blocks.flatMap { block -> [StructureClarifyUnit] in
            let exercises = block.exercises.map { model in
                StructureClarifyExercise(
                    name: model.name,
                    summary: StructureClarifyExercise.summary(for: model),
                    sets: model.sets,
                    reps: model.reps,
                    restSec: model.restSec,
                    distanceM: model.distanceM,
                    notes: model.notes
                )
            }
            guard !exercises.isEmpty else { return [] }

            let source = pendingSourceOverride ?? block.structureSource
            let isFlatSets = block.type.canonical == .sets && exercises.count == 1
                && (source == .unknown || source == .userConfirmed)

            if isFlatSets && source != .userNote {
                return exercises.map { .row(StructureClarifyRow(exercise: $0)) }
            }

            let status: StructureClarifyStatus = {
                switch source {
                case .userConfirmed:
                    return .confirmed
                case .userNote, .inferred, .explicit, .unknown:
                    return .pending
                }
            }()

            // Flat user_confirmed from leave-flat should stay rows when saving again —
            // but for display after leave-flat we usually dismiss. Treat multi-exercise
            // or typed blocks as groups.
            if block.type.canonical == .sets && exercises.count == 1 && source == .userConfirmed {
                return exercises.map { .row(StructureClarifyRow(exercise: $0)) }
            }

            return [
                .group(
                    StructureClarifyGroup(
                        type: block.type,
                        label: block.label ?? exercises.map(\.name).joined(separator: " + "),
                        rounds: block.rounds,
                        restSec: block.restSec,
                        exercises: exercises,
                        status: status,
                        structureSource: source == .userConfirmed && status == .pending
                            ? .inferred
                            : source
                    )
                )
            ]
        }
    }
}
