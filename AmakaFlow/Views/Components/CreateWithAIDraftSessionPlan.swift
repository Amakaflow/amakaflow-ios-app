//
//  CreateWithAIDraftSessionPlan.swift
//  AmakaFlow
//
//  AMA-2373 — grouped warm-up / main / cooldown blocks matching the approved
//  draft mock (bordered bands, rest chips on rows, no numbered Rest steps).
//

import SwiftUI

struct CreateWithAIDraftSessionPlan: View {
    let mainTitle: String
    let warmUp: WorkoutInterval?
    let blocks: [WorkoutInterval]
    let cooldown: WorkoutInterval?

    private var mainRows: [DraftRow] {
        CreateWithAIDraftPresentation.collapseRests(intervals: blocks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let warmUp {
                bandCard(
                    title: "Warm-up",
                    trailing: summaryMinutesLabel(warmUp),
                    titleColor: DailyDriver.foreground,
                    borderColor: DailyDriver.borderStrong
                ) {
                    CreateWithAIDraftRow(
                        row: DraftRow(
                            interval: warmUp,
                            band: .warmUp,
                            restChipSeconds: nil,
                            isSummary: true
                        )
                    )
                }
            }

            if !mainRows.isEmpty {
                bandCard(
                    title: mainTitle,
                    trailing: CreateWithAIDraftPresentation.exerciseCountLabel(
                        warmUp: nil,
                        blocks: blocks,
                        cooldown: nil
                    ),
                    titleColor: DailyDriver.lime,
                    borderColor: DailyDriver.lime.opacity(0.55)
                ) {
                    ForEach(Array(mainRows.enumerated()), id: \.offset) { _, row in
                        CreateWithAIDraftRow(row: row)
                    }
                }
            }

            if let cooldown {
                bandCard(
                    title: "Cool-down",
                    trailing: summaryMinutesLabel(cooldown),
                    titleColor: DailyDriver.foreground,
                    borderColor: DailyDriver.borderStrong
                ) {
                    CreateWithAIDraftRow(
                        row: DraftRow(
                            interval: cooldown,
                            band: .cooldown,
                            restChipSeconds: nil,
                            isSummary: true
                        )
                    )
                }
            }
        }
        .accessibilityIdentifier("create_with_ai_session_plan")
    }

    private func bandCard<Content: View>(
        title: String,
        trailing: String?,
        titleColor: Color,
        borderColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(titleColor)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
            }

            content()
        }
        .padding(14)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryMinutesLabel(_ interval: WorkoutInterval) -> String? {
        switch interval {
        case .warmup(let seconds, _), .cooldown(let seconds, _):
            // Warm-up/cool-down steps are timed, so this is exact, not "~".
            return WorkoutDurationEstimate.label(seconds: seconds, isEstimate: false)
        default:
            return nil
        }
    }
}

struct CreateWithAIDraftRow: View {
    let row: DraftRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DailyDriver.foreground)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: detailIsSwap ? .bold : .regular, design: .monospaced))
                        .foregroundColor(detailIsSwap ? DailyDriver.amber : DailyDriver.foregroundMuted)
                }
            }

            Spacer(minLength: 8)

            if let restSeconds = row.restChipSeconds {
                Text("REST \(restSeconds)S")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DailyDriver.card2)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch row.band {
        case .warmUp: return summaryTitle(fallback: "Warm-up")
        case .cooldown: return summaryTitle(fallback: "Cool-down")
        case .main: return mainIntervalName(row.interval)
        }
    }

    private var detail: String? {
        if row.isSummary {
            return summaryDetail(row.interval)
        }
        switch row.interval {
        case .reps(let sets, let reps, _, let load, _, _):
            var parts: [String] = []
            if let sets {
                parts.append("\(sets) x \(reps)")
            } else {
                parts.append("\(reps) reps")
            }
            if let load {
                let upper = load.uppercased()
                if upper.contains("SWAP") {
                    parts.append("· \(upper)")
                } else {
                    parts.append("· \(load)")
                }
            }
            return parts.joined(separator: " ")
        case .time(let seconds, let target):
            if let target, !target.isEmpty { return target }
            return "\(max(1, seconds / 60)) min"
        case .distance(_, let target):
            return target
        case .repeat(_, let intervals):
            return "\(intervals.count) exercises"
        default:
            return nil
        }
    }

    private var detailIsSwap: Bool {
        guard let detail else { return false }
        return detail.uppercased().contains("SWAP")
    }

    private func summaryTitle(fallback: String) -> String {
        switch row.interval {
        case .warmup(_, let target), .cooldown(_, let target):
            guard let target, !target.isEmpty else { return fallback }
            let first = target
                .split(separator: ",", maxSplits: 1)
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if let first, !first.isEmpty { return first }
            return fallback
        default:
            return fallback
        }
    }

    private func mainIntervalName(_ interval: WorkoutInterval) -> String {
        switch interval {
        case .warmup: return "Warm-up"
        case .cooldown: return "Cool-down"
        case .time(_, let target): return target ?? "Timed work"
        case .reps(_, _, let name, _, _, _): return name
        case .distance(let meters, _): return "\(meters)m"
        case .repeat(let reps, _): return "Repeat x\(reps)"
        case .rest: return "Rest"
        }
    }

    private func summaryDetail(_ interval: WorkoutInterval) -> String? {
        switch interval {
        case .warmup(let seconds, let target), .cooldown(let seconds, let target):
            let minutes = max(1, seconds / 60)
            if let target, !target.isEmpty {
                // If title already used the first clause, show remaining + time.
                let parts = target.split(separator: ",", maxSplits: 1)
                if parts.count > 1 {
                    let rest = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    return "\(minutes) min · \(rest)"
                }
                return "\(minutes) min"
            }
            return "\(minutes) min"
        default:
            return nil
        }
    }
}
