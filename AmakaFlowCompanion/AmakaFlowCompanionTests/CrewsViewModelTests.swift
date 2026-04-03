//
//  CrewsViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for CrewsViewModel — crew loading, detail, feed, creation, join, leave (AMA-1277)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class CrewsViewModelTests: XCTestCase {

    private var mockAPI: MockAPIService!
    private var sut: CrewsViewModel!

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
        sut = CrewsViewModel(dependencies: deps)
    }

    // MARK: - Load Crews

    func testLoadCrews() async {
        let crews = [
            makeCrew(id: "1", name: "Alpha Squad"),
            makeCrew(id: "2", name: "Beta Crew")
        ]
        mockAPI.fetchMyCrewsResult = .success(CrewListResponse(crews: crews, count: 2))

        await sut.loadCrews()

        XCTAssertEqual(sut.crews.count, 2)
        XCTAssertEqual(sut.crews[0].name, "Alpha Squad")
        XCTAssertEqual(sut.crews[1].name, "Beta Crew")
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(mockAPI.fetchMyCrewsCalled)
    }

    // MARK: - Load Crew Detail

    func testLoadCrewDetail() async {
        let detail = makeCrewDetail(id: "1", name: "Alpha Squad", memberCount: 5)
        mockAPI.fetchCrewDetailResult = .success(detail)

        await sut.loadCrewDetail(id: "1")

        XCTAssertNotNil(sut.selectedCrewDetail)
        XCTAssertEqual(sut.selectedCrewDetail?.id, "1")
        XCTAssertEqual(sut.selectedCrewDetail?.name, "Alpha Squad")
        XCTAssertEqual(sut.selectedCrewDetail?.memberCount, 5)
        XCTAssertFalse(sut.isLoadingDetail)
        XCTAssertTrue(mockAPI.fetchCrewDetailCalled)
    }

    // MARK: - Load Crew Feed

    func testLoadCrewFeed() async {
        let posts = [
            makeCrewFeedPost(id: "p1"),
            makeCrewFeedPost(id: "p2")
        ]
        mockAPI.fetchCrewFeedResult = .success(CrewFeedResponse(posts: posts, nextCursor: nil))

        await sut.loadCrewFeed(crewId: "1")

        XCTAssertEqual(sut.crewFeedPosts.count, 2)
        XCTAssertEqual(sut.crewFeedPosts[0].id, "p1")
        XCTAssertFalse(sut.isLoadingFeed)
        XCTAssertTrue(mockAPI.fetchCrewFeedCalled)
    }

    // MARK: - Create Crew

    func testCreateCrew() async {
        mockAPI.fetchMyCrewsResult = .success(CrewListResponse(crews: [], count: 0))

        let success = await sut.createCrew(name: "New Crew", description: "A test crew", maxMembers: 10)

        XCTAssertTrue(success)
        XCTAssertTrue(mockAPI.createCrewCalled)
        XCTAssertFalse(sut.isCreating)
        XCTAssertNil(sut.createError)
    }

    // MARK: - Join Crew

    func testJoinCrew() async {
        mockAPI.fetchMyCrewsResult = .success(CrewListResponse(crews: [], count: 0))

        let success = await sut.joinCrew(crewId: "crew-1", inviteCode: "ALPHA123")

        XCTAssertTrue(success)
        XCTAssertTrue(mockAPI.joinCrewCalled)
        XCTAssertTrue(sut.joinSuccess)
        XCTAssertFalse(sut.isJoining)
        XCTAssertNil(sut.joinError)
    }

    // MARK: - Leave Crew

    func testLeaveCrew() async {
        mockAPI.fetchMyCrewsResult = .success(CrewListResponse(crews: [], count: 0))

        let success = await sut.leaveCrew(crewId: "crew-1")

        XCTAssertTrue(success)
        XCTAssertTrue(mockAPI.leaveCrewCalled)
    }

    // MARK: - Error Handling

    func testLoadCrewsError() async {
        mockAPI.fetchMyCrewsResult = .failure(APIError.serverError(500))

        await sut.loadCrews()

        XCTAssertTrue(sut.crews.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Helpers

    private func makeCrew(id: String, name: String) -> Crew {
        Crew(
            id: id,
            name: name,
            description: nil,
            createdBy: "user-1",
            maxMembers: 20,
            inviteCode: "CODE\(id)",
            memberCount: 3,
            createdAt: "2026-01-01T00:00:00Z"
        )
    }

    private func makeCrewDetail(id: String, name: String, memberCount: Int) -> CrewDetail {
        CrewDetail(
            id: id,
            name: name,
            description: nil,
            createdBy: "user-1",
            maxMembers: 20,
            inviteCode: "CODE\(id)",
            members: [],
            memberCount: memberCount,
            createdAt: "2026-01-01T00:00:00Z"
        )
    }

    private func makeCrewFeedPost(id: String) -> CrewFeedPost {
        CrewFeedPost(
            id: id,
            userId: "user-1",
            content: ["workout_name": "Test Workout"],
            photoUrl: nil,
            prBadges: [],
            createdAt: "2026-01-01T00:00:00Z"
        )
    }
}
