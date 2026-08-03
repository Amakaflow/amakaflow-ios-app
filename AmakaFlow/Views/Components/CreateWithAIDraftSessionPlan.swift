//
//  CreateWithAIDraftSessionPlan.swift
//  AmakaFlow
//
//  AMA-2373 — session-plan rows extracted from CreateWithAIDraftView for
//  SwiftLint type_body_length.
//

import SwiftUI

struct CreateWithAINumberedDraftRow: Equatable {
    let offset: Int
    let row: DraftRow
    let number: Int?
}

struct CreateWithAIDraftSessionPlan: View {
    let warmUp: WorkoutInterval?
    let blocks: [WorkoutInterval]
    let cooldown: WorkoutInterval?

    var body: some View {
        let rows = CreateWithAIDraftPresentation.bandRows(
            warmUp: warmUp,
            blocks: blocks,
            cooldown: cooldown
        )
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SESSION PLAN")
            ForEach(Self.numberedDraftRows(rows), id: \.offset) { item in
                CreateWithAIDraftRow(row: item.row, number: item.number)
            }
        }
        .accessibilityIdentifier("create_with_ai_session_plan")
    }

    private static func numberedDraftRows(_ rows: [DraftRow]) -> [CreateWithAINumberedDraftRow] {
        var mainIndex = 0
        return rows.enumerated().map { offset, row in
            guard row.band == .main, !row.isSummary else {
                return CreateWithAINumberedDraftRow(offset: offset, row: row, number: nil)
            }
            mainIndex += 1
            return CreateWithAINumberedDraftRow(offset: offset, row: row, number: mainIndex)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.25)
            .foregroundColor(DailyDriver.foregroundDim)
    }
}

struct CreateWithAIDraftRow: View {
    let row: DraftRow
    let number: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            badge

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.foreground)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
            }

            Spacer(minLength: 8)

            if let restSeconds = row.restChipSeconds {
                Text("\(restSeconds)s rest")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DailyDriver.card2)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var badge: some View {
        if row.isSummary {
            Image(systemName: row.band == .warmUp ? "flame.fill" : "wind")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DailyDriver.ink)
                .frame(width: 26, height: 26)
                .background(DailyDriver.amber)
                .clipShape(Circle())
        } else {
            Text("\(number ?? 0)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(DailyDriver.ink)
                .frame(width: 26, height: 26)
                .background(DailyDriver.lime)
                .clipShape(Circle())
        }
    }

    private var title: String {
        switch row.band {
        case .warmUp: return "Warm-up"
        case .cooldown: return "Cool-down"
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
            if let sets { parts.append("\(sets)x") }
            parts.append("\(reps) reps")
            if let load { parts.append("@ \(load)") }
            return parts.joined(separator: " ")
        case .time(let seconds, _):
            return "\(max(1, seconds / 60)) min"
        case .distance(_, let target):
            return target
        case .repeat(_, let intervals):
            return "\(intervals.count) exercises"
        default:
            return nil
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
                return "\(minutes) min · \(target)"
            }
            return "\(minutes) min"
        default:
            return nil
        }
    }
}
