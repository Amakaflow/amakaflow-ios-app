//
//  FatigueHistoryViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for FatigueHistoryViewModel (AMA-1412)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class FatigueHistoryViewModelTests: XCTestCase {

    var viewModel: FatigueHistoryViewModel!
    var mockAPI: MockAPIService!

    override func setUp() async throws {
        mockAPI = MockAPIService()
        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        viewModel = FatigueHistoryViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPI = nil
    }

    // MARK: - loadHistory

    func testLoadHistorySuccess() async {
        let day1 = DayState(
            date: "2026-04-02",
            readiness: .green,
            plannedWorkouts: [],
            completedWorkouts: [],
            fatigueScore: 80,
            notes: nil
        )
        let day2 = DayState(
            date: "2026-04-01",
            readiness: .yellow,
            plannedWorkouts: [],
            completedWorkouts: [],
            fatigueScore: 60,
            notes: nil
        )
        mockAPI.fetchDayStatesResult = .success([day2, day1]) // unordered input

        await viewModel.loadHistory()

        XCTAssertTrue(mockAPI.fetchDayStatesCalled)
        XCTAssertEqual(viewModel.dayStates.count, 2)
        // Should be sorted descending by date
        XCTAssertEqual(viewModel.dayStates[0].date, "2026-04-02")
        XCTAssertEqual(viewModel.dayStates[1].date, "2026-04-01")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadHistoryError() async {
        mockAPI.fetchDayStatesResult = .failure(APIError.serverError(500))

        await viewModel.loadHistory()

        XCTAssertTrue(mockAPI.fetchDayStatesCalled)
        XCTAssertEqual(viewModel.dayStates.count, 0)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "Could not load readiness history")
    }

    func testLoadHistoryClearsErrorOnRetry() async {
        mockAPI.fetchDayStatesResult = .failure(APIError.serverError(500))
        await viewModel.loadHistory()
        XCTAssertNotNil(viewModel.errorMessage)

        mockAPI.fetchDayStatesResult = .success([])
        await viewModel.loadHistory()

        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadHistorySetsIsLoadingDuringFetch() async {
        // Verify isLoading resets to false after completion
        mockAPI.fetchDayStatesResult = .success([])
        await viewModel.loadHistory()
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - averageFatigueScore

    func testAverageFatigueScoreWithScores() async {
        mockAPI.fetchDayStatesResult = .success([
            DayState(date: "2026-04-02", readiness: .green, plannedWorkouts: [], completedWorkouts: [], fatigueScore: 80, notes: nil),
            DayState(date: "2026-04-01", readiness: .yellow, plannedWorkouts: [], completedWorkouts: [], fatigueScore: 60, notes: nil),
            DayState(date: "2026-03-31", readiness: .red, plannedWorkouts: [], completedWorkouts: [], fatigueScore: 40, notes: nil)
        ])

        await viewModel.loadHistory()

        let avg = viewModel.averageFatigueScore
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!, 60.0, accuracy: 0.01)
    }

    func testAverageFatigueScoreNilWhenNoScores() async {
        mockAPI.fetchDayStatesResult = .success([
            DayState(date: "2026-04-02", readiness: .green, plannedWorkouts: [], completedWorkouts: [], fatigueScore: nil, notes: nil)
        ])

        await viewModel.loadHistory()

        XCTAssertNil(viewModel.averageFatigueScore)
    }

    func testAverageFatigueScoreNilWhenEmpty() {
        XCTAssertNil(viewModel.averageFatigueScore)
    }

    // MARK: - Readiness Counts

    func testReadinessCounts() async {
        mockAPI.fetchDayStatesResult = .success([
            DayState(date: "2026-04-02", readiness: .green, plannedWorkouts: [], completedWorkouts: [], fatigueScore: nil, notes: nil),
            DayState(date: "2026-04-01", readiness: .green, plannedWorkouts: [], completedWorkouts: [], fatigueScore: nil, notes: nil),
            DayState(date: "2026-03-31", readiness: .yellow, plannedWorkouts: [], completedWorkouts: [], fatigueScore: nil, notes: nil),
            DayState(date: "2026-03-30", readiness: .red, plannedWorkouts: [], completedWorkouts: [], fatigueScore: nil, notes: nil),
            DayState(date: "2026-03-29", readiness: .rest, plannedWorkouts: [], completedWorkouts: [], fatigueScore: nil, notes: nil)
        ])

        await viewModel.loadHistory()

        XCTAssertEqual(viewModel.greenDays, 2)
        XCTAssertEqual(viewModel.yellowDays, 1)
        XCTAssertEqual(viewModel.redDays, 1)
    }

    func testReadinessCountsZeroWhenEmpty() {
        XCTAssertEqual(viewModel.greenDays, 0)
        XCTAssertEqual(viewModel.yellowDays, 0)
        XCTAssertEqual(viewModel.redDays, 0)
    }

    // MARK: - changeRange

    func testChangeRangeUpdatesSelectedRange() async {
        XCTAssertEqual(viewModel.selectedRange, .twoWeeks)

        mockAPI.fetchDayStatesResult = .success([])
        viewModel.changeRange(.oneWeek)

        XCTAssertEqual(viewModel.selectedRange, .oneWeek)
    }

    func testChangeRangeToOneMonthTriggersLoad() async {
        mockAPI.fetchDayStatesResult = .success([])
        viewModel.changeRange(.oneMonth)

        // Give the spawned Task time to complete
        await waitForAsync(seconds: 0.1)

        XCTAssertEqual(viewModel.selectedRange, .oneMonth)
        XCTAssertTrue(mockAPI.fetchDayStatesCalled)
    }

    // MARK: - DateRange enum

    func testDateRangeDays() {
        XCTAssertEqual(FatigueHistoryViewModel.DateRange.oneWeek.days, 7)
        XCTAssertEqual(FatigueHistoryViewModel.DateRange.twoWeeks.days, 14)
        XCTAssertEqual(FatigueHistoryViewModel.DateRange.oneMonth.days, 30)
    }

    func testDateRangeRawValues() {
        XCTAssertEqual(FatigueHistoryViewModel.DateRange.oneWeek.rawValue, "1W")
        XCTAssertEqual(FatigueHistoryViewModel.DateRange.twoWeeks.rawValue, "2W")
        XCTAssertEqual(FatigueHistoryViewModel.DateRange.oneMonth.rawValue, "1M")
    }

    func testDefaultSelectedRangeIsTwoWeeks() {
        XCTAssertEqual(viewModel.selectedRange, .twoWeeks)
    }
}
