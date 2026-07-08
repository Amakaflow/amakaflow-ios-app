//
//  SocialAPIRepositoryTests.swift
//  AmakaFlowCompanionTests
//
//  Contract tests for SocialAPIRepository endpoints (issue #432).
//  Uses MockURLProtocol via APIService session transport path.
//  Covers path, method, query params, response decoding, and
//  APIError mapping (401, 500).
//
//  Endpoints covered:
//    GET    /social/feed                              (fetchSocialFeed)
//    GET    /social/settings                          (fetchSocialSettings)
//    POST   /social/users/{id}/follow                 (followUser)
//    POST   /social/users/{id}/unfollow               (unfollowUser)
//    GET    /social/challenges                        (fetchChallenges)
//    GET    /social/crews                             (fetchMyCrews)
//    GET    /social/leaderboards/friends              (fetchFriendsLeaderboard)
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - fetchSocialFeed

@MainActor
final class FetchSocialFeedTests: XCTestCase {
    private var api: APIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        api = APIService(session: MockURLProtocol.mockSession())
    }

    override func tearDown() {
        api = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchSocialFeedHitsMapperAPIWithGETAndLimitParam() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/social/feed",
                           "fetchSocialFeed must GET /social/feed")
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertNotNil(
                comps?.queryItems?.first(where: { $0.name == "limit" }),
                "fetchSocialFeed must include 'limit' query param"
            )
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = """
            {
              "posts": [],
              "next_cursor": null,
              "has_more": false
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.fetchSocialFeed(cursor: nil, limit: 20)

        XCTAssertTrue(result.posts.isEmpty)
        XCTAssertFalse(result.hasMore)
    }

    func testFetchSocialFeedWithCursorIncludesCursorParam() async throws {
        MockURLProtocol.requestHandler = { request in
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertNotNil(
                comps?.queryItems?.first(where: { $0.name == "cursor" }),
                "fetchSocialFeed with cursor must include 'cursor' query param"
            )
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = #"{"posts":[],"next_cursor":null,"has_more":false}"#.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.fetchSocialFeed(cursor: "cursor-xyz", limit: 10)

        XCTAssertTrue(result.posts.isEmpty)
    }

    func testFetchSocialFeed500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchSocialFeed(cursor: nil, limit: 20)
            XCTFail("Expected server error")
        } catch APIError.serverError {
            // expected — SocialAPIRepository uses legacy .serverError(Int)
        } catch {
            XCTFail("Expected .serverError, got \(error)")
        }
    }
}

// MARK: - fetchSocialSettings

@MainActor
final class FetchSocialSettingsTests: XCTestCase {
    private var api: APIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        api = APIService(session: MockURLProtocol.mockSession())
    }

    override func tearDown() {
        api = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchSocialSettingsHitsMapperAPIWithGETAndDecodesSettings() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/social/settings",
                           "fetchSocialSettings must GET /social/settings")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            // makeDecoder() uses convertFromSnakeCase: use snake_case keys.
            let data = """
            {
              "discoverable": true,
              "share_workouts": false,
              "hide_weights": true
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let settings = try await api.fetchSocialSettings()

        XCTAssertTrue(settings.discoverable)
        XCTAssertFalse(settings.shareWorkouts)
        XCTAssertTrue(settings.hideWeights)
    }

    func testFetchSocialSettings500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchSocialSettings()
            XCTFail("Expected server error")
        } catch APIError.serverError {
            // expected
        } catch {
            XCTFail("Expected .serverError, got \(error)")
        }
    }
}

// MARK: - followUser / unfollowUser

@MainActor
final class FollowUserTests: XCTestCase {
    private var api: APIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        api = APIService(session: MockURLProtocol.mockSession())
    }

    override func tearDown() {
        api = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFollowUserHitsMapperAPIWithPOSTAndUserId() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/social/users/user-42/follow",
                           "followUser must POST to /social/users/{id}/follow")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        try await api.followUser(userId: "user-42")
    }

    func testFollowUser401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.followUser(userId: "user-42")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testUnfollowUserHitsMapperAPIWithPOSTAndUserId() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/social/users/user-42/unfollow",
                           "unfollowUser must POST to /social/users/{id}/unfollow")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        try await api.unfollowUser(userId: "user-42")
    }

    func testFollowUser500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.followUser(userId: "user-42")
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - fetchChallenges

@MainActor
final class FetchChallengesTests: XCTestCase {
    private var api: APIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        api = APIService(session: MockURLProtocol.mockSession())
    }

    override func tearDown() {
        api = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchChallengesHitsMapperAPIWithGETAndDecodesEmptyList() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/social/challenges",
                           "fetchChallenges must GET /social/challenges")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = #"{"challenges":[],"total":0}"#.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.fetchChallenges()

        XCTAssertTrue(result.challenges.isEmpty)
    }

    func testFetchChallenges500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchChallenges()
            XCTFail("Expected server error")
        } catch APIError.serverError {
            // expected
        } catch {
            XCTFail("Expected .serverError, got \(error)")
        }
    }
}

// MARK: - fetchMyCrews

@MainActor
final class FetchMyCrewsTests: XCTestCase {
    private var api: APIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        api = APIService(session: MockURLProtocol.mockSession())
    }

    override func tearDown() {
        api = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchMyCrewsHitsMapperAPISocialCrewsWithGET() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/social/crews",
                           "fetchMyCrews must GET /social/crews")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = #"{"crews":[],"count":0}"#.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.fetchMyCrews()

        XCTAssertTrue(result.crews.isEmpty)
    }
}

// MARK: - fetchFriendsLeaderboard

@MainActor
final class FetchFriendsLeaderboardTests: XCTestCase {
    private var api: APIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        api = APIService(session: MockURLProtocol.mockSession())
    }

    override func tearDown() {
        api = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchFriendsLeaderboardHitsMapperAPIWithGETAndDimensionPeriodParams() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/social/leaderboards/friends",
                           "fetchFriendsLeaderboard must GET /social/leaderboards/friends")
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(
                comps?.queryItems?.first(where: { $0.name == "dimension" })?.value,
                "volume"
            )
            XCTAssertEqual(
                comps?.queryItems?.first(where: { $0.name == "period" })?.value,
                "week"
            )
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = #"{"entries":[],"period":"week","dimension":"volume"}"#.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.fetchFriendsLeaderboard(dimension: "volume", period: "week")

        XCTAssertTrue(result.entries.isEmpty)
    }

    func testFetchFriendsLeaderboard500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchFriendsLeaderboard(dimension: "volume", period: "week")
            XCTFail("Expected server error")
        } catch APIError.serverError {
            // expected
        } catch {
            XCTFail("Expected .serverError, got \(error)")
        }
    }
}
