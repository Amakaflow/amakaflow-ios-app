//
//  MonthGridLayout.swift
//  AmakaFlow
//
//  Pure layout helpers for the Workouts Month grid (AMA-1641).
//  Extracted from WorkoutsView so the calendar math is unit-testable
//  without instantiating SwiftUI views.
//

import Foundation

enum MonthGridLayout {
    /// Number of leading empty cells needed in the day grid so day-1 of the
    /// month lands under the correct weekday column.
    ///
    /// `monthStart` may be any date in the target month; this function
    /// re-anchors to the first of the month internally.
    static func leadingEmptyCells(for monthStart: Date, calendar: Calendar) -> Int {
        let weekdayOfFirst = calendar.component(.weekday, from: calendar.startOfMonth(for: monthStart))
        // weekday is 1...7 with 1 = Sunday by default. firstWeekday is 1...7.
        // Number of leading empty cells is (weekdayOfFirst - firstWeekday) mod 7.
        let raw = weekdayOfFirst - calendar.firstWeekday
        return (raw + 7) % 7
    }

    /// Locale-aware short weekday symbols rotated to start on the calendar's
    /// `firstWeekday` (Sunday for US default locale).
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        guard offset >= 0, offset < symbols.count else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// First instant of the month that is `offset` months from `from`.
    static func monthAnchor(
        from date: Date = Date(),
        offset: Int,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .month, value: offset, to: calendar.startOfMonth(for: date)) ?? date
    }

    /// Sequential dates for every day in the month containing `anchor`.
    static func dates(inMonthContaining anchor: Date, calendar: Calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        return (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }
}

extension Calendar {
    /// Returns the first instant of the month containing `date`, in the
    /// receiver's time zone.
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
