//
//  FeedViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for FeedViewModel — feed loading, pagination, reactions, comments (AMA-1273)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class FeedViewModelTests: XCTestCase {

    private var mockAPI: MockAPIService!
    private var sut: FeedViewModel!

    override func setUp() async throws {
        mockAPI = await MockAPIService()
        let deps = await AppDependencies(
            apiService: mockAPI,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        sut = FeedViewModel(dependencies: deps)
    }

    // MARK: - Feed Loading

    func testLoadFeedSuccess() async {
        let posts = [
            makeFeedPost(id: "1", userName: "Alice", workoutName: "Push Day"),
            makeFeedPost(id: "2", userName: "Bob", workoutName: "Leg Day")
        ]
        mockAPI.fetchSocialFeedResult = .success(
            FeedResponse(posts: posts, nextCursor: "cursor-abc", hasMore: true)
        )

        await sut.loadFeed()

        XCTAssertEqual(sut.posts.count, 2)
        XCTAssertEqual(sut.posts[0].userName, "Alice")
        XCTAssertEqual(sut.posts[1].workoutName, "Leg Day")
        XCTAssertEqual(sut.nextCursor, "cursor-abc")
        XCTAssertTrue(sut.hasMore)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    func testLoadFeedError() async {
        mockAPI.fetchSocialFeedResult = .failure(APIError.serverError(500))

        await sut.loadFeed()

        XCTAssertTrue(sut.posts.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadMoreAppendsPosts() async {
        let firstPage = [makeFeedPost(id: "1", userName: "Alice", workoutName: "Push Day")]
        mockAPI.fetchSocialFeedResult = .success(
            FeedResponse(posts: firstPage, nextCursor: "cursor-1", hasMore: true)
        )
        await sut.loadFeed()

        let secondPage = [makeFeedPost(id: "2", userName: "Bob", workoutName: "Pull Day")]
        mockAPI.fetchSocialFeedResult = .success(
            FeedResponse(posts: secondPage, nextCursor: nil, hasMore: false)
        )
        await sut.loadMore()

        XCTAssertEqual(sut.posts.count, 2)
        XCTAssertEqual(sut.posts[0].id, "1")
        XCTAssertEqual(sut.posts[1].id, "2")
        XCTAssertFalse(sut.hasMore)
    }

    func testLoadMoreDoesNothingWithoutCursor() async {
        mockAPI.fetchSocialFeedResult = .success(
            FeedResponse(posts: [], nextCursor: nil, hasMore: false)
        )
        await sut.loadFeed()

        await sut.loadMore()
        // Should not crash; posts remain empty
        XCTAssertTrue(sut.posts.isEmpty)
    }

    // MARK: - Reactions

    func testToggleReactionAdds() async {
        let posts = [makeFeedPost(id: "1", userName: "Alice", workoutName: "Push Day")]
        mockAPI.fetchSocialFeedResult = .success(
            FeedResponse(posts: posts, nextCursor: nil, hasMore: false)
        )
        await sut.loadFeed()

        await sut.toggleReaction(postId: "1", emoji: "heart")

        XCTAssertTrue(sut.posts[0].userReactions.contains("heart"))
        XCTAssertTrue(mockAPI.addSocialReactionCalled)
    }

    func testToggleReactionRemoves() async {
        let posts = [makeFeedPost(
            id: "1", userName: "Alice", workoutName: "Push Day",
            reactions: [FeedReaction(emoji: "heart", count: 1)],
            userReactions: ["heart"]
        )]
        mockAPI.fetchSocialFeedResult = .success(
            FeedResponse(posts: posts, nextCursor: nil, hasMore: false)
        )
        await sut.loadFeed()

        await sut.toggleReaction(postId: "1", emoji: "heart")

        XCTAssertFalse(sut.posts[0].userReactions.contains("heart"))
        XCTAssertTrue(mockAPI.removeSocialReactionCalled)
    }

    // MARK: - Comments

    func testLoadComments() async {
        let posts = [makeFeedPost(id: "1", userName: "Alice", workoutName: "Push Day")]
        mockAPI.fetchSocialFeedResult = .success(
            FeedResponse(posts: posts, nextCursor: nil, hasMore: false)
        )
        await sut.loadFeed()

        await sut.loadComments(postId: "1")

        XCTAssertEqual(sut.selectedPostId, "1")
        XCTAssertTrue(mockAPI.fetchSocialCommentsCalled)
        XCTAssertFalse(sut.isLoadingComments)
    }

    func testPostComment() async {
        let posts = [makeFeedPost(id: "1", userName: "Alice", workoutName: "Push Day")]
        mockAPI.fetchSocialFeedResult = .success(
            FeedResponse(posts: posts, nextCursor: nil, hasMore: false)
        )
        await sut.loadFeed()

        sut.selectedPostId = "1"
        sut.commentText = "Great workout!"
        await sut.postComment()

        XCTAssertTrue(mockAPI.postSocialCommentCalled)
        XCTAssertEqual(sut.commentText, "") // cleared after posting
        XCTAssertFalse(sut.isPostingComment)
    }

    func testPostEmptyCommentDoesNothing() async {
        sut.selectedPostId = "1"
        sut.commentText = "   "
        await sut.postComment()

        XCTAssertFalse(mockAPI.postSocialCommentCalled)
    }

    // MARK: - Helpers

    private func makeFeedPost(
        id: String,
        userName: String,
        workoutName: String,
        reactions: [FeedReaction] = [],
        userReactions: [String] = []
    ) -> FeedPost {
        FeedPost(
            id: id,
            userId: "user-\(id)",
            userName: userName,
            userAvatarUrl: nil,
            postedAt: Date(),
            workoutName: workoutName,
            exercises: [FeedExercise(name: "Bench Press", sets: 3, reps: 10, weight: 80)],
            totalVolume: 2400,
            durationSeconds: 3600,
            personalRecords: [],
            photoUrl: nil,
            reactions: reactions,
            commentCount: 0,
            userReactions: userReactions
        )
    }
}
