//
//  WorkoutBandGrouping+Sections.swift
//  AmakaFlow
//
//  AMA-2395 — how a block becomes a named section, and how a band gets its
//  subtotal. Split out of WorkoutBandGrouping.swift for file length.
//
//  The naming contract lives here: there is no code path that can produce the
//  string "Block N".
//

import Foundation

extension WorkoutBandGrouping {
    // MARK: - Classification

    enum BandRole {
        case warmUp
        case cooldown
        case main
    }

    struct BlockGroup {
        var id: String
        var role: BandRole
        var blocks: [Block]
        var exercises: [Exercise]
        var blockIDs: [String] { blocks.map(\.id) }
        var primary: Block? { blocks.first }
        /// True when several unlabeled blocks were merged into one band.
        var isMerged: Bool { blocks.count > 1 }
    }

    static func classify(_ input: [(block: Block, exercises: [Exercise])]) -> [BlockGroup] {
        input.enumerated().map { index, entry in
            BlockGroup(
                id: entry.block.id,
                role: role(for: entry.block, exercises: entry.exercises, index: index, all: input),
                blocks: [entry.block],
                exercises: entry.exercises
            )
        }
    }

    private static func role(
        for block: Block,
        exercises: [Exercise],
        index: Int,
        all: [(block: Block, exercises: [Exercise])]
    ) -> BandRole {
        let label = (block.label ?? "").lowercased()
        if label.contains("warm") || label.contains("primer") { return .warmUp }
        if label.contains("cool") { return .cooldown }

        // An unlabeled short opener with no loaded work is a warm-up, whatever
        // the exporter called it — that's what makes a 3:00 jump-rope block
        // read as WARM-UP instead of its own nameless section.
        if index == 0, all.count > 1, isGenericLabel(block.label), isShortOpener(exercises) {
            return .warmUp
        }
        return .main
    }

    private static func isShortOpener(_ exercises: [Exercise]) -> Bool {
        guard !exercises.isEmpty else { return false }
        let hasLoadedWork = exercises.contains { exercise in
            WorkoutSportHonesty.modality(for: exercise) == .lift || exercise.load != nil
        }
        guard !hasLoadedWork else { return false }
        let seconds = exercises.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        return seconds > 0 && seconds <= 6 * 60
    }

    /// Consecutive plain single-round unlabeled blocks are one band, not N.
    static func mergeLooseStraightBlocks(_ groups: [BlockGroup]) -> [BlockGroup] {
        var result: [BlockGroup] = []
        for group in groups {
            guard let block = group.primary else { continue }
            let isLoose = group.role == .main
                && block.structure == .straight
                && max(1, block.rounds) == 1
                && isGenericLabel(block.label)
            if isLoose,
               var previous = result.last,
               previous.role == .main,
               let previousBlock = previous.primary,
               previousBlock.structure == .straight,
               max(1, previousBlock.rounds) == 1,
               isGenericLabel(previousBlock.label) {
                previous.blocks.append(block)
                previous.exercises.append(contentsOf: group.exercises)
                result[result.count - 1] = previous
            } else {
                result.append(group)
            }
        }
        return result
    }

    static func isGenericLabel(_ label: String?) -> Bool {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return true
        }
        return label.range(
            of: #"^(main( block)?|block\s*\d*|section\s*\d*|round\s*\d*([–-]\d+)?|amrap|exercises?)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    // MARK: - Titles

    static func title(for group: BlockGroup) -> String {
        guard let block = group.primary else { return "WORK" }
        if group.role == .cooldown { return "COOLDOWN" }
        // A named structure keeps its name AND its shape; anything else is
        // named for what it contains.
        return structureTitle(for: group, block: block) ?? straightTitle(for: group, block: block)
    }

    /// Titles for the structures that name themselves.
    private static func structureTitle(for group: BlockGroup, block: Block) -> String? {
        let rounds = max(1, block.rounds)
        switch block.structure {
        case .emom:
            return "EMOM \(capMinutes(for: block) ?? rounds)"
        case .amrap:
            return "AMRAP \(capMinutes(for: block) ?? rounds)"
        case .tabata:
            return roundsSuffixed("TABATA", rounds: rounds)
        case .circuit, .timedCircuit:
            var title = roundsSuffixed("CIRCUIT", rounds: rounds)
            if rotatesWithoutRest(block) { title += " · ROTATE, NO REST" }
            return title
        case .superset:
            let shape = "SUPERSET × \(rounds)"
            return leadLiftName(in: group.exercises).map { "\($0.uppercased()) · \(shape)" } ?? shape
        case .straight:
            return nil
        }
    }

    /// A plain block: its own label, its one main lift, or its dominant modality.
    private static func straightTitle(for group: BlockGroup, block: Block) -> String {
        let rounds = max(1, block.rounds)
        let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // "For time" is a named shape even on a straight block.
        if label.range(of: #"for\s*time"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return roundsSuffixed("FOR TIME", rounds: rounds)
        }
        if !isGenericLabel(label), !group.isMerged {
            return roundsSuffixed(label.uppercased(), rounds: rounds)
        }
        if let lift = soleMovementName(in: group.exercises) {
            return roundsSuffixed(lift.uppercased(), rounds: rounds)
        }
        return roundsSuffixed(derivedName(for: group.exercises), rounds: rounds)
    }

    /// The cap the ESTIMATOR resolved, so header and subtotal always agree.
    private static func capMinutes(for block: Block) -> Int? {
        WorkoutDurationEstimator.capSeconds(for: block).map { $0 / 60 }
    }

    private static func roundsSuffixed(_ title: String, rounds: Int) -> String {
        rounds > 1 ? "\(title) · \(rounds) ROUNDS" : title
    }

    private static func rotatesWithoutRest(_ block: Block) -> Bool {
        block.exercises.count > 1
            && (block.restBetweenSeconds ?? 0) == 0
            && block.exercises.allSatisfy { ($0.restSeconds ?? 0) == 0 }
    }

    /// The one MAIN LIFT a block is built around, if there is exactly one.
    /// Deliberately lift-only: a block of planks is `CORE`, not `PLANK`.
    private static func soleMovementName(in exercises: [Exercise]) -> String? {
        let names = Set(exercises.map { baseName(of: $0.name).lowercased() })
        guard names.count == 1,
              let first = exercises.first,
              WorkoutSportHonesty.modality(for: first) == .lift else {
            return nil
        }
        return baseName(of: first.name)
    }

    private static func leadLiftName(in exercises: [Exercise]) -> String? {
        let lift = exercises.first { WorkoutSportHonesty.modality(for: $0) == .lift }
        return (lift ?? exercises.first).map { baseName(of: $0.name) }
    }

    /// Untitled mixed blocks are named for what they mostly are.
    private static func derivedName(for exercises: [Exercise]) -> String {
        switch WorkoutSportHonesty.dominantModality(of: exercises) {
        case .cardioMachine, .run: return "CONDITIONING"
        case .bodyweight: return "CORE"
        case .lift, .unknown: return "ACCESSORIES"
        }
    }

    static func kind(for group: BlockGroup) -> WorkoutBandKind {
        switch group.role {
        case .warmUp: return .warmUp
        case .cooldown: return .cooldown
        case .main:
            switch WorkoutSportHonesty.dominantModality(of: group.exercises) {
            case .cardioMachine, .run, .bodyweight: return .conditioning
            case .lift, .unknown: return .work
            }
        }
    }

    // MARK: - Subtotals

    struct PartialBand {
        let id: String
        let title: String
        let kind: WorkoutBandKind
        var rows: [WorkoutBandRow]
        let blockIDs: [String]
        let isWarmUpSink: Bool
    }

    /// Band seconds = its rows' seconds + the overhead (rest between rounds,
    /// transition padding) of the blocks it owns, so the bands still sum to the
    /// workout total even though ramps moved between them.
    static func finalise(
        _ partials: [PartialBand],
        estimate: WorkoutDurationEstimate,
        blocks: [Block]
    ) -> [WorkoutBand] {
        let overheads = blockOverheads(estimate: estimate, blocks: blocks)
        // Every block's overhead is claimed exactly ONCE, by whichever band
        // holds the largest share of its exercises. A strict-majority rule
        // would silently drop the overhead of a block split evenly between two
        // bands, and the subtotals would stop adding up to the total.
        let owners = blockOwners(partials: partials, blocks: blocks)

        return partials.map { partial in
            let exerciseIDs = partial.rows.flatMap(\.exerciseIDs)
            var component = estimate.component(forExerciseIDs: exerciseIDs)
            var seconds = component.seconds
            var isEstimate = component.isEstimate

            for (blockID, ownerID) in owners where ownerID == partial.id {
                seconds += overheads[blockID] ?? 0
                if estimate.seconds(forBlockID: blockID)?.isEstimate == true { isEstimate = true }
            }
            component = WorkoutDurationComponent(id: partial.id, seconds: seconds, isEstimate: isEstimate)

            return WorkoutBand(
                id: partial.id,
                title: partial.title,
                kind: partial.kind,
                rows: partial.rows,
                timeLabel: component.label,
                seconds: seconds,
                isEstimate: isEstimate
            )
        }
    }

    private static func blockOverheads(
        estimate: WorkoutDurationEstimate,
        blocks: [Block]
    ) -> [String: Int] {
        var overheads: [String: Int] = [:]
        for block in blocks {
            let blockSeconds = estimate.seconds(forBlockID: block.id)?.seconds ?? 0
            let exerciseSeconds = block.exercises.reduce(0) {
                $0 + (estimate.seconds(forExerciseID: $1.id)?.seconds ?? 0)
            }
            overheads[block.id] = max(0, blockSeconds - exerciseSeconds)
        }
        return overheads
    }

    /// Maps every non-empty block to the single band that owns its overhead:
    /// the band holding the most of its exercises, ties broken by band order so
    /// the result is deterministic.
    private static func blockOwners(partials: [PartialBand], blocks: [Block]) -> [String: String] {
        let held = partials.map { (id: $0.id, ids: Set($0.rows.flatMap(\.exerciseIDs))) }
        var owners: [String: String] = [:]
        for block in blocks where !block.exercises.isEmpty {
            var bestID: String?
            var bestCount = 0
            for band in held {
                let mine = block.exercises.filter { band.ids.contains($0.id) }.count
                if mine > bestCount {
                    bestCount = mine
                    bestID = band.id
                }
            }
            if let bestID { owners[block.id] = bestID }
        }
        return owners
    }
}
