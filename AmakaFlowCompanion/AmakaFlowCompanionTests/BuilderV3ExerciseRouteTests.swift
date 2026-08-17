//
//  BuilderV3ExerciseRouteTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2449 — exercise routes live on mobile-bff, not mapper-api.
//

import XCTest
@testable import AmakaFlowCompanion

/// Captures the request the client actually emits.
///
/// The point of these tests is the URL the client builds, so asserting on a
/// separately composed string would pass even if the call site stopped passing
/// `baseURL:` — which is exactly the regression that shipped.
private final class RecordingURLSession: APIURLSession {
    private(set) var requests: [URLRequest] = []
    var status = 200
    var body = Data(#"{"results":[],"exercises":[],"count":0}"#.utf8)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }

    var lastURL: URL? { requests.last?.url }
}

final class BuilderV3ExerciseRouteTests: XCTestCase {

    private func makeClient(
        _ session: RecordingURLSession
    ) -> BuilderV3ExerciseSearchClient {
        BuilderV3ExerciseSearchClient(
            apiService: APIService(session: session),
            useFixtures: false
        )
    }

    // MARK: - The bug: the request went to the wrong host

    /// Exercises the client's own request builder, so removing
    /// `baseURL: apiService.bffURL` from it fails here. Explicit headers skip
    /// the auth round trip; the URL under test is unaffected by them.
    private func searchURL() async throws -> URL {
        let request = try await BuilderV3ExerciseSearchClient(useFixtures: false)
            .makeSearchRequest(query: "bench", limit: 30, headers: [:])
        return try XCTUnwrap(request.url, "search request had no URL")
    }

    private func listURL() async throws -> URL {
        let request = try await BuilderV3ExerciseSearchClient(useFixtures: false)
            .makeListRequest(
                queryItems: [URLQueryItem(name: "category", value: "strength")],
                headers: [:]
            )
        return try XCTUnwrap(request.url, "list request had no URL")
    }

    func testSearchRequestsTheBFFHostNotMapperAPI() async throws {
        let url = try await searchURL()
        XCTAssertEqual(
            url.path,
            "/v1/exercises/search",
            "search must call the BFF's /v1/exercises/search route"
        )
        XCTAssertTrue(
            url.absoluteString.hasPrefix(AppEnvironment.current.mobileBFFURL),
            "search must target mobile-bff; mapper-api 404s on this route (AMA-2449)"
        )
        XCTAssertFalse(
            url.absoluteString.hasPrefix(AppEnvironment.current.mapperAPIURL),
            "search fell back to the default mapper-api base — the AMA-2449 regression"
        )
    }

    func testCategoryBrowseRequestsTheBFFHostNotMapperAPI() async throws {
        let url = try await listURL()
        XCTAssertEqual(
            url.path,
            "/v1/exercises",
            "category browse must call the BFF's /v1/exercises route"
        )
        XCTAssertTrue(
            url.absoluteString.hasPrefix(AppEnvironment.current.mobileBFFURL),
            "browse must target mobile-bff; mapper-api 404s on this route (AMA-2449)"
        )
        XCTAssertFalse(
            url.absoluteString.hasPrefix(AppEnvironment.current.mapperAPIURL),
            "browse fell back to the default mapper-api base — the AMA-2449 regression"
        )
    }

    /// `bffURL` already carries `/v1`; a path repeating it would 404 exactly
    /// like the wrong host did, so assert the emitted URL has it exactly once.
    func testEmittedPathsCarryTheVersionPrefixExactlyOnce() async throws {
        for url in try await [searchURL(), listURL()] {
            XCTAssertFalse(
                url.path.contains("/v1/v1"),
                "\(url.path) repeated the /v1 the BFF base already carries"
            )
            XCTAssertTrue(url.path.hasPrefix("/v1/"), "BFF routes are mounted under /v1")
        }
    }

    func testSearchSendsTheQueryItWasGiven() async throws {
        let query = try await searchURL().query ?? ""
        XCTAssertTrue(query.contains("q=bench"), "search must send its query, got: \(query)")
    }

    // MARK: - A missing route must not read as a bad network

    func testA404ClassifiesAsARouteMistake() {
        XCTAssertEqual(
            BuilderV3ExerciseFetchResult.classify(APIError.notFound),
            .routeMissing,
            "a 404 means the route is wrong — a wiring bug, not a network condition"
        )
    }

    func testTransientFailuresDoNotClassifyAsARouteMistake() {
        XCTAssertEqual(
            BuilderV3ExerciseFetchResult.classify(APIError.server(status: 503)),
            .requestFailed,
            "a 5xx is the server struggling, not a missing route"
        )
        XCTAssertEqual(
            BuilderV3ExerciseFetchResult.classify(APIError.network(underlying: URLError(.timedOut))),
            .requestFailed,
            "a timeout is transient and must not trip the route-missing trap"
        )
        XCTAssertEqual(
            BuilderV3ExerciseFetchResult.classify(APIError.decoding(underlying: URLError(.cannotParseResponse))),
            .requestFailed,
            "a bad payload is a contract problem, but the route itself resolved"
        )
    }

    func testTransientFailureStillServesFixturesSoTheSheetIsNotEmpty() {
        let result = BuilderV3ExerciseFetchResult.fallback(
            items: BuilderV3ExerciseSearchClient.fixtureResults(matching: "bench"),
            error: APIError.network(underlying: URLError(.notConnectedToInternet)),
            endpoint: BuilderV3ExerciseSearchClient.searchPath
        )
        XCTAssertEqual(result.mode, .mock, "an offline fetch must be reported as mock, not live")
        XCTAssertEqual(result.fallbackReason, .requestFailed, "offline is transient, not a route bug")
        XCTAssertFalse(result.items.isEmpty, "offline should still offer fixtures to browse")
    }

    // MARK: - Deliberate fixture use is not a failure

    func testUITestFixturesAreNotReportedAsAFailure() async {
        let client = BuilderV3ExerciseSearchClient(useFixtures: true)
        let result = await client.search(query: "bench")
        XCTAssertEqual(
            result.fallbackReason,
            .fixturesRequested,
            "fixtures asked for by UI tests must not look like a network failure"
        )
    }

    func testEmptyQueryIsNotReportedAsAFailure() async {
        let session = RecordingURLSession()
        let result = await makeClient(session).search(query: "   ")
        XCTAssertEqual(
            result.fallbackReason,
            .noQuery,
            "an empty query has nothing to ask the server, which is not a failure"
        )
        XCTAssertTrue(session.requests.isEmpty, "an empty query must not hit the network at all")
    }
}
