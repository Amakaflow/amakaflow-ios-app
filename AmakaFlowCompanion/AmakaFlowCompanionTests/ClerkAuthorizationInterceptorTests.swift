import XCTest
@testable import AmakaFlowCompanion

// MARK: - ClerkAuthorizationInterceptor 401→refresh→retry-once tests (issue #430)

final class ClerkAuthorizationInterceptorTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = MockURLProtocol.mockSession()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    // MARK: - Happy path: first request succeeds

    func test200OnFirstRequestSkipsRefresh() async throws {
        let provider = MockClerkBearerTokenProvider(initialToken: "valid-token")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        let req = URLRequest(url: URL(string: "https://api.test/resource")!)
        let (_, http) = try await ClerkAuthorizationInterceptor.perform(
            req, tokenProvider: provider, session: session)

        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(provider.refreshCallCount, 0, "No refresh should occur on a 200 response")
        XCTAssertEqual(MockURLProtocol.interceptedRequests.count, 1)
        XCTAssertEqual(
            MockURLProtocol.interceptedRequests[0].value(forHTTPHeaderField: "Authorization"),
            "Bearer valid-token"
        )
    }

    // MARK: - Core acceptance: 401 → single refresh → retry succeeds

    func test401TriggersOneRefreshAndRetry() async throws {
        let provider = MockClerkBearerTokenProvider(
            initialToken: "initial-token",
            refreshResult: .success("refreshed-token")
        )

        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            let statusCode = callCount == 1 ? 401 : 200
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        let req = URLRequest(url: URL(string: "https://api.test/resource")!)
        let (_, http) = try await ClerkAuthorizationInterceptor.perform(
            req, tokenProvider: provider, session: session)

        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(provider.refreshCallCount, 1, "Exactly one refresh on 401")
        XCTAssertEqual(MockURLProtocol.interceptedRequests.count, 2, "Initial request + one retry")
        XCTAssertEqual(
            MockURLProtocol.interceptedRequests[0].value(forHTTPHeaderField: "Authorization"),
            "Bearer initial-token",
            "First request must carry the initial token"
        )
        XCTAssertEqual(
            MockURLProtocol.interceptedRequests[1].value(forHTTPHeaderField: "Authorization"),
            "Bearer refreshed-token",
            "Retry must carry the freshly-refreshed token"
        )
    }

    // MARK: - No infinite loop: 401 on retry throws .unauthorized exactly once

    func test401OnRetryThrowsUnauthorizedWithNoFurtherAttempts() async throws {
        let provider = MockClerkBearerTokenProvider(
            initialToken: "initial-token",
            refreshResult: .success("refreshed-token")
        )
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        let req = URLRequest(url: URL(string: "https://api.test/resource")!)
        do {
            _ = try await ClerkAuthorizationInterceptor.perform(
                req, tokenProvider: provider, session: session)
            XCTFail("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            XCTAssertEqual(
                provider.refreshCallCount, 1,
                "Refresh must be attempted exactly once — no retry loop"
            )
            XCTAssertEqual(
                MockURLProtocol.interceptedRequests.count, 2,
                "Exactly two network calls: initial + one retry, then bail"
            )
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    // MARK: - Refresh failure propagates without a second network call

    func test401WhenRefreshThrowsPropagatesError() async throws {
        let provider = MockClerkBearerTokenProvider(
            initialToken: "initial-token",
            refreshResult: .failure(TestInterceptorError.refreshFailed)
        )
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        let req = URLRequest(url: URL(string: "https://api.test/resource")!)
        do {
            _ = try await ClerkAuthorizationInterceptor.perform(
                req, tokenProvider: provider, session: session)
            XCTFail("Expected refresh error")
        } catch TestInterceptorError.refreshFailed {
            XCTAssertEqual(
                MockURLProtocol.interceptedRequests.count, 1,
                "No retry request when refresh itself throws"
            )
        } catch {
            XCTFail("Expected .refreshFailed, got \(error)")
        }
    }
}

// MARK: - Test doubles

private enum TestInterceptorError: Error, Equatable {
    case refreshFailed
}

private final class MockClerkBearerTokenProvider: ClerkBearerTokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let initialToken: String
    private let refreshResult: Result<String, Error>?
    private var _refreshCallCount = 0

    var refreshCallCount: Int { lock.withLock { _refreshCallCount } }

    init(
        initialToken: String,
        refreshResult: Result<String, Error>? = nil
    ) {
        self.initialToken = initialToken
        self.refreshResult = refreshResult
    }

    func bearerToken() async throws -> String { initialToken }

    func refreshAfterUnauthorized() async throws -> String {
        lock.withLock { _refreshCallCount += 1 }
        switch refreshResult {
        case .success(let token):
            return token
        case .failure(let error):
            throw error
        case nil:
            throw TestInterceptorError.refreshFailed
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
