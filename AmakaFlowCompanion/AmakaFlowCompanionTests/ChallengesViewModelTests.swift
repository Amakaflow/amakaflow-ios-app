//
//  ChallengesViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for ChallengesViewModel — challenge loading, filtering, joining, creation (AMA-1276)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ChallengesViewModelTests: XCTestCase {

    private var mockAPI: MockAPIService!
    private var sut: ChallengesViewModel!

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
        sut = ChallengesViewModel(dependencies: deps)
    }

    // MARK: - Loading

    func testLoadChallengesSuccess() async {
        let challenges = [
            makeChallenge(id: "1", title: "Volume Week", type: .volume),
            makeChallenge(id: "2", title: "Streak 7", type: .consistency),
            makeChallenge(id: "3", title: "PR Hunt", type: .pr)
        ]
        mockAPI.fetchChallengesResult = .success(ChallengesResponse(challenges: challenges))

        await sut.loadChallenges()

        XCTAssertEqual(sut.challenges.count, 3)
        XCTAssertEqual(sut.filteredChallenges.count, 3)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(mockAPI.fetchChallengesCalled)
    }

    func testLoadChallengesError() async {
        mockAPI.fetchChallengesResult = .failure(APIError.serverError(500))

        await sut.loadChallenges()

        XCTAssertTrue(sut.challenges.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Filtering

    func testFilterByType() async {
        let challenges = [
            makeChallenge(id: "1", title: "Volume", type: .volume),
            makeChallenge(id: "2", title: "Consistency", type: .consistency),
            makeChallenge(id: "3", title: "PR", type: .pr)
        ]
        mockAPI.fetchChallengesResult = .success(ChallengesResponse(challenges: challenges))
        await sut.loadChallenges()

        sut.setTypeFilter(.volume)
        XCTAssertEqual(sut.filteredChallenges.count, 1)
        XCTAssertEqual(sut.filteredChallenges[0].type, .volume)

        sut.setTypeFilter(.consistency)
        XCTAssertEqual(sut.filteredChallenges.count, 1)
        XCTAssertEqual(sut.filteredChallenges[0].type, .consistency)

        sut.setTypeFilter(nil) // "All"
        XCTAssertEqual(sut.filteredChallenges.count, 3)
    }

    // MARK: - Detail Loading

    func testLoadChallengeDetail() async {
        let challenge = makeChallenge(id: "1", title: "Test Challenge", type: .volume)
        let leaderboard = [
            LeaderboardEntry(id: "le-1", rank: 1, userId: "u1", userName: "Alice", userAvatarUrl: nil, progress: 800, progressPercentage: 80),
            LeaderboardEntry(id: "le-2", rank: 2, userId: "u2", userName: "Bob", userAvatarUrl: nil, progress: 500, progressPercentage: 50)
        ]
        let progress = ChallengeProgress(challengeId: "1", currentValue: 700, targetValue: 1000, percentage: 70, isCompleted: false, completedAt: nil, badge: nil)

        mockAPI.fetchChallengeDetailResult = .success(
            ChallengeDetailResponse(challenge: challenge, leaderboard: leaderboard, myProgress: progress)
        )

        await sut.loadChallengeDetail(id: "1")

        XCTAssertNotNil(sut.selectedChallenge)
        XCTAssertEqual(sut.selectedChallenge?.leaderboard.count, 2)
        XCTAssertEqual(sut.selectedChallenge?.myProgress?.percentage, 70)
        XCTAssertFalse(sut.isLoadingDetail)
        XCTAssertTrue(mockAPI.fetchChallengeDetailCalled)
    }

    // MARK: - Celebration

    func testCompletionTriggersCelebration() async {
        let challenge = makeChallenge(id: "1", title: "Done!", type: .pr)
        let badge = ChallengeBadge(id: "b1", name: "PR Hunter", iconName: "trophy.fill", description: "Completed a PR challenge")
        let progress = ChallengeProgress(challengeId: "1", currentValue: 100, targetValue: 100, percentage: 100, isCompleted: true, completedAt: Date(), badge: badge)

        mockAPI.fetchChallengeDetailResult = .success(
            ChallengeDetailResponse(challenge: challenge, leaderboard: [], myProgress: progress)
        )

        await sut.loadChallengeDetail(id: "1")

        XCTAssertTrue(sut.showCelebration)
        XCTAssertEqual(sut.completedBadge?.name, "PR Hunter")
    }

    func testDismissCelebration() {
        sut.showCelebration = true
        sut.completedBadge = ChallengeBadge(id: "b1", name: "Test", iconName: "star", description: "Test")

        sut.dismissCelebration()

        XCTAssertFalse(sut.showCelebration)
        XCTAssertNil(sut.completedBadge)
    }

    // MARK: - Join

    func testJoinChallenge() async {
        let challenge = makeChallenge(id: "1", title: "Test", type: .volume)
        mockAPI.fetchChallengesResult = .success(ChallengesResponse(challenges: [challenge]))
        mockAPI.fetchChallengeDetailResult = .success(
            ChallengeDetailResponse(challenge: challenge, leaderboard: [], myProgress: nil)
        )

        await sut.joinChallenge(id: "1")

        XCTAssertTrue(mockAPI.joinChallengeCalled)
        XCTAssertFalse(sut.isJoining)
    }

    // MARK: - Create

    func testCreateChallengeSuccess() async {
        mockAPI.fetchChallengesResult = .success(ChallengesResponse(challenges: []))

        let request = CreateChallengeRequest(
            title: "New Challenge",
            type: .volume,
            description: nil,
            target: 5000,
            targetUnit: "kg",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400 * 7),
            isTeamMode: false
        )

        let success = await sut.createChallenge(request)

        XCTAssertTrue(success)
        XCTAssertTrue(mockAPI.createChallengeCalled)
        XCTAssertFalse(sut.isCreating)
        XCTAssertNil(sut.createError)
    }

    // MARK: - Helpers

    private func makeChallenge(
        id: String,
        title: String,
        type: ChallengeType,
        isJoined: Bool = false
    ) -> Challenge {
        Challenge(
            id: id,
            title: title,
            type: type,
            status: .active,
            description: nil,
            target: 1000,
            targetUnit: "kg",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400 * 7),
            creatorId: "creator-1",
            creatorName: "TestUser",
            participantCount: 5,
            isTeamMode: false,
            isJoined: isJoined,
            myProgress: nil,
            myProgressPercentage: nil
        )
    }
}
