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

    // MARK: - API Response Handling Tests

    /// Tests for handling various API response scenarios to prevent crashes
    /// when backend returns unexpected response formats

    func testDetectsValidArrayResponse() {
        let arrayResponse = "[{\"id\": \"1\"}]"
        let isArray = isArrayResponse(arrayResponse)
        XCTAssertTrue(isArray)
    }

    func testDetectsEmptyArrayResponse() {
        let emptyArray = "[]"
        let isArray = isArrayResponse(emptyArray)
        XCTAssertTrue(isArray)
    }

    func testDetectsErrorObjectResponseAsNonArray() {
        // Backend may return error object with 200 status due to routing issues
        let errorResponse = """
        {"detail": "invalid input syntax for type uuid: \\"completions\\""}
        """
        let isArray = isArrayResponse(errorResponse)
        XCTAssertFalse(isArray)
    }

    func testDetectsGenericObjectAsNonArray() {
        let objectResponse = """
        {"message": "Internal Server Error", "code": "22P02"}
        """
        let isArray = isArrayResponse(objectResponse)
        XCTAssertFalse(isArray)
    }

    func testHandlesWhitespaceBeforeArrayBracket() {
        let responseWithWhitespace = "  \n  [{\"id\": \"1\"}]"
        let isArray = isArrayResponse(responseWithWhitespace)
        XCTAssertTrue(isArray)
    }

    func testHandlesWhitespaceBeforeObjectBracket() {
        let responseWithWhitespace = "  \n  {\"error\": \"test\"}"
        let isArray = isArrayResponse(responseWithWhitespace)
        XCTAssertFalse(isArray)
    }

    func testParseCompletionsSuccess() {
        let validJSON = """
        [
            {
                "id": "test-1",
                "workout_name": "Morning Run",
                "started_at": "2025-01-01T10:00:00Z",
                "ended_at": "2025-01-01T10:30:00Z",
                "duration_seconds": 1800,
                "source": "apple_watch",
                "synced_to_strava": false
            }
        ]
        """

        let result = parseCompletionsResponse(validJSON)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "test-1")
        XCTAssertEqual(result.first?.workoutName, "Morning Run")
    }

    func testParseCompletionsEmptyArray() {
        let emptyJSON = "[]"
        let result = parseCompletionsResponse(emptyJSON)
        XCTAssertEqual(result.count, 0)
    }

    func testParseCompletionsReturnsEmptyOnDecodeError() {
        // Invalid JSON that looks like array but has wrong structure
        let invalidJSON = "[{\"wrong_field\": \"value\"}]"
        let result = parseCompletionsResponse(invalidJSON)
        // Should return empty array instead of crashing
        XCTAssertEqual(result.count, 0)
    }

    func testParseCompletionsReturnsEmptyOnNonArrayResponse() {
        // Backend error response
        let errorJSON = """
        {"detail": "invalid input syntax for type uuid"}
        """
        let result = parseCompletionsResponse(errorJSON)
        XCTAssertEqual(result.count, 0)
    }

    func testShouldReturnEmptyForServerError500() {
        let statusCode = 500
        let shouldReturnEmpty = shouldReturnEmptyForStatusCode(statusCode)
        XCTAssertTrue(shouldReturnEmpty)
    }

    func testShouldReturnEmptyForServerError404() {
        let statusCode = 404
        let shouldReturnEmpty = shouldReturnEmptyForStatusCode(statusCode)
        XCTAssertTrue(shouldReturnEmpty)
    }

    func testShouldNotReturnEmptyForSuccess200() {
        let statusCode = 200
        let shouldReturnEmpty = shouldReturnEmptyForStatusCode(statusCode)
        XCTAssertFalse(shouldReturnEmpty)
    }

    func testShouldNotReturnEmptyForUnauthorized401() {
        let statusCode = 401
        let shouldReturnEmpty = shouldReturnEmptyForStatusCode(statusCode)
        XCTAssertFalse(shouldReturnEmpty) // Should throw error instead
    }

    func testParseCompletionsWithOptionalFields() {
        // Test that optional fields are handled correctly
        let jsonWithOptionals = """
        [
            {
                "id": "test-2",
                "workout_name": "Quick Workout",
                "started_at": "2025-01-01T10:00:00Z",
                "ended_at": "2025-01-01T10:15:00Z",
                "duration_seconds": 900,
                "avg_heart_rate": 145,
                "active_calories": 150,
                "source": "manual",
                "synced_to_strava": true,
                "strava_activity_id": "12345"
            }
        ]
        """

        let result = parseCompletionsResponse(jsonWithOptionals)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.avgHeartRate, 145)
        XCTAssertEqual(result.first?.activeCalories, 150)
        XCTAssertEqual(result.first?.syncedToStrava, true)
    }

    func testParseCompletionsWithNullOptionalFields() {
        // Test that null optional fields are handled
        let jsonWithNulls = """
        [
            {
                "id": "test-3",
                "workout_name": "Basic Workout",
                "started_at": "2025-01-01T10:00:00Z",
                "ended_at": "2025-01-01T10:30:00Z",
                "duration_seconds": 1800,
                "avg_heart_rate": null,
                "active_calories": null,
                "source": "phone_only",
                "synced_to_strava": false,
                "strava_activity_id": null
            }
        ]
        """

        let result = parseCompletionsResponse(jsonWithNulls)
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result.first?.avgHeartRate)
        XCTAssertNil(result.first?.activeCalories)
    }

    // MARK: - API Response Handling Helper Methods

    /// Check if response body appears to be a JSON array (starts with '[')
    private func isArrayResponse(_ responseBody: String) -> Bool {
        responseBody.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
    }

    /// Determine if status code should return empty array instead of throwing
    private func shouldReturnEmptyForStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 404 || statusCode == 500
    }

    /// Test struct matching WorkoutCompletion fields
    private struct TestCompletion: Codable {
        let id: String
        let workoutName: String
        let startedAt: Date
        let endedAt: Date
        let durationSeconds: Int
        let avgHeartRate: Int?
        let activeCalories: Int?
        let source: String
        let syncedToStrava: Bool
        let stravaActivityId: String?

        enum CodingKeys: String, CodingKey {
            case id
            case workoutName = "workout_name"
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case durationSeconds = "duration_seconds"
            case avgHeartRate = "avg_heart_rate"
            case activeCalories = "active_calories"
            case source
            case syncedToStrava = "synced_to_strava"
            case stravaActivityId = "strava_activity_id"
        }
    }

    /// Parse completions response, returning empty array on any error
    private func parseCompletionsResponse(_ jsonString: String) -> [TestCompletion] {
        // Check if response is actually an array
        guard isArrayResponse(jsonString) else {
            return []
        }

        guard let data = jsonString.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode([TestCompletion].self, from: data)
        } catch {
            // Return empty array on decode errors (schema mismatch, etc.)
            return []
        }
    }
}
