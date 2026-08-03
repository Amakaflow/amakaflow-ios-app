//
//  BuilderV3RunModels.swift
//  AmakaFlow
//
//  AMA-2372 — Run step builder: warmup / work / recover / cooldown / repeat-block.
//  Serializes into the existing `SocialImportBlock` / blocks path so the mapper
//  stays unchanged — a `BuilderV3RunBlock` with `repeatCount > 1` and 2+ steps
//  becomes a `circuit` block; single-step blocks become `warmup` / `cooldown` /
//  `sets` blocks exactly like any other manually-built workout.
//

import Foundation

/// One row inside a run block. Distance and duration are both optional —
/// a step may be time-based ("10 min easy"), distance-based ("400 m"), or both.
enum BuilderV3RunStepKind: String, CaseIterable, Equatable, Sendable {
    case warmup
    case work
    case recover
    case cooldown

    var label: String {
        switch self {
        case .warmup: return "Warm-up"
        case .work: return "Work"
        case .recover: return "Recover"
        case .cooldown: return "Cool-down"
        }
    }

    /// Block type when this kind stands alone (not inside a repeat-block).
    var standaloneBlockType: StructureBlockType {
        switch self {
        case .warmup: return .warmup
        case .cooldown: return .cooldown
        case .work, .recover: return .sets
        }
    }
}

struct BuilderV3RunStep: Identifiable, Equatable, Sendable {
    var id: String
    var kind: BuilderV3RunStepKind
    var name: String
    var durationSeconds: Int?
    var distanceMeters: Int?
    /// Free-text pace / effort target (e.g. "5:00/km", "easy", "5K race pace").
    var paceTarget: String?

    init(
        id: String = UUID().uuidString,
        kind: BuilderV3RunStepKind,
        name: String,
        durationSeconds: Int? = nil,
        distanceMeters: Int? = nil,
        paceTarget: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.paceTarget = paceTarget
    }

    /// Timeline chip line — mirrors `EditorV2Exercise.summaryLine` tone.
    var summaryLine: String {
        var parts: [String] = []
        if let distanceMeters {
            parts.append(distanceMeters >= 1000
                ? String(format: "%.1f km", Double(distanceMeters) / 1000)
                : "\(distanceMeters) m")
        }
        if let durationSeconds {
            parts.append(durationSeconds >= 60 ? "\(durationSeconds / 60) min" : "\(durationSeconds) sec")
        }
        if let paceTarget, !paceTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(paceTarget)
        }
        return parts.joined(separator: " · ")
    }
}

/// A block is either a single standalone step (warmup/cooldown/continuous work)
/// or a repeat-block: `repeatCount` rounds of its child `steps` (work + recover).
struct BuilderV3RunBlock: Identifiable, Equatable, Sendable {
    var id: String
    var repeatCount: Int
    var steps: [BuilderV3RunStep]
    var label: String?

    init(
        id: String = UUID().uuidString,
        repeatCount: Int = 1,
        steps: [BuilderV3RunStep],
        label: String? = nil
    ) {
        self.id = id
        self.repeatCount = max(1, repeatCount)
        self.steps = steps
        self.label = label
    }

    var isRepeatBlock: Bool { repeatCount > 1 }

    /// Timeline label — "6× 400m + recover" or the step's own name for singles.
    var timelineLabel: String {
        if let label, !label.isEmpty { return label }
        guard let first = steps.first else { return "Block" }
        if isRepeatBlock {
            return "\(repeatCount)× " + steps.map(\.name).joined(separator: " + ")
        }
        return first.name
    }
}

struct BuilderV3RunSession: Equatable, Sendable {
    var title: String
    var blocks: [BuilderV3RunBlock]

    init(title: String = "", blocks: [BuilderV3RunBlock] = []) {
        self.title = title
        self.blocks = blocks
    }

    var isBlankDraft: Bool { blocks.isEmpty }

    @discardableResult
    mutating func addWarmup(name: String = "Warm-up jog", durationSeconds: Int = 600) -> BuilderV3RunBlock {
        let block = BuilderV3RunBlock(
            steps: [BuilderV3RunStep(kind: .warmup, name: name, durationSeconds: durationSeconds)]
        )
        blocks.append(block)
        return block
    }

    @discardableResult
    mutating func addCooldown(name: String = "Cool-down walk", durationSeconds: Int = 300) -> BuilderV3RunBlock {
        let block = BuilderV3RunBlock(
            steps: [BuilderV3RunStep(kind: .cooldown, name: name, durationSeconds: durationSeconds)]
        )
        blocks.append(block)
        return block
    }

    @discardableResult
    mutating func addStandaloneWork(
        name: String,
        durationSeconds: Int? = nil,
        distanceMeters: Int? = nil,
        paceTarget: String? = nil
    ) -> BuilderV3RunBlock {
        let block = BuilderV3RunBlock(
            steps: [
                BuilderV3RunStep(
                    kind: .work,
                    name: name,
                    durationSeconds: durationSeconds,
                    distanceMeters: distanceMeters,
                    paceTarget: paceTarget
                )
            ]
        )
        blocks.append(block)
        return block
    }

    @discardableResult
    mutating func addRepeatBlock(
        repeatCount: Int,
        work: BuilderV3RunStep,
        recover: BuilderV3RunStep?
    ) -> BuilderV3RunBlock {
        var steps = [work]
        if let recover { steps.append(recover) }
        let block = BuilderV3RunBlock(repeatCount: repeatCount, steps: steps)
        blocks.append(block)
        return block
    }

    mutating func removeBlock(_ id: String) {
        blocks.removeAll { $0.id == id }
    }

    mutating func updateBlock(_ id: String, patch: (inout BuilderV3RunBlock) -> Void) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        patch(&blocks[index])
    }

    /// Mirrors `EditorV2Session.reorder` — no SwiftUI dependency in this pure model.
    mutating func moveBlock(fromOffsets: IndexSet, toOffset: Int) {
        var items = blocks
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
        blocks = items
    }
}

// MARK: - Persistence (existing SocialImportBlock/blocks path — mapper unchanged)

extension BuilderV3RunSession {
    func toSocialImportBlocks() -> [SocialImportBlock] {
        blocks.map { block in
            let exercises = block.steps.map(\.asSocialImportExercise)
            let type: StructureBlockType = block.isRepeatBlock
                ? .circuit
                : (block.steps.first?.kind.standaloneBlockType ?? .sets)
            return SocialImportBlock(
                label: block.timelineLabel,
                rounds: block.repeatCount,
                exercises: exercises,
                type: type.rawValue,
                structureSource: StructureSource.userConfirmed.rawValue
            )
        }
    }

    func toSaveIntervals() -> [WorkoutSaveInterval] {
        blocks.flatMap { block in
            block.steps.map { step -> WorkoutSaveInterval in
                let type: String
                switch step.kind {
                case .warmup: type = "warmup"
                case .cooldown: type = "cooldown"
                case .work, .recover: type = step.distanceMeters != nil ? "distance" : "time"
                }
                return WorkoutSaveInterval(
                    type: type,
                    name: step.name,
                    seconds: step.durationSeconds,
                    meters: step.distanceMeters,
                    target: step.paceTarget
                )
            }
        }
    }
}

private extension BuilderV3RunStep {
    var asSocialImportExercise: SocialImportExercise {
        SocialImportExercise(
            name: name,
            seconds: durationSeconds,
            distanceMeters: distanceMeters,
            load: paceTarget,
            structureSource: StructureSource.userConfirmed.rawValue
        )
    }
}

// MARK: - Run seeds (Intervals / Tempo / Long run / Race pace)

enum BuilderV3RunRegistry {
    static func makeRunSession(for seed: BuilderV3TypeSeed) -> BuilderV3RunSession {
        var session = BuilderV3RunSession()
        if let defaultTitle = seed.defaultTitle {
            session.title = defaultTitle
        }
        switch seed.id {
        case BuilderV3TypeRegistry.intervals.id:
            session.addWarmup()
            session.addRepeatBlock(
                repeatCount: 6,
                work: BuilderV3RunStep(kind: .work, name: "400 m", distanceMeters: 400, paceTarget: "5K pace"),
                recover: BuilderV3RunStep(kind: .recover, name: "Recover", durationSeconds: 90, paceTarget: "easy")
            )
            session.addCooldown()
        case BuilderV3TypeRegistry.tempo.id:
            session.addWarmup()
            session.addStandaloneWork(
                name: "Tempo run",
                durationSeconds: 1200,
                paceTarget: "comfortably hard"
            )
            session.addCooldown()
        case BuilderV3TypeRegistry.longRun.id:
            session.addWarmup(durationSeconds: 300)
            session.addStandaloneWork(
                name: "Long run",
                distanceMeters: 10000,
                paceTarget: "easy"
            )
            session.addCooldown(durationSeconds: 300)
        case BuilderV3TypeRegistry.racePace.id:
            session.addWarmup()
            session.addRepeatBlock(
                repeatCount: 4,
                work: BuilderV3RunStep(kind: .work, name: "1000 m", distanceMeters: 1000, paceTarget: "race pace"),
                recover: BuilderV3RunStep(kind: .recover, name: "Recover", durationSeconds: 120, paceTarget: "easy")
            )
            session.addCooldown()
        default:
            break
        }
        return session
    }
}
