//
//  ActualsVerifiedCard.swift
//  AmakaFlow
//
//  AMA-2387: verified payoff — callout + WHAT YOU DID · VS PLAN
//  (screens-actuals.jsx SYVerifiedScreen).
//

import SwiftUI

struct ActualsVerifiedDeltaRow: Identifiable, Equatable {
    let id: String
    let name: String
    let actualLine: String
    let deltaLabel: String
    let isAsPlanned: Bool
    let structureHeader: String?
    let structureBlockIndex: Int?
}

enum ActualsVerifiedDeltas {
    static func rows(from exercises: [ExerciseActual]) -> [ActualsVerifiedDeltaRow] {
        exercises.map { exercise in
            let delta = exercise.planDelta
            return ActualsVerifiedDeltaRow(
                id: exercise.id,
                name: exercise.name,
                actualLine: exercise.actualDisplayLine,
                deltaLabel: delta.label,
                isAsPlanned: delta.isAsPlanned,
                structureHeader: exercise.structureHeader,
                structureBlockIndex: exercise.structureBlockIndex
            )
        }
    }

    static func sections(from rows: [ActualsVerifiedDeltaRow]) -> [ActualsVerifiedDeltaSection] {
        ActualsVerifiedDeltaSection.sections(from: rows)
    }

    static func calloutBody(sourceName: String, rpe: Int?) -> String {
        if let rpe {
            return "\(sourceName) metrics + your actuals + RPE \(rpe) — counted once in Progress."
        }
        return "\(sourceName) metrics + your actuals — counted once in Progress."
    }
}

struct ExerciseActualPlanDelta: Equatable {
    let label: String
    let isAsPlanned: Bool
}

extension ExerciseActual {
    var actualDisplayLine: String {
        guard isLogged else { return ActualsCopy.notLogged }
        // Logbook path: show every checked set (100×6 · 127.5×5 · 85×9), not one rollup weight.
        let checked = sets.filter(\.isChecked).sorted { lhs, rhs in
            if lhs.isWarmup != rhs.isWarmup { return lhs.isWarmup && !rhs.isWarmup }
            return lhs.index < rhs.index
        }
        if !checked.isEmpty {
            return Self.setBreakdownLine(
                checked,
                scale: LogbookDistanceScale.forExercise(named: name),
                addedLoad: LogbookMovementClass.isBodyweight(named: name),
                bodyweight: LogbookMovementClass.isBodyweight(named: name)
            )
        }
        if let note = planned.note, !note.isEmpty, actualWeightKg == nil, planned.weightKg == nil {
            // Preserve note-style lines when weight wasn't tracked (e.g. split squat 2×20).
            if confirmation == .asPlanned || (actualSets == planned.sets && actualReps == planned.reps) {
                if actualReps == 1 {
                    return "\(actualSets) × \(note)"
                }
                return "\(actualSets) × \(actualReps) · \(note)"
            }
        }
        if let kilograms = actualWeightKg {
            let kgText = kilograms == floor(kilograms) ? "\(Int(kilograms))" : String(format: "%.1f", kilograms)
            return "\(actualSets) × \(actualReps) · \(kgText) KG"
        }
        return "\(actualSets) × \(actualReps)"
    }

    /// Per-set WHAT YOU DID line from logbook checks.
    ///
    /// AMA-2462: takes the scale rather than defaulting to `.road` — a verified
    /// Ski Erg actual must read 500 M, not 0.31 MI, for an athlete set to miles.
    static func setBreakdownLine(
        _ sets: [SetActual],
        scale: LogbookDistanceScale = .road,
        addedLoad: Bool = false,
        bodyweight: Bool = false
    ) -> String {
        if sets.count == 1 {
            let only = sets[0]
            if only.durationSeconds != nil || only.calories != nil || only.distanceMeters != nil {
                return LogbookGhost(
                    durationSeconds: only.durationSeconds,
                    calories: only.calories,
                    distanceMeters: only.distanceMeters,
                    source: .lastActual
                ).metricDisplayLine(scale: scale)
            }
        }
        let parts = sets.map { set -> String in
            let prefix = set.isWarmup ? "W " : ""
            let hasMetric = set.durationSeconds != nil
                || set.calories != nil
                || set.distanceMeters != nil
            if hasMetric, set.weightKg == nil, set.reps == nil {
                return prefix + LogbookGhost(
                    durationSeconds: set.durationSeconds,
                    calories: set.calories,
                    distanceMeters: set.distanceMeters,
                    source: .lastActual
                ).metricDisplayLine(scale: scale)
            }
            let weightText: String
            if let kilograms = set.weightKg {
                let magnitude = kilograms == floor(kilograms)
                    ? "\(Int(kilograms))"
                    : String(format: "%.1f", kilograms)
                // AMA-2462: verified history must not restate added load as
                // absolute — a belted chin-up is +25 here as well.
                weightText = (addedLoad ? "+" : "") + magnitude
            } else {
                weightText = "—"
            }
            let repsText = set.reps.map(String.init) ?? "—"
            // AMA-2472: a bodyweight movement has no load slot to leave empty.
            // "Explosive Push-Up — −×12" was reporting a dash where a weight
            // would go on a movement that can never have one; it reads "12".
            if set.weightKg == nil, bodyweight {
                return prefix + repsText
            }
            return "\(prefix)\(weightText)×\(repsText)"
        }
        let joined = parts.joined(separator: " · ")
        let hasWeight = sets.contains { $0.weightKg != nil }
        return hasWeight ? "\(joined) KG" : joined
    }

    var planDelta: ExerciseActualPlanDelta {
        // Sets/reps changes must win over a near-zero weight delta.
        if actualSets != planned.sets || actualReps != planned.reps {
            return ExerciseActualPlanDelta(label: ActualsCopy.verifiedAdjustedDelta, isAsPlanned: false)
        }
        if let plannedKg = planned.weightKg, let actualKg = actualWeightKg {
            let delta = actualKg - plannedKg
            if abs(delta) < 0.05 {
                return ExerciseActualPlanDelta(label: ActualsCopy.verifiedAsPlannedDelta, isAsPlanned: true)
            }
            let magnitude = abs(delta)
            let magText = magnitude == floor(magnitude)
                ? "\(Int(magnitude))"
                : String(format: "%.1f", magnitude)
            let sign = delta > 0 ? "+" : "−"
            return ExerciseActualPlanDelta(
                label: "\(sign)\(magText) KG VS PLAN",
                isAsPlanned: false
            )
        }
        if actualWeightKg == planned.weightKg {
            return ExerciseActualPlanDelta(label: ActualsCopy.verifiedAsPlannedDelta, isAsPlanned: true)
        }
        return ExerciseActualPlanDelta(label: ActualsCopy.verifiedAsPlannedDelta, isAsPlanned: true)
    }
}

struct ActualsVerifiedDeltaSection: Identifiable, Equatable {
    let id: String
    let header: String?
    let rows: [ActualsVerifiedDeltaRow]

    static func sections(from rows: [ActualsVerifiedDeltaRow]) -> [ActualsVerifiedDeltaSection] {
        var result: [ActualsVerifiedDeltaSection] = []
        var buffer: [ActualsVerifiedDeltaRow] = []
        var currentHeader: String?
        var currentBlock: Int?

        func flush() {
            guard !buffer.isEmpty else { return }
            let id = [
                currentBlock.map(String.init) ?? "flat",
                String(result.count),
                buffer[0].id
            ].joined(separator: "_")
            result.append(
                ActualsVerifiedDeltaSection(id: id, header: currentHeader, rows: buffer)
            )
            buffer = []
        }

        for row in rows {
            if buffer.isEmpty {
                currentHeader = row.structureHeader
                currentBlock = row.structureBlockIndex
                buffer.append(row)
                continue
            }
            let sameBlock = row.structureBlockIndex != nil
                && row.structureBlockIndex == currentBlock
            let sameHeader = row.structureHeader == currentHeader
            if sameBlock || (row.structureBlockIndex == nil && currentBlock == nil && sameHeader) {
                buffer.append(row)
            } else {
                flush()
                currentHeader = row.structureHeader
                currentBlock = row.structureBlockIndex
                buffer.append(row)
            }
        }
        flush()
        return result
    }
}

struct ActualsStructureBandHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundColor(DailyDriver.amber)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(DailyDriver.amber.opacity(0.18)))
            .accessibilityIdentifier("af_actuals_structure_header")
    }
}

struct ActualsVerifiedCard: View {
    let sourceName: String
    let rpe: Int?
    let rows: [ActualsVerifiedDeltaRow]
    /// Optional payoff line under the list (JSX mentions next-editor ghosts).
    var footerNote: String? = ActualsCopy.verifiedGhostFooter

    private var sections: [ActualsVerifiedDeltaSection] {
        ActualsVerifiedDeltas.sections(from: rows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            callout

            Text(ActualsCopy.verifiedVsPlanHeader)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .padding(.top, 14)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(sections) { section in
                    verifiedSection(section)
                }
            }
            .accessibilityIdentifier(ActualsCopy.verifiedCardAccessibilityID)

            if let footerNote {
                Text(footerNote)
                    .font(.system(size: 10))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .lineSpacing(2)
            }
        }
    }

    @ViewBuilder
    private func verifiedSection(_ section: ActualsVerifiedDeltaSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header = section.header, !header.isEmpty {
                ActualsStructureBandHeader(title: header)
            }
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(DailyDriver.border).frame(height: 1)
                    }
                    deltaRow(row)
                }
            }
            .padding(.horizontal, 14)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if section.header != nil {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DailyDriver.amber)
                        .frame(width: 3)
                        .padding(.vertical, 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var callout: some View {
        ActualsSessionStatusCallout(
            headline: ActualsCopy.verifiedHeadline,
            bodyText: ActualsVerifiedDeltas.calloutBody(sourceName: sourceName, rpe: rpe)
        )
    }

    private func deltaRow(_ row: ActualsVerifiedDeltaRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .ddDisplayText(13.5, weight: .semibold)
                    .foregroundColor(DailyDriver.foreground)
                Text(row.actualLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.deltaLabel)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(row.isAsPlanned ? DailyDriver.foregroundDim : DailyDriver.lime)
        }
        .padding(.vertical, 11)
        .accessibilityIdentifier("af_actuals_verified_row_\(row.id)")
    }
}

#if DEBUG
#Preview("Verified card") {
    var session = ActualsFillInSession.lowerBodyPosteriorSample()
    session.exercises[0].confirmation = .adjusted
    session.exercises[0].actualWeightKg = 90
    for index in 1..<session.exercises.count {
        session.exercises[index].confirmation = .asPlanned
    }
    session.rpe = 8
    return ScrollView {
        ActualsVerifiedCard(
            sourceName: "Strava",
            rpe: 8,
            rows: ActualsVerifiedDeltas.rows(from: session.exercises)
        )
        .padding(18)
    }
    .background(DailyDriver.screenBackground.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
#endif
