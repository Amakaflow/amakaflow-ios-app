//
//  WorkoutBandGrouping+Sections.swift
//  AmakaFlow
//
//  AMA-2395 — how a stored block is TITLED and COLOURED. Nothing here changes
//  what a block contains or where it sits.
//
//  Structure vocabulary comes from the block's own `structure` field, never
//  from guessing at its contents:
//
//    · a circuit is several stations rotated as a group
//    · a superset is a pair worked back to back
//    · one exercise on its own is straight sets — never a circuit, whatever
//      the stored structure claims, because one station cannot be a circuit
//
//  Absence of rest carries NO structural meaning. Most library workouts record
//  no rest at all; rest is added when a workout is prepared for a watch. So we
//  never say anything about rest we were not told.
//

import Foundation

extension WorkoutBandGrouping {
    // MARK: - Titles

    /// The block's own label, plus a structure descriptor when the block is a
    /// genuine multi-station format. Empty string = render no heading at all.
    static func title(for block: Block) -> String {
        let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if isWarmupLabel(label) { return "WARM-UP" }
        if isCooldownLabel(label) { return "COOLDOWN" }

        let descriptor = structureDescriptor(for: block)
        guard !label.isEmpty, !isGenericLabel(label) else {
            // No usable label of its own: show the format if there is one,
            // otherwise nothing. We never manufacture a name.
            return descriptor ?? ""
        }
        return [label.uppercased(), descriptor].compactMap { $0 }.joined(separator: " · ")
    }

    /// `CIRCUIT · 4 ROUNDS`, `SUPERSET × 3`, `EMOM 24`, `AMRAP 12`, or nil for
    /// straight sets. A single-exercise block never gets one: one station is
    /// not a circuit and cannot be a superset.
    static func structureDescriptor(for block: Block) -> String? {
        let rounds = max(1, block.rounds)
        guard block.exercises.count > 1 else { return nil }

        switch block.structure {
        case .straight:
            return nil
        case .circuit, .timedCircuit:
            return rounds > 1 ? "CIRCUIT · \(rounds) ROUNDS" : "CIRCUIT"
        case .superset:
            return rounds > 1 ? "SUPERSET × \(rounds)" : "SUPERSET"
        case .emom:
            return "EMOM \(capMinutes(for: block) ?? rounds)"
        case .amrap:
            return "AMRAP \(capMinutes(for: block) ?? rounds)"
        case .tabata:
            return rounds > 1 ? "TABATA · \(rounds) ROUNDS" : "TABATA"
        }
    }

    /// The cap the ESTIMATOR resolved, so header and subtotal always agree.
    private static func capMinutes(for block: Block) -> Int? {
        WorkoutDurationEstimator.capSeconds(for: block).map { $0 / 60 }
    }

    /// Placeholder labels an exporter left behind ("Block 3", "Main"). We drop
    /// them rather than render them — but we never replace them with a guess.
    static func isGenericLabel(_ label: String?) -> Bool {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return true
        }
        return label.range(
            of: #"^(main( block)?|block\s*\d*|section\s*\d*|round\s*\d*([–-]\d+)?|exercises?)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func isWarmupLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        return lower.contains("warm") || lower.contains("primer")
    }

    static func isCooldownLabel(_ label: String) -> Bool {
        label.lowercased().contains("cool")
    }

    // MARK: - Colour

    /// Band colour only — never affects grouping, order or membership.
    static func kind(for block: Block) -> WorkoutBandKind {
        let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isWarmupLabel(label) { return .warmUp }
        if isCooldownLabel(label) { return .cooldown }

        switch WorkoutSportHonesty.dominantModality(of: block.exercises) {
        case .cardioMachine, .run, .bodyweight: return .conditioning
        case .lift, .unknown: return .work
        }
    }
}
