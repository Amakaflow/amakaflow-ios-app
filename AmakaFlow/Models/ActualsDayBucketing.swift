//
//  ActualsDayBucketing.swift
//  AmakaFlow
//
//  AMA-2396 A2: bucket sessions by start_date_local (NOT UTC), newest-first.
//  Named regression: 18:34 must sort above 12:19 on the same local day.
//

import Foundation

enum ActualsDayBucketing {
    /// Parse Strava `start_date_local` (no zone / local wall clock) or UTC `start_date`.
    /// Prefer `startDateLocal` when present so UTC-crossing activities land on the
    /// athlete's local day.
    static func resolveStartDate(
        startDateLocal: String?,
        startDateUTC: String,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Date? {
        if let startDateLocal,
           let local = parseLocalWallClock(startDateLocal, calendar: calendar, now: now) {
            return local
        }
        return parseISO8601(startDateUTC)
    }

    /// Group by local calendar day; within each day sort newest-first.
    static func bucketByLocalDay<T>(
        _ items: [T],
        startDate: (T) -> Date,
        calendar: Calendar = .current
    ) -> [(day: Date, items: [T])] {
        var groups: [Date: [T]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: startDate(item))
            groups[day, default: []].append(item)
        }
        return groups.keys.sorted(by: >).map { day in
            let sorted = (groups[day] ?? []).sorted { startDate($0) > startDate($1) }
            return (day, sorted)
        }
    }

    /// Filter to a local calendar day, newest-first.
    static func items(
        on day: Date,
        from items: [Date],
        calendar: Calendar = .current
    ) -> [Date] {
        items
            .filter { calendar.isDate($0, inSameDayAs: day) }
            .sorted(by: >)
    }

    // MARK: - Parsing

    static func parseISO8601(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// Strava `start_date_local` is typically `yyyy-MM-dd'T'HH:mm:ss` with no zone.
    static func parseLocalWallClock(
        _ raw: String,
        calendar: Calendar,
        now: Date
    ) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // If it carries a zone, treat as absolute.
        if trimmed.contains("Z") || trimmed.contains("+") || trimmed.suffix(6).contains("-") {
            // Heuristic: ISO offsets look like …±HH:MM at the end.
            if let absolute = parseISO8601(trimmed) { return absolute }
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        // Fallback: strip zone and reparse as local.
        let stripped = trimmed
            .replacingOccurrences(of: "Z", with: "")
            .replacingOccurrences(
                of: #"([+-]\d{2}:\d{2})$"#,
                with: "",
                options: .regularExpression
            )
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: stripped)
    }

    /// Mono day header for History: `SAT · AUG 9`
    static func historyDayHeader(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let locale = calendar.locale ?? .current
        let weekday = date.formatted(
            Date.FormatStyle()
                .weekday(.abbreviated)
                .locale(locale)
                .timeZone(calendar.timeZone)
                .calendar(calendar)
        ).uppercased()
        let month = date.formatted(
            Date.FormatStyle()
                .month(.abbreviated)
                .locale(locale)
                .timeZone(calendar.timeZone)
                .calendar(calendar)
        ).uppercased()
        let day = calendar.component(.day, from: date)
        return "\(weekday) · \(month) \(day)"
    }
}

// MARK: - History scrubber (past 30 days)

enum ActualsHistoryScrubber {
    static let lookbackDays = 30
    /// Visible strip width (design shows ~7 cells including optional future).
    static let visibleCount = 7

    /// Build a backward-looking scrubber window ending at `anchor` (usually today),
    /// spanning up to `lookbackDays`. Future days are included only as dim planned-only
    /// cells when `includeFuturePlanned` is true — never as the default window start.
    static func days(
        activityDates: [Date],
        calendar: Calendar = .current,
        now: Date = Date(),
        selectedDay: Date? = nil,
        includeFuturePlannedSlot: Bool = true
    ) -> [DDScrubberDay] {
        let today = calendar.startOfDay(for: now)
        // selectedDay retained for API compatibility — full 30-day strip is always returned;
        // the view scrolls to the selection.
        _ = selectedDay

        // Full navigable strip: [today - 29, today] (+ optional dimmed tomorrow).
        guard let earliest = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today) else {
            return []
        }

        var end = today
        if includeFuturePlannedSlot,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            end = tomorrow
        }

        let locale = calendar.locale ?? .current
        var result: [DDScrubberDay] = []
        var cursor = earliest
        while cursor <= end {
            let dayNumber = calendar.component(.day, from: cursor)
            let weekday = cursor.formatted(
                Date.FormatStyle()
                    .weekday(.narrow)
                    .locale(locale)
                    .timeZone(calendar.timeZone)
                    .calendar(calendar)
            ).uppercased()
            let isToday = calendar.isDate(cursor, inSameDayAs: today)
            let isFuture = cursor > today
            let hasActivity = activityDates.contains { calendar.isDate($0, inSameDayAs: cursor) }
            result.append(
                DDScrubberDay(
                    id: cursor,
                    weekdayLabel: weekday,
                    dayNumber: dayNumber,
                    isToday: isToday,
                    isFuture: isFuture,
                    hasActivity: hasActivity
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Full navigable range (for tests): past 30 days through today.
    static func navigableRange(
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today) else {
            return nil
        }
        return (start, today)
    }
}
