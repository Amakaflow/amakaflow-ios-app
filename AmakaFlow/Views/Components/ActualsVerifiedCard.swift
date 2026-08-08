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
                isAsPlanned: delta.isAsPlanned
            )
        }
    }

    static func calloutBody(sourceName: String, rpe: Int) -> String {
        "\(sourceName) metrics + your actuals + RPE \(rpe) — counted once in Progress."
    }
}

struct ExerciseActualPlanDelta: Equatable {
    let label: String
    let isAsPlanned: Bool
}

extension ExerciseActual {
    var actualDisplayLine: String {
        if let note = planned.note, !note.isEmpty, actualWeightKg == nil, planned.weightKg == nil {
            // Preserve note-style lines when weight wasn't tracked (e.g. split squat 2×20).
            if confirmation == .asPlanned || (actualSets == planned.sets && actualReps == planned.reps) {
                return "\(actualSets) × \(actualReps) · \(note)"
            }
        }
        if let kilograms = actualWeightKg {
            let kgText = kilograms == floor(kilograms) ? "\(Int(kilograms))" : String(format: "%.1f", kilograms)
            return "\(actualSets) × \(actualReps) · \(kgText) KG"
        }
        return "\(actualSets) × \(actualReps)"
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

struct ActualsVerifiedCard: View {
    let sourceName: String
    let rpe: Int
    let rows: [ActualsVerifiedDeltaRow]
    /// Optional payoff line under the list (JSX mentions next-editor ghosts).
    var footerNote: String? = ActualsCopy.verifiedGhostFooter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            callout

            Text(ActualsCopy.verifiedVsPlanHeader)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .padding(.top, 14)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var callout: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DailyDriver.lime)
                Text(ActualsCopy.verifiedHeadline)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.lime)
            }
            Text(ActualsVerifiedDeltas.calloutBody(sourceName: sourceName, rpe: rpe))
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.lime.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.lime.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier(ActualsCopy.verifiedCalloutAccessibilityID)
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
