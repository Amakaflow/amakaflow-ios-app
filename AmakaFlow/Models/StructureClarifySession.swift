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
        let line = PrescriptionFormatter.clarifyLine(for: model)
        return line.isEmpty ? "—" : line
    }

    static func restMeta(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            let mins = seconds / 60
            return "\(mins) MIN REST"
        }
        return "\(seconds)S REST"
    }
}

extension PrescriptionFormatter {
    /// AMA-2305 clarify rows — same resolver as detail / editor summary.
    static func effective(from model: StructureExerciseModel) -> EffectivePrescription {
        let plainReps = model.reps
        let repsRange = plainReps == nil ? RepsRange.parse(model.notes) : nil
        var secondary = secondaryParts(
            load: nil,
            notes: plainReps == nil && repsRange == nil ? model.notes : nil,
            restSeconds: model.restSec,
            rangeQualifier: repsRange?.qualifier
        )

        let primary = resolvePrimaryMetric(
            PrescriptionMetricInputs(
                durationSeconds: nil,
                distanceMeters: model.distanceM,
                calories: nil,
                plainReps: plainReps,
                repsRange: repsRange,
                sets: model.sets
            )
        )

        if case .repsRange(let range, _) = primary, let qualifier = range.qualifier {
            if !secondary.contains(qualifier) {
                secondary.append(qualifier)
            }
        }

        return EffectivePrescription(primary: primary, secondary: secondary)
    }

    static func clarifyLine(for model: StructureExerciseModel) -> String {
        line(effective(from: model)).uppercased()
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
}
