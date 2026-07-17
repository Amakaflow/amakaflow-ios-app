//
//  ActivityHistoryViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for ActivityHistoryViewModel using injected mock dependencies.
//  Added as part of AMA-344: Refactor ViewModels for Dependency Injection.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ActivityHistoryViewModelTests: XCTestCase {

    var viewModel: ActivityHistoryViewModel!
    var mockAPIService: MockAPIService!
    var mockPairingService: MockPairingService!
    var dependencies: AppDependencies!
    var testNow: Date!

    override func setUp() async throws {
        mockAPIService = MockAPIService()
        mockPairingService = MockPairingService()
        mockPairingService.configurePaired()

        mockAPIService.fetchCompletionsResult = .success(WorkoutCompletion.sampleData)

        dependencies = AppDependencies(
            apiService: mockAPIService,
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )

        testNow = Date()
        viewModel = ActivityHistoryViewModel(dependencies: dependencies, nowProvider: { [weak self] in self?.testNow ?? Date() })
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPIService = nil
        mockPairingService = nil
        dependencies = nil
        testNow = nil
    }

    // MARK: - Load Completions

    func testLoadCompletionsSuccessCallsAPI() async {
        await viewModel.loadCompletions()

        XCTAssertTrue(mockAPIService.fetchCompletionsCalled)
        XCTAssertFalse(viewModel.completions.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadCompletionsUsesInjectedService() async {
        // Inject a different set of completions to confirm we're using mock, not live service
        let testCompletion = WorkoutCompletion.sampleData.first!
        mockAPIService.fetchCompletionsResult = .success([testCompletion])

        await viewModel.loadCompletions()

        XCTAssertEqual(viewModel.completions.count, 1)
        XCTAssertEqual(viewModel.completions.first?.id, testCompletion.id)
    }

    func testLoadCompletionsSeedsTodaySampleWhenAPINonTodayOnly() async {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: testNow)!
        let staleCompletion = makeCompletion(id: "stale-yesterday", startedAt: yesterday)

        mockAPIService.fetchCompletionsResult = .success([staleCompletion])

        await viewModel.loadCompletions()

        #if DEBUG
        XCTAssertTrue(mockAPIService.fetchCompletionsCalled)
        XCTAssertEqual(viewModel.completions.count, 3)
        XCTAssertEqual(viewModel.completions.first?.id, "stale-yesterday")
        XCTAssertTrue(viewModel.todaysCompletions.allSatisfy(\.wasSimulated))
        XCTAssertEqual(viewModel.todaysCompletions.count, 2)
        #else
        XCTAssertEqual(viewModel.completions.count, 1)
        XCTAssertEqual(viewModel.completions.first?.id, "stale-yesterday")
        XCTAssertTrue(viewModel.todaysCompletions.isEmpty)
        #endif
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadCompletionsErrorShowsMessage() async {
        mockAPIService.fetchCompletionsResult = .failure(APIError.serverError(500))

        await viewModel.loadCompletions()

        #if DEBUG
        // DEBUG seeds handoff timeline on first-load failure for simulator verification.
        XCTAssertEqual(viewModel.completions.count, 2)
        XCTAssertTrue(viewModel.completions.allSatisfy(\.wasSimulated))
        XCTAssertNil(viewModel.errorMessage)
        #else
        XCTAssertTrue(viewModel.completions.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
        #endif
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadCompletionsNotPairedShowsEmpty() async {
        mockPairingService.isPaired = false

        await viewModel.loadCompletions()

        // Not authenticated — no API call
        XCTAssertFalse(mockAPIService.fetchCompletionsCalled)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        #if DEBUG
        // DEBUG seeds handoff timeline for simulator verification without pairing.
        XCTAssertEqual(viewModel.completions.count, 2)
        XCTAssertTrue(viewModel.completions.allSatisfy(\.wasSimulated))
        #else
        XCTAssertTrue(viewModel.completions.isEmpty)
        #endif
    }

    func testLoadCompletionsResetsErrorOnRetry() async {
        // First call fails
        mockAPIService.fetchCompletionsResult = .failure(APIError.serverError(500))
        await viewModel.loadCompletions()
        #if DEBUG
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.completions.allSatisfy(\.wasSimulated))
        #else
        XCTAssertNotNil(viewModel.errorMessage)
        #endif

        // Second call succeeds
        mockAPIService.fetchCompletionsResult = .success(WorkoutCompletion.sampleData)
        await viewModel.loadCompletions()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.completions.isEmpty)
    }

    func testLoadCompletionsUnauthorizedShowsSessionExpired() async {
        mockAPIService.fetchCompletionsResult = .failure(APIError.unauthorized)

        await viewModel.loadCompletions()

        XCTAssertEqual(viewModel.errorMessage, "Session expired. Please reconnect.")
    }

    // MARK: - Filter

    func testFilterAllReturnsAllCompletions() async {
        await viewModel.loadCompletions()

        viewModel.selectedFilter = .all
        XCTAssertEqual(viewModel.filteredCompletions.count, viewModel.completions.count)
    }

    func testThisWeekUsesCurrentCalendarWeekExcludingPreviousWeek() {
        let calendar = Calendar.current
        testNow = makeDate(year: 2026, month: 6, day: 2, hour: 12, calendar: calendar)
        viewModel.completions = [
            makeCompletion(id: "current-week", startedAt: makeDate(year: 2026, month: 6, day: 1, hour: 9, calendar: calendar)),
            makeCompletion(id: "previous-week", startedAt: makeDate(year: 2026, month: 5, day: 27, hour: 9, calendar: calendar))
        ]

        viewModel.selectedFilter = .thisWeek

        XCTAssertEqual(viewModel.filteredCompletions.map(\.id), ["current-week"])
        XCTAssertEqual(viewModel.weeklySummary.workoutCount, 1)
        XCTAssertEqual(viewModel.filterSummary.workoutCount, 1)
    }

    func testSelectedFilterSummaryMatchesRenderedCompletionCount() {
        let calendar = Calendar.current
        testNow = makeDate(year: 2026, month: 6, day: 2, hour: 12, calendar: calendar)
        viewModel.completions = [
            makeCompletion(id: "monday", startedAt: makeDate(year: 2026, month: 6, day: 1, hour: 8, calendar: calendar), durationSeconds: 1_800, calories: 200),
            makeCompletion(id: "tuesday", startedAt: makeDate(year: 2026, month: 6, day: 2, hour: 9, calendar: calendar), durationSeconds: 2_400, calories: 300),
            makeCompletion(id: "previous-week", startedAt: makeDate(year: 2026, month: 5, day: 27, hour: 9, calendar: calendar), durationSeconds: 1_200, calories: 150)
        ]

        viewModel.selectedFilter = .thisWeek
        let renderedCompletions = viewModel.groupedCompletions.flatMap { $0.completions }

        XCTAssertEqual(renderedCompletions.count, 2)
        XCTAssertEqual(viewModel.filterSummary.workoutCount, renderedCompletions.count)
        XCTAssertEqual(viewModel.filterSummary.totalDurationSeconds, 4_200)
        XCTAssertEqual(viewModel.filterSummary.totalCalories, 500)
        XCTAssertFalse(renderedCompletions.contains { $0.id == "previous-week" })
    }

    func testAllFilterSummaryMatchesAllRenderedCompletions() {
        let calendar = Calendar.current
        testNow = makeDate(year: 2026, month: 6, day: 2, hour: 12, calendar: calendar)
        viewModel.completions = [
            makeCompletion(id: "current-week", startedAt: makeDate(year: 2026, month: 6, day: 1, hour: 9, calendar: calendar)),
            makeCompletion(id: "previous-week", startedAt: makeDate(year: 2026, month: 5, day: 27, hour: 9, calendar: calendar))
        ]

        viewModel.selectedFilter = .all
        let renderedCompletions = viewModel.groupedCompletions.flatMap { $0.completions }

        XCTAssertEqual(viewModel.summaryTitle, "ALL")
        XCTAssertEqual(viewModel.filterSummary.workoutCount, renderedCompletions.count)
        XCTAssertEqual(renderedCompletions.count, 2)
    }

    func testThisWeekRendersAllNineInWindowCompletions() {
        let calendar = Calendar.current
        testNow = makeDate(year: 2026, month: 6, day: 2, hour: 12, calendar: calendar)
        viewModel.completions = (0..<9).map { index in
            makeCompletion(
                id: "in-week-\(index)",
                startedAt: makeDate(year: 2026, month: 6, day: 1, hour: index + 1, calendar: calendar)
            )
        } + [
            makeCompletion(id: "previous-week", startedAt: makeDate(year: 2026, month: 5, day: 27, hour: 9, calendar: calendar))
        ]

        viewModel.selectedFilter = .thisWeek
        let renderedCompletions = viewModel.groupedCompletions.flatMap { $0.completions }

        XCTAssertEqual(viewModel.filterSummary.workoutCount, 9)
        XCTAssertEqual(viewModel.groupedCompletions.count, 1)
        XCTAssertEqual(renderedCompletions.count, 9)
        XCTAssertEqual(Set(renderedCompletions.map(\.id)), Set((0..<9).map { "in-week-\($0)" }))
    }

    // MARK: - Weekly Summary Distance

    func testWeeklySummaryAggregatesDistanceMeters() {
        let calendar = Calendar.current
        testNow = makeDate(year: 2026, month: 6, day: 2, hour: 12, calendar: calendar)
        viewModel.completions = [
            makeCompletion(
                id: "run-a",
                startedAt: makeDate(year: 2026, month: 6, day: 1, hour: 8, calendar: calendar),
                distanceMeters: 6200
            ),
            makeCompletion(
                id: "run-b",
                startedAt: makeDate(year: 2026, month: 6, day: 2, hour: 9, calendar: calendar),
                distanceMeters: 3840
            ),
            makeCompletion(
                id: "strength",
                startedAt: makeDate(year: 2026, month: 6, day: 2, hour: 10, calendar: calendar),
                distanceMeters: nil
            )
        ]

        viewModel.selectedFilter = .thisWeek

        XCTAssertEqual(viewModel.filterSummary.totalDistanceMeters, 10_040)
        XCTAssertEqual(viewModel.filterSummary.formattedDistance, "10.0")
    }

    func testWeeklySummaryFormattedDistanceUsesOneDecimalKm() {
        let summary = WeeklySummary(completions: [
            makeCompletion(
                id: "run",
                startedAt: Date(),
                distanceMeters: 38_400
            )
        ])

        XCTAssertEqual(summary.formattedDistance, "38.4")
    }

    func testWorkoutCompletionDecodesDistanceMetersFromAPIPayload() throws {
        let json = """
        {
          "id": "completion-1",
          "workout_name": "Morning Run",
          "started_at": "2026-06-01T10:00:00Z",
          "duration_seconds": 1800,
          "source": "apple_watch",
          "distance_meters": 6200
        }
        """
        let completion = try APIService.makeDecoder().decode(
            WorkoutCompletion.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(completion.distanceMeters, 6200)
    }

    func testRefreshCompletionsOnNetworkFailurePreservesExistingContent() async {
        // Load initial content successfully
        mockAPIService.fetchCompletionsResult = .success(WorkoutCompletion.sampleData)
        await viewModel.loadCompletions()
        let preRefreshCount = viewModel.completions.count
        XCTAssertGreaterThan(preRefreshCount, 0)

        // Refresh fails with a network error
        mockAPIService.fetchCompletionsResult = .failure(APIError.networkError(URLError(.notConnectedToInternet)))
        await viewModel.refreshCompletions()

        // Existing content must be preserved; inline error affordance shown
        XCTAssertEqual(viewModel.completions.count, preRefreshCount, "Refresh failure must not wipe existing history")
        XCTAssertNotNil(viewModel.errorMessage, "Inline error must appear on refresh failure")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testRefreshCompletionsOnAPIErrorPreservesExistingContent() async {
        // Load initial content successfully
        mockAPIService.fetchCompletionsResult = .success(WorkoutCompletion.sampleData)
        await viewModel.loadCompletions()
        let preRefreshCount = viewModel.completions.count
        XCTAssertGreaterThan(preRefreshCount, 0)

        // Refresh fails with a server error
        mockAPIService.fetchCompletionsResult = .failure(APIError.serverError(500))
        await viewModel.refreshCompletions()

        // Existing content must be preserved
        XCTAssertEqual(viewModel.completions.count, preRefreshCount, "Server error on refresh must not wipe existing history")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Demo Mode

    func testDemoModeSkipsAPICall() async {
        viewModel.useDemoMode = true

        await viewModel.loadCompletions()

        XCTAssertFalse(mockAPIService.fetchCompletionsCalled)
        XCTAssertFalse(viewModel.completions.isEmpty) // Demo loads mock data
    }

    // MARK: - Test Helpers

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func makeCompletion(
        id: String,
        startedAt: Date,
        durationSeconds: Int = 600,
        calories: Int? = 100,
        distanceMeters: Int? = nil
    ) -> WorkoutCompletion {
        WorkoutCompletion(
            id: id,
            workoutName: "Workout \(id)",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(TimeInterval(durationSeconds)),
            durationSeconds: durationSeconds,
            avgHeartRate: nil,
            maxHeartRate: nil,
            activeCalories: calories,
            distanceMeters: distanceMeters,
            source: .phone,
            syncedToStrava: false,
            workoutId: nil,
            originalWorkout: nil,
            isSimulated: false
        )
    }
}
