//
//  TodayDiary.swift
//  AmakaFlow
//
//  AMA-2289: Completed-only Today diary helpers.
//  Proto IA: finished sessions only — no plan/schedule chrome; no structure edit.
//

import Foundation

/// Pure helpers for the Daily Driver Today completed diary.
enum TodayDiary {
    /// Finished sessions for `now`'s calendar day, newest-first.
    static func completionsForToday(
        _ completions: [WorkoutCompletion],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkoutCompletion] {
        completions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Completed records are immutable in structure — never open the workout editor.
    static let allowsStructureEdit = false

    /// Post-complete actions available on a completed diary item (thin OK).
    enum CompletedItemAction: String, CaseIterable, Identifiable {
        case verify
        case map
        case enrich

        var id: String { rawValue }

        var title: String {
            switch self {
            case .verify: return "Verify"
            case .map: return "Map"
            case .enrich: return "Enrich"
            }
        }

        var systemImage: String {
            switch self {
            case .verify: return "checkmark.seal"
            case .map: return "map"
            case .enrich: return "text.badge.plus"
            }
        }

        var accessibilityIdentifier: String {
            "af_completion_action_\(rawValue)"
        }

        var subtitle: String {
            switch self {
            case .verify:
                return "Confirm this synced session matches what you did"
            case .map:
                return "Link route or exercise names from the device pull"
            case .enrich:
                return "Add notes or effort — without editing structure"
            }
        }
    }

    static var diaryActions: [CompletedItemAction] {
        CompletedItemAction.allCases
    }
}
