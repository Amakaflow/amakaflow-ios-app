//
//  ProfileTrainingStatsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2417: Monday-week Profile aggregates from Strava sync-completed.
//

import XCTest
@testable import AmakaFlowCompanion

final class ProfileTrainingStatsTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        cal.firstWeekday = 2
        return cal
    }

    /// Wednesday 2026-08-12 — week Mon 8/10 … Sun 8/16.
    private var now: Date {
        date(year: 2026, month: 8, day: 12, hour: 18)
    }

    func testMondayFirstCalendarUsesMonday() {
        XCTAssertEqual(ProfileTrainingStats.mondayFirstCalendar.firstWeekday, 2)
    }

    func testWeekFilterExcludesPriorSundayAndIncludesMonday() {
        let priorSunday = activity(
            id: 1,
            name: "Sunday ride",
            startLocal: "2026-08-09T09:00:00",
            durationMin: 40
        )
        let monday = activity(
            id: 2,
            name: "Monday lift",
            startLocal: "2026-08-10T07:00:00",
            durationMin: 55
        )
        let completions = ProfileTrainingStats.completions(
            from: [priorSunday, monday],
            calendar: calendar,
            now: now
        )
        let week = ProfileTrainingStats.weekCompletions(
            from: completions,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(week.map(\.workoutName), ["Monday lift"])
        XCTAssertEqual(WeeklySummary(completions: week).workoutCount, 1)
        XCTAssertEqual(WeeklySummary(completions: week).totalDurationSeconds, 55 * 60)
    }

    func testMonthCountUsesCalendarMonth() {
        let july = activity(
            id: 10,
            name: "July run",
            startLocal: "2026-07-31T18:00:00",
            durationMin: 30
        )
        let august = activity(
            id: 11,
            name: "August run",
            startLocal: "2026-08-01T07:00:00",
            durationMin: 30
        )
        let completions = ProfileTrainingStats.completions(
            from: [july, august],
            calendar: calendar,
            now: now
        )
        let month = ProfileTrainingStats.monthCompletions(
            from: completions,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(month.map(\.workoutName), ["August run"])
    }

    func testDayStreakCurrentAndBest() {
        // Active: Mon 10, Tue 11, Wed 12 (current=3); also Fri 7–Sat 8 (best still 3)
        let activities = [
            activity(id: 1, name: "A", startLocal: "2026-08-07T08:00:00", durationMin: 20),
            activity(id: 2, name: "B", startLocal: "2026-08-08T08:00:00", durationMin: 20),
            activity(id: 3, name: "C", startLocal: "2026-08-10T08:00:00", durationMin: 20),
            activity(id: 4, name: "D", startLocal: "2026-08-11T08:00:00", durationMin: 20),
            activity(id: 5, name: "E", startLocal: "2026-08-12T08:00:00", durationMin: 20)
        ]
        let completions = ProfileTrainingStats.completions(
            from: activities,
            calendar: calendar,
            now: now
        )
        let streak = ProfileTrainingStats.dayStreak(
            from: completions,
            today: now,
            calendar: calendar
        )
        XCTAssertEqual(streak.current, 3)
        XCTAssertEqual(streak.best, 3)
    }

    func testCompletionsMapDurationAndDistance() {
        let activity = activity(
            id: 99,
            name: "Tempo",
            startLocal: "2026-08-11T12:00:00",
            durationMin: 42,
            distanceKm: 8.5
        )
        let completions = ProfileTrainingStats.completions(
            from: [activity],
            calendar: calendar,
            now: now
        )
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions[0].id, "strava_99")
        XCTAssertEqual(completions[0].durationSeconds, 42 * 60)
        XCTAssertEqual(completions[0].distanceMeters, 8500)
        XCTAssertTrue(completions[0].isSyncedToStrava)
    }

    // MARK: - Helpers

    private func activity(
        id: Int,
        name: String,
        startLocal: String,
        durationMin: Int,
        distanceKm: Double = 0
    ) -> StravaCompletedActivityDTO {
        StravaCompletedActivityDTO(
            stravaId: id,
            name: name,
            type: "Workout",
            distanceKm: distanceKm,
            durationMin: durationMin,
            startDate: "\(startLocal)Z",
            startDateLocal: startLocal,
            description: ""
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }
}
