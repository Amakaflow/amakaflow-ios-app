//
//  BuilderV3ExerciseRouteTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2449 — exercise routes live on mobile-bff, not mapper-api.
//

import XCTest
@testable import AmakaFlowCompanion

final class BuilderV3ExerciseRouteTests: XCTestCase {

    private var api: APIService { APIService.shared }

    // MARK: - The bug: requests went to the default host

    /// The whole defect in one assertion. `makeAPIRequest` defaults to
    /// `APIService.baseURL` (mapper-api), which 404s on every exercise route.
    func testExerciseRoutesDoNotResolveAgainstTheDefaultMapperHost() {
        let mapper = AppEnvironment.current.mapperAPIURL
        for path in [BuilderV3ExerciseSearchClient.searchPath,
                     BuilderV3ExerciseSearchClient.listPath] {
            XCTAssertFalse(
                (api.bffURL + path).hasPrefix(mapper),
                "\(path) resolved against mapper-api, which 404s on it"
            )
        }
    }

    func testExerciseRoutesResolveAgainstTheBFFHost() {
        let bff = AppEnvironment.current.mobileBFFURL
        XCTAssertTrue((api.bffURL + BuilderV3ExerciseSearchClient.searchPath).hasPrefix(bff))
        XCTAssertTrue((api.bffURL + BuilderV3ExerciseSearchClient.listPath).hasPrefix(bff))
    }

    /// `bffURL` already carries `/v1`, so the paths must not repeat it —
    /// a doubled prefix would 404 exactly like the wrong host did.
    func testPathsDoNotRepeatTheVersionPrefixTheBFFBaseAlreadyCarries() {
        XCTAssertTrue(api.bffURL.hasSuffix("/v1"))
        XCTAssertFalse(BuilderV3ExerciseSearchClient.searchPath.hasPrefix("/v1"))
        XCTAssertFalse(BuilderV3ExerciseSearchClient.listPath.hasPrefix("/v1"))
    }

    func testComposedURLsMatchTheRoutesServedByTheBFF() {
        let bff = AppEnvironment.current.mobileBFFURL
        XCTAssertEqual(
            api.bffURL + BuilderV3ExerciseSearchClient.searchPath,
            "\(bff)/v1/exercises/search"
        )
        XCTAssertEqual(
            api.bffURL + BuilderV3ExerciseSearchClient.listPath,
            "\(bff)/v1/exercises"
        )
    }

    // MARK: - A missing route must not read as a bad network

    func testA404IsClassifiedAsARouteMistakeNotATransientFailure() {
        // assertionFailure traps a 404 in debug by design, so classify directly.
        XCTAssertEqual(APIError.coerce(APIError.notFound).category, .notFound)
        XCTAssertNotEqual(APIError.coerce(APIError.server(status: 503)).category, .notFound)
        XCTAssertNotEqual(
            APIError.coerce(APIError.network(underlying: URLError(.timedOut))).category,
            .notFound
        )
    }

    func testTransientFailuresStillFallBackToFixturesWithoutTrapping() {
        let result = BuilderV3ExerciseFetchResult.fallback(
            items: BuilderV3ExerciseSearchClient.fixtureResults(matching: "bench"),
            error: APIError.network(underlying: URLError(.notConnectedToInternet)),
            endpoint: BuilderV3ExerciseSearchClient.searchPath
        )
        XCTAssertEqual(result.mode, .mock)
        XCTAssertEqual(result.fallbackReason, .requestFailed)
        XCTAssertFalse(result.items.isEmpty, "offline should still offer fixtures")
    }

    /// Deliberate fixture paths are not failures and must not be reported as such.
    func testDeliberateFixtureUseIsNotReportedAsAFailure() async {
        let client = BuilderV3ExerciseSearchClient(useFixtures: true)
        let requested = await client.search(query: "bench")
        XCTAssertEqual(requested.fallbackReason, .fixturesRequested)

        let empty = await client.search(query: "   ")
        XCTAssertEqual(empty.fallbackReason, .noQuery)
    }
}
