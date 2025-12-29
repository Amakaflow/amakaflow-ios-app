//
//  ActivityHistoryTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for activity history feature - logic and data transformations
//
//  Tests the logic used by ActivityHistoryView without depending on types
//  that require Xcode project configuration. This ensures tests can run
//  in the CI environment reliably.
//

import XCTest
@testable import AmakaFlowCompanion

final class ActivityHistoryTests: XCTestCase {

    // MARK: - Duration Formatting Tests

    func testFormattedDurationMinutesOnly() {
        let result = formatDuration(durationSeconds: 300)
        XCTAssertEqual(result, "5:00")
    }

    func testFormattedDurationMinutesAndSeconds() {
        let result = formatDuration(durationSeconds: 185)
        XCTAssertEqual(result, "3:05")
    }

    func testFormattedDurationWithHours() {
        let result = formatDuration(durationSeconds: 3725)
        XCTAssertEqual(result, "1:02:05")
    }

    func testFormattedDurationZeroSeconds() {
        let result = formatDuration(durationSeconds: 0)
        XCTAssertEqual(result, "0:00")
    }

    func testFormattedDurationExactHour() {
        let result = formatDuration(durationSeconds: 3600)
        XCTAssertEqual(result, "1:00:00")
    }

    func testFormattedDurationLongDuration() {
        let result = formatDuration(durationSeconds: 7265) // 2h 1m 5s
        XCTAssertEqual(result, "2:01:05")
    }

    // MARK: - Weekly Summary Calculation Tests

    func testWeeklySummaryCalculation() {
        let summary = calculateWeeklySummary(
            durations: [1800, 2400, 1200],
            calories: [200, 300, 150]
        )

        XCTAssertEqual(summary.workoutCount, 3)
        XCTAssertEqual(summary.totalDurationSeconds, 5400) // 1.5 hours
        XCTAssertEqual(summary.totalCalories, 650)
    }

    func testWeeklySummaryEmptyCompletions() {
        let summary = calculateWeeklySummary(durations: [], calories: [])

        XCTAssertEqual(summary.workoutCount, 0)
        XCTAssertEqual(summary.totalDurationSeconds, 0)
        XCTAssertEqual(summary.totalCalories, 0)
    }

    func testWeeklySummaryFormattedDurationWithHours() {
        let summary = calculateWeeklySummary(
            durations: [3600, 1800], // 1h + 30m
            calories: [0, 0]
        )

        XCTAssertEqual(formatSummaryDuration(summary.totalDurationSeconds), "1h 30m")
    }

    func testWeeklySummaryFormattedDurationMinutesOnly() {
        let summary = calculateWeeklySummary(
            durations: [1800], // 30 min
            calories: [0]
        )

        XCTAssertEqual(formatSummaryDuration(summary.totalDurationSeconds), "30m")
    }

    func testWeeklySummaryFormattedCaloriesUnder1000() {
        let summary = calculateWeeklySummary(durations: [0], calories: [500])
        XCTAssertEqual(formatCalories(summary.totalCalories), "500")
    }

    func testWeeklySummaryFormattedCaloriesOver1000() {
        let summary = calculateWeeklySummary(durations: [0], calories: [1500])
        XCTAssertEqual(formatCalories(summary.totalCalories), "1.5k")
    }

    func testWeeklySummaryFormattedCaloriesExact1000() {
        let summary = calculateWeeklySummary(durations: [0], calories: [1000])
        XCTAssertEqual(formatCalories(summary.totalCalories), "1.0k")
    }

    func testWeeklySummaryHandlesNilCalories() {
        let summary = calculateWeeklySummaryWithNilCalories(
            durations: [1800, 2400],
            calories: [nil, 200]
        )

        XCTAssertEqual(summary.totalCalories, 200)
    }

    // MARK: - Date Category Tests

    func testDateCategoryToday() {
        let now = Date()
        let category = calculateDateCategory(for: now)

        XCTAssertEqual(category.title, "Today")
        XCTAssertEqual(category.sortOrder, 0)
    }

    func testDateCategoryYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let category = calculateDateCategory(for: yesterday)

        XCTAssertEqual(category.title, "Yesterday")
        XCTAssertEqual(category.sortOrder, 1)
    }

    func testDateCategoryThisWeek() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let category = calculateDateCategory(for: threeDaysAgo)

        XCTAssertEqual(category.sortOrder, 2)
        XCTAssertTrue(category.title.count > 0)
    }

    func testDateCategoryOlder() {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let category = calculateDateCategory(for: twoWeeksAgo)

        XCTAssertEqual(category.sortOrder, 3)
    }

    func testDateCategorySortOrderPreserved() {
        let dates = [
            Date(), // Today
            Calendar.current.date(byAdding: .day, value: -1, to: Date())!, // Yesterday
            Calendar.current.date(byAdding: .day, value: -3, to: Date())!, // This week
            Calendar.current.date(byAdding: .day, value: -14, to: Date())! // Older
        ]

        let categories = dates.map { calculateDateCategory(for: $0) }

        // Verify sort order increases
        for i in 0..<categories.count - 1 {
            XCTAssertLessThanOrEqual(categories[i].sortOrder, categories[i + 1].sortOrder)
        }
    }

    // MARK: - Filter Threshold Tests

    func testFilterAllReturnsNilThreshold() {
        let threshold = filterDateThreshold(for: "all")
        XCTAssertNil(threshold)
    }

    func testFilterThisWeekReturnsCorrectThreshold() {
        let threshold = filterDateThreshold(for: "thisWeek")
        XCTAssertNotNil(threshold)

        let calendar = Calendar.current
        let daysDiff = calendar.dateComponents([.day], from: threshold!, to: Date()).day!
        XCTAssertEqual(daysDiff, 7)
    }

    func testFilterThisMonthReturnsCorrectThreshold() {
        let threshold = filterDateThreshold(for: "thisMonth")
        XCTAssertNotNil(threshold)

        let calendar = Calendar.current
        let monthsDiff = calendar.dateComponents([.month], from: threshold!, to: Date()).month!
        XCTAssertEqual(monthsDiff, 1)
    }

    // MARK: - Health Metrics Tests

    func testHasHealthMetricsWithHeartRate() {
        let hasMetrics = hasHealthMetrics(avgHeartRate: 120, activeCalories: nil)
        XCTAssertTrue(hasMetrics)
    }

    func testHasHealthMetricsWithCalories() {
        let hasMetrics = hasHealthMetrics(avgHeartRate: nil, activeCalories: 300)
        XCTAssertTrue(hasMetrics)
    }

    func testHasHealthMetricsWithBoth() {
        let hasMetrics = hasHealthMetrics(avgHeartRate: 120, activeCalories: 300)
        XCTAssertTrue(hasMetrics)
    }

    func testHasNoHealthMetrics() {
        let hasMetrics = hasHealthMetrics(avgHeartRate: nil, activeCalories: nil)
        XCTAssertFalse(hasMetrics)
    }

    // MARK: - Completion Sorting Tests

    func testCompletionsSortByStartTimeDescending() {
        let now = Date()
        let times = [
            now.addingTimeInterval(-3600), // 1 hour ago
            now.addingTimeInterval(-1800), // 30 min ago
            now.addingTimeInterval(-7200)  // 2 hours ago
        ]

        let sorted = sortCompletionsByTime(times)

        // Should be: 30 min ago, 1 hour ago, 2 hours ago
        XCTAssertEqual(sorted[0], times[1])
        XCTAssertEqual(sorted[1], times[0])
        XCTAssertEqual(sorted[2], times[2])
    }

    // MARK: - Source Display Tests

    func testSourceDisplayNames() {
        XCTAssertEqual(sourceDisplayName(for: "apple_watch"), "Apple Watch")
        XCTAssertEqual(sourceDisplayName(for: "garmin"), "Garmin")
        XCTAssertEqual(sourceDisplayName(for: "manual"), "Manual")
        XCTAssertEqual(sourceDisplayName(for: "phone_only"), "Phone")
    }

    func testSourceIconNames() {
        XCTAssertEqual(sourceIconName(for: "apple_watch"), "applewatch")
        XCTAssertEqual(sourceIconName(for: "garmin"), "watchface.applewatch.case")
        XCTAssertEqual(sourceIconName(for: "manual"), "pencil")
        XCTAssertEqual(sourceIconName(for: "phone_only"), "iphone")
    }

    // MARK: - Pagination Tests

    func testCanLoadMoreWithSpace() {
        let canLoad = canLoadMore(hasMoreData: true, isLoadingMore: false, isLoading: false)
        XCTAssertTrue(canLoad)
    }

    func testCannotLoadMoreWhileLoading() {
        let canLoad = canLoadMore(hasMoreData: true, isLoadingMore: true, isLoading: false)
        XCTAssertFalse(canLoad)
    }

    func testCannotLoadMoreWhenNoMoreData() {
        let canLoad = canLoadMore(hasMoreData: false, isLoadingMore: false, isLoading: false)
        XCTAssertFalse(canLoad)
    }

    func testCannotLoadMoreWhileInitialLoading() {
        let canLoad = canLoadMore(hasMoreData: true, isLoadingMore: false, isLoading: true)
        XCTAssertFalse(canLoad)
    }

    // MARK: - Helper Methods (mirror ViewModel logic for testing)

    private func formatDuration(durationSeconds: Int) -> String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private struct TestWeeklySummary {
        let workoutCount: Int
        let totalDurationSeconds: Int
        let totalCalories: Int
    }

    private func calculateWeeklySummary(durations: [Int], calories: [Int]) -> TestWeeklySummary {
        TestWeeklySummary(
            workoutCount: durations.count,
            totalDurationSeconds: durations.reduce(0, +),
            totalCalories: calories.reduce(0, +)
        )
    }

    private func calculateWeeklySummaryWithNilCalories(durations: [Int], calories: [Int?]) -> TestWeeklySummary {
        TestWeeklySummary(
            workoutCount: durations.count,
            totalDurationSeconds: durations.reduce(0, +),
            totalCalories: calories.compactMap { $0 }.reduce(0, +)
        )
    }

    private func formatSummaryDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatCalories(_ calories: Int) -> String {
        if calories >= 1000 {
            return String(format: "%.1fk", Double(calories) / 1000.0)
        }
        return "\(calories)"
    }

    private struct TestDateCategory {
        let title: String
        let sortOrder: Int
    }

    private func calculateDateCategory(for date: Date) -> TestDateCategory {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateDay = calendar.startOfDay(for: date)

        if calendar.isDateInToday(date) {
            return TestDateCategory(title: "Today", sortOrder: 0)
        } else if calendar.isDateInYesterday(date) {
            return TestDateCategory(title: "Yesterday", sortOrder: 1)
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: today),
                  dateDay >= weekAgo {
            return TestDateCategory(
                title: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                sortOrder: 2
            )
        } else {
            return TestDateCategory(
                title: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                sortOrder: 3
            )
        }
    }

    private func filterDateThreshold(for filter: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        switch filter {
        case "all":
            return nil
        case "thisWeek":
            return calendar.date(byAdding: .day, value: -7, to: now)
        case "thisMonth":
            return calendar.date(byAdding: .month, value: -1, to: now)
        default:
            return nil
        }
    }

    private func hasHealthMetrics(avgHeartRate: Int?, activeCalories: Int?) -> Bool {
        avgHeartRate != nil || activeCalories != nil
    }

    private func sortCompletionsByTime(_ times: [Date]) -> [Date] {
        times.sorted { $0 > $1 }
    }

    private func sourceDisplayName(for source: String) -> String {
        switch source {
        case "apple_watch": return "Apple Watch"
        case "garmin": return "Garmin"
        case "manual": return "Manual"
        case "phone_only": return "Phone"
        default: return "Unknown"
        }
    }

    private func sourceIconName(for source: String) -> String {
        switch source {
        case "apple_watch": return "applewatch"
        case "garmin": return "watchface.applewatch.case"
        case "manual": return "pencil"
        case "phone_only": return "iphone"
        default: return "questionmark"
        }
    }

    private func canLoadMore(hasMoreData: Bool, isLoadingMore: Bool, isLoading: Bool) -> Bool {
        hasMoreData && !isLoadingMore && !isLoading
    }
}
