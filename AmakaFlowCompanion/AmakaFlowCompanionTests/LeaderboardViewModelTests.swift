//
//  LeaderboardViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for LeaderboardViewModel — leaderboard loading, scope/dimension/period switching, formatting (AMA-1278)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class LeaderboardViewModelTests: XCTestCase {

    private var mockAPI: MockAPIService!
    private var sut: LeaderboardViewModel!

    override func setUp() async throws {
        mockAPI = await MockAPIService()
        let deps = await AppDependencies(
            apiService: mockAPI,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        sut = LeaderboardViewModel(dependencies: deps)
    }

    // MARK: - Friends Leaderboard

    func testLoadFriendsLeaderboard() async {
        let entries = [
            makeEntry(userId: "u1", displayName: "Alice", value: 5000, rank: 1),
            makeEntry(userId: "u2", displayName: "Bob", value: 3000, rank: 2)
        ]
        mockAPI.fetchFriendsLeaderboardResult = .success(
            LeaderboardAPIResponse(dimension: "volume", period: "month", entries: entries)
        )

        await sut.loadLeaderboard()

        XCTAssertEqual(sut.entries.count, 2)
        XCTAssertEqual(sut.entries[0].displayName, "Alice")
        XCTAssertEqual(sut.entries[1].displayName, "Bob")
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(mockAPI.fetchFriendsLeaderboardCalled)
    }

    // MARK: - Crew Leaderboard

    func testLoadCrewLeaderboard() async {
        let deps = await AppDependencies(
            apiService: mockAPI,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        sut = LeaderboardViewModel(dependencies: deps, crewId: "crew-1")
        sut.selectedScope = .crew

        let entries = [makeEntry(userId: "u1", displayName: "Alice", value: 2000, rank: 1)]
        mockAPI.fetchCrewLeaderboardResult = .success(
            LeaderboardAPIResponse(dimension: "volume", period: "month", entries: entries)
        )

        await sut.loadLeaderboard()

        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertEqual(sut.entries[0].displayName, "Alice")
        XCTAssertFalse(sut.isLoading)
        XCTAssertTrue(mockAPI.fetchCrewLeaderboardCalled)
    }

    // MARK: - Change Dimension

    func testChangeDimension() async {
        let entries = [makeEntry(userId: "u1", displayName: "Alice", value: 5, rank: 1)]
        mockAPI.fetchFriendsLeaderboardResult = .success(
            LeaderboardAPIResponse(dimension: "consistency", period: "month", entries: entries)
        )

        await sut.changeDimension(.consistency)

        XCTAssertEqual(sut.selectedDimension, .consistency)
        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertTrue(mockAPI.fetchFriendsLeaderboardCalled)
    }

    // MARK: - Change Period

    func testChangePeriod() async {
        let entries = [makeEntry(userId: "u1", displayName: "Alice", value: 1000, rank: 1)]
        mockAPI.fetchFriendsLeaderboardResult = .success(
            LeaderboardAPIResponse(dimension: "volume", period: "week", entries: entries)
        )

        await sut.changePeriod(.week)

        XCTAssertEqual(sut.selectedPeriod, .week)
        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertTrue(mockAPI.fetchFriendsLeaderboardCalled)
    }

    // MARK: - Change Scope

    func testChangeScope() async {
        sut.crewId = "crew-99"
        let entries = [makeEntry(userId: "u1", displayName: "Alice", value: 800, rank: 1)]
        mockAPI.fetchCrewLeaderboardResult = .success(
            LeaderboardAPIResponse(dimension: "volume", period: "month", entries: entries)
        )

        await sut.changeScope(.crew)

        XCTAssertEqual(sut.selectedScope, .crew)
        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertTrue(mockAPI.fetchCrewLeaderboardCalled)
    }

    // MARK: - Formatted Value — Volume

    func testFormattedValueVolume() async {
        sut.selectedDimension = .volume

        let lowEntry = makeEntry(userId: "u1", displayName: "Alice", value: 500, rank: 1)
        XCTAssertEqual(sut.formattedValue(lowEntry), "500 kg")

        let highEntry = makeEntry(userId: "u2", displayName: "Bob", value: 2500, rank: 2)
        XCTAssertEqual(sut.formattedValue(highEntry), "2.5k kg")
    }

    // MARK: - Formatted Value — Consistency

    func testFormattedValueConsistency() async {
        sut.selectedDimension = .consistency

        let oneWeek = makeEntry(userId: "u1", displayName: "Alice", value: 1, rank: 1)
        XCTAssertEqual(sut.formattedValue(oneWeek), "1 week")

        let manyWeeks = makeEntry(userId: "u2", displayName: "Bob", value: 4, rank: 2)
        XCTAssertEqual(sut.formattedValue(manyWeeks), "4 weeks")
    }

    // MARK: - Error Handling

    func testLoadLeaderboardError() async {
        mockAPI.fetchFriendsLeaderboardResult = .failure(APIError.serverError(500))

        await sut.loadLeaderboard()

        XCTAssertTrue(sut.entries.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Helpers

    private func makeEntry(userId: String, displayName: String, value: Double, rank: Int) -> LeaderboardEntryModel {
        LeaderboardEntryModel(
            rank: rank,
            userId: userId,
            displayName: displayName,
            avatarUrl: nil,
            value: value,
            isMe: false
        )
    }
}
