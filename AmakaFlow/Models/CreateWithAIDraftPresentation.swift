//
//  CreateWithAIDraftPresentation.swift
//  AmakaFlow
//
//  Pure presentation transforms for the Create with AI draft.
//

import Foundation

enum DraftBand: Equatable {
    case warmUp
    case main
    case cooldown
}

struct DraftRow: Equatable {
    let interval: WorkoutInterval
    let band: DraftBand
    let restChipSeconds: Int?
    let isSummary: Bool

    var isNumberedRest: Bool {
        guard !isSummary else { return false }
        if case .rest = interval { return true }
        return false
    }
}

enum CreateWithAIDraftPresentation {
    static func whyThisBullets(
        whyThis: [String]?,
        description: String?
    ) -> [String] {
        let serverBullets = normalizedBullets(whyThis ?? [])
        if !serverBullets.isEmpty {
            return Array(serverBullets.prefix(3))
        }

        guard let description else { return [] }
        let descriptionBullets = description
            .components(separatedBy: CharacterSet(charactersIn: "\n.!?•"))
        return Array(normalizedBullets(descriptionBullets).prefix(3))
    }

    static func collapseRests(intervals: [WorkoutInterval]) -> [DraftRow] {
        var rows: [DraftRow] = []

        for interval in intervals {
            if case .rest(let seconds) = interval {
                guard let seconds, !rows.isEmpty, rows[rows.count - 1].restChipSeconds == nil else {
                    continue
                }
                let previous = rows[rows.count - 1]
                rows[rows.count - 1] = DraftRow(
                    interval: previous.interval,
                    band: previous.band,
                    restChipSeconds: seconds,
                    isSummary: previous.isSummary
                )
                continue
            }

            rows.append(
                DraftRow(
                    interval: interval,
                    band: .main,
                    restChipSeconds: embeddedRestSeconds(in: interval),
                    isSummary: false
                )
            )
        }

        return rows
    }

    static func bandRows(
        warmUp: WorkoutInterval?,
        blocks: [WorkoutInterval],
        cooldown: WorkoutInterval?
    ) -> [DraftRow] {
        var rows: [DraftRow] = []

        if let warmUp {
            rows.append(summaryRow(interval: warmUp, band: .warmUp))
        }
        rows.append(contentsOf: collapseRests(intervals: blocks))
        if let cooldown {
            rows.append(summaryRow(interval: cooldown, band: .cooldown))
        }

        return rows
    }

    private static func normalizedBullets(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func embeddedRestSeconds(in interval: WorkoutInterval) -> Int? {
        guard case .reps(_, _, _, _, let restSeconds, _) = interval else { return nil }
        return restSeconds
    }

    private static func summaryRow(interval: WorkoutInterval, band: DraftBand) -> DraftRow {
        DraftRow(
            interval: interval,
            band: band,
            restChipSeconds: nil,
            isSummary: true
        )
    }
}
