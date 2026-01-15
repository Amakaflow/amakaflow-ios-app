//
//  MockURLProtocol.swift
//  AmakaFlowCompanionTests
//
//  Custom URLProtocol for intercepting and stubbing network requests in tests.
//  Allows tests to verify API calls and return controlled responses.
//
//  Part of AMA-349: Test Infrastructure
//

import Foundation

/// URLProtocol subclass for intercepting and mocking network requests in tests.
///
/// Usage:
/// ```swift
/// // Configure mock response
/// MockURLProtocol.requestHandler = { request in
///     let response = HTTPURLResponse(
///         url: request.url!,
///         statusCode: 200,
///         httpVersion: nil,
///         headerFields: nil
///     )!
///     let data = try! JSONEncoder().encode(["success": true])
///     return (response, data)
/// }
///
/// // Create URLSession with mock protocol
/// let config = URLSessionConfiguration.ephemeral
/// config.protocolClasses = [MockURLProtocol.self]
/// let session = URLSession(configuration: config)
///
/// // Use session in tests - requests will be intercepted
/// ```
final class MockURLProtocol: URLProtocol {
    // MARK: - Static Configuration

    /// Handler to process intercepted requests and return mock responses.
    /// Must be set before making requests.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Track all requests that were intercepted (for assertions)
    static var interceptedRequests: [URLRequest] = []

    /// Error to simulate network failures
    static var simulatedError: Error?

    /// Delay before returning response (simulates network latency)
    static var responseDelay: TimeInterval = 0

    // MARK: - URLProtocol Implementation

    override class func canInit(with request: URLRequest) -> Bool {
        // Intercept all requests when this protocol is registered
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        // Track this request for test assertions
        MockURLProtocol.interceptedRequests.append(request)

        // Simulate error if configured
        if let error = MockURLProtocol.simulatedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        // Require handler to be set
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("""
                MockURLProtocol.requestHandler must be set before making requests.
                Set it in your test setup or before the code under test executes.
                """)
        }

        do {
            let (response, data) = try handler(request)

            // Apply response delay if configured
            if MockURLProtocol.responseDelay > 0 {
                Thread.sleep(forTimeInterval: MockURLProtocol.responseDelay)
            }

            // Return the mock response
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No cleanup needed for mock protocol
    }

    // MARK: - Test Helpers

    /// Reset all static state between tests
    static func reset() {
        requestHandler = nil
        interceptedRequests = []
        simulatedError = nil
        responseDelay = 0
    }

    /// Create a URLSession configured to use this mock protocol
    static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Configure a simple JSON response handler
    /// - Parameters:
    ///   - statusCode: HTTP status code (default 200)
    ///   - data: Response data to return
    static func setResponse(statusCode: Int = 200, data: Data) {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mock.test")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
    }

    /// Configure a JSON encodable response
    /// - Parameters:
    ///   - statusCode: HTTP status code (default 200)
    ///   - body: Encodable object to return as JSON
    static func setJSONResponse<T: Encodable>(statusCode: Int = 200, body: T) throws {
        let data = try JSONEncoder().encode(body)
        setResponse(statusCode: statusCode, data: data)
    }

    /// Configure an error response
    /// - Parameter error: Error to return
    static func setError(_ error: Error) {
        simulatedError = error
    }
}

// MARK: - Common Test Errors

/// Errors for simulating network failures in tests
enum MockNetworkError: Error, LocalizedError {
    case noConnection
    case timeout
    case serverError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "The network connection was lost."
        case .timeout:
            return "The request timed out."
        case .serverError:
            return "The server returned an error."
        case .invalidResponse:
            return "The server returned an invalid response."
        }
    }
}
