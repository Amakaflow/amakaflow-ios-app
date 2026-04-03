//
//  VolumeAnalyticsViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for VolumeAnalyticsViewModel — loading, balance ratios, sorting, error handling (AMA-1414)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class VolumeAnalyticsViewModelTests: XCTestCase {

    private var mockAPI: MockAPIService!
    private var sut: VolumeAnalyticsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI = await MockAPIService()
        let deps = await AppDependencies(
            apiService: mockAPI,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        sut = VolumeAnalyticsViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        sut = nil
        mockAPI = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeResponse(
        totalVolume: Double = 5000,
        totalSets: Int = 120,
        totalReps: Int = 1440,
        breakdown: [String: Double] = [:],
        dataPoints: [VolumeDataPoint] = []
    ) -> VolumeAnalyticsResponse {
        VolumeAnalyticsResponse(
            data: dataPoints,
            summary: VolumeSummary(
                totalVolume: totalVolume,
                totalSets: totalSets,
                totalReps: totalReps,
                muscleGroupBreakdown: breakdown
            ),
            period: VolumePeriod(startDate: "2026-03-01", endDate: "2026-03-31"),
            granularity: "weekly"
        )
    }

    // MARK: - testLoadVolume

    func testLoadVolume_populatesCurrentData() async {
        let response = makeResponse(totalVolume: 8000, totalSets: 200, totalReps: 2400)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        XCTAssertNotNil(sut.currentData, "currentData should be set after successful load")
        XCTAssertEqual(sut.currentData?.summary.totalVolume, 8000)
        XCTAssertEqual(sut.currentData?.summary.totalSets, 200)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(mockAPI.fetchVolumeAnalyticsCalled)
    }

    func testLoadVolume_populatesPreviousData() async {
        let response = makeResponse(totalVolume: 6000)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        XCTAssertNotNil(sut.previousData, "previousData should be set (both calls return same mock)")
    }

    // MARK: - testPushPullRatio

    func testPushPullRatio_calculatesCorrectly() async {
        let breakdown: [String: Double] = [
            "chest": 2000,
            "shoulders": 1000,
            "triceps": 500,   // push total = 3500
            "back": 2000,
            "biceps": 1500    // pull total = 3500
        ]
        let response = makeResponse(breakdown: breakdown)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        XCTAssertNotNil(sut.pushPullRatio)
        // 3500 / 3500 = 1.0
        XCTAssertEqual(sut.pushPullRatio!, 1.0, accuracy: 0.001)
    }

    func testPushPullRatio_imbalancedHighPush() async {
        let breakdown: [String: Double] = [
            "chest": 3000,
            "shoulders": 2000,
            "triceps": 1000,  // push total = 6000
            "back": 1000,
            "biceps": 500     // pull total = 1500
        ]
        let response = makeResponse(breakdown: breakdown)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        XCTAssertNotNil(sut.pushPullRatio)
        // 6000 / 1500 = 4.0
        XCTAssertEqual(sut.pushPullRatio!, 4.0, accuracy: 0.001)
    }

    func testPushPullRatio_nilWhenNoPullVolume() async {
        let breakdown: [String: Double] = [
            "chest": 2000,
            "legs": 3000
            // no pull muscles
        ]
        let response = makeResponse(breakdown: breakdown)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        XCTAssertNil(sut.pushPullRatio, "Should be nil when pull muscles have zero volume")
    }

    // MARK: - testUpperLowerRatio

    func testUpperLowerRatio_calculatesCorrectly() async {
        let breakdown: [String: Double] = [
            "chest": 1000,
            "back": 1000,
            "shoulders": 500,
            "biceps": 250,
            "triceps": 250,   // upper total = 3000
            "legs": 1500,
            "glutes": 1000,
            "hamstrings": 500 // lower total = 3000
        ]
        let response = makeResponse(breakdown: breakdown)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        XCTAssertNotNil(sut.upperLowerRatio)
        // 3000 / 3000 = 1.0
        XCTAssertEqual(sut.upperLowerRatio!, 1.0, accuracy: 0.001)
    }

    func testUpperLowerRatio_nilWhenNoLowerVolume() async {
        let breakdown: [String: Double] = [
            "chest": 2000,
            "back": 1000
            // no lower muscles
        ]
        let response = makeResponse(breakdown: breakdown)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        XCTAssertNil(sut.upperLowerRatio, "Should be nil when lower muscles have zero volume")
    }

    // MARK: - testSortedMuscleGroups

    func testSortedMuscleGroups_sortedByVolumeDescending() async {
        let breakdown: [String: Double] = [
            "legs": 3000,
            "chest": 1000,
            "back": 2000
        ]
        let response = makeResponse(totalVolume: 6000, breakdown: breakdown)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        let groups = sut.sortedMuscleGroups
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].name, "legs")
        XCTAssertEqual(groups[1].name, "back")
        XCTAssertEqual(groups[2].name, "chest")
    }

    func testSortedMuscleGroups_percentageSumsToHundred() async {
        let breakdown: [String: Double] = [
            "chest": 2500,
            "back": 2500
        ]
        let response = makeResponse(totalVolume: 5000, breakdown: breakdown)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        let total = sut.sortedMuscleGroups.reduce(0.0) { $0 + $1.percentage }
        XCTAssertEqual(total, 100.0, accuracy: 0.001)
    }

    func testSortedMuscleGroups_emptyWhenNoData() async {
        let response = makeResponse(breakdown: [:])
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        XCTAssertTrue(sut.sortedMuscleGroups.isEmpty, "Should be empty when no breakdown data")
    }

    // MARK: - testVolumeChange

    func testVolumeChange_positiveWhenCurrentHigher() async {
        // fetchVolumeAnalytics is called twice (current + previous), both return the same mock
        // We set up current as 6000 and previous as 5000 by alternating results
        // Since mock returns the same result for both, set current=6000 and
        // then manually inject previousData to test the calculation logic
        let currentResponse = makeResponse(totalVolume: 6000)
        let previousResponse = makeResponse(totalVolume: 5000)
        mockAPI.fetchVolumeAnalyticsResult = .success(currentResponse)

        await sut.loadVolume()

        // Manually set previousData to simulate a lower previous period
        sut.previousData = previousResponse

        // volumeChange = (6000 - 5000) / 5000 * 100 = 20%
        XCTAssertNotNil(sut.volumeChange)
        XCTAssertEqual(sut.volumeChange!, 20.0, accuracy: 0.001)
    }

    func testVolumeChange_negativeWhenCurrentLower() async {
        let currentResponse = makeResponse(totalVolume: 4000)
        mockAPI.fetchVolumeAnalyticsResult = .success(currentResponse)

        await sut.loadVolume()

        sut.previousData = makeResponse(totalVolume: 5000)

        // volumeChange = (4000 - 5000) / 5000 * 100 = -20%
        XCTAssertNotNil(sut.volumeChange)
        XCTAssertEqual(sut.volumeChange!, -20.0, accuracy: 0.001)
    }

    func testVolumeChange_nilWhenNoPreviousData() {
        // No load, both currentData and previousData are nil
        XCTAssertNil(sut.volumeChange)
    }

    // MARK: - testLoadVolumeError

    func testLoadVolumeError_setsErrorMessage() async {
        mockAPI.fetchVolumeAnalyticsResult = .failure(APIError.serverError(500))

        await sut.loadVolume()

        XCTAssertNotNil(sut.errorMessage, "Should have error message on failure")
        XCTAssertEqual(sut.errorMessage, "Could not load volume data")
        XCTAssertNil(sut.currentData)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadVolumeError_clearsOnRetry() async {
        mockAPI.fetchVolumeAnalyticsResult = .failure(APIError.serverError(500))
        await sut.loadVolume()
        XCTAssertNotNil(sut.errorMessage)

        let response = makeResponse(totalVolume: 1000)
        mockAPI.fetchVolumeAnalyticsResult = .success(response)
        await sut.loadVolume()

        XCTAssertNil(sut.errorMessage, "Error should clear on successful retry")
        XCTAssertNotNil(sut.currentData)
    }

    // MARK: - testBalanceRatioWithZeroVolume

    func testBalanceRatioWithZeroVolume_returnsNil() async {
        // Empty breakdown — no muscle data at all
        let response = makeResponse(breakdown: [:])
        mockAPI.fetchVolumeAnalyticsResult = .success(response)

        await sut.loadVolume()

        XCTAssertNil(sut.pushPullRatio, "pushPullRatio should be nil with no muscle data")
        XCTAssertNil(sut.upperLowerRatio, "upperLowerRatio should be nil with no muscle data")
    }

    func testBalanceRatioWithNoCurrentData_returnsNil() {
        // Before any load, currentData is nil
        XCTAssertNil(sut.pushPullRatio)
        XCTAssertNil(sut.upperLowerRatio)
    }
}
