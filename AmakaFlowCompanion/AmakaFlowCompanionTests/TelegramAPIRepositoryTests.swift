//
//  TelegramAPIRepositoryTests.swift
//  AmakaFlowCompanionTests
//
//  Contract tests for TelegramAPIRepository endpoints (issue #432).
//  Uses MockURLProtocol via APIService.request() transport path.
//  Covers path, method, response decoding, and APIError mapping.
//
//  Endpoints covered:
//    POST /v1/messaging/telegram/setup        (mintTelegramLinkToken)
//    GET  /v1/messaging/telegram/status?token= (getTelegramLinkStatus)
//
//  These endpoints use self.request() so non-2xx errors map to:
//    401 → .unauthorized
//    500 empty body → .server(status: 500)
//    404 → .notFound
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - mintTelegramLinkToken

@MainActor
final class MintTelegramLinkTokenTests: XCTestCase {
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

    func testMintTelegramLinkTokenHitsBFFTelegramSetupWithPOSTAndDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/messaging/telegram/setup",
                           "mintTelegramLinkToken must POST to BFF /v1/messaging/telegram/setup")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            // Generated decoder uses camelCase keys (no convertFromSnakeCase).
            let data = """
            {
              "token": "tok-abc123",
              "deepLink": "https://t.me/amakabot?start=tok-abc123",
              "nativeLink": "tg://resolve?domain=amakabot&start=tok-abc123",
              "expiresInSeconds": 300
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.mintTelegramLinkToken()

        XCTAssertEqual(result.token, "tok-abc123")
        XCTAssertEqual(result.expiresInSeconds, 300)
        XCTAssert(result.deepLink.contains("amakabot"))
    }

    func testMintTelegramLinkToken401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.mintTelegramLinkToken()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testMintTelegramLinkToken500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.mintTelegramLinkToken()
            XCTFail("Expected server error")
        } catch APIError.server(status: 500) {
            // expected: request() uses the modern .server(status:) case
        } catch {
            XCTFail("Expected .server(status: 500), got \(error)")
        }
    }
}

// MARK: - getTelegramLinkStatus

@MainActor
final class GetTelegramLinkStatusTests: XCTestCase {
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

    func testGetTelegramLinkStatusHitsBFFTelegramStatusWithGETAndToken() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/messaging/telegram/status",
                           "getTelegramLinkStatus must GET BFF /v1/messaging/telegram/status")
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(
                comps?.queryItems?.first(where: { $0.name == "token" })?.value,
                "tok-abc123",
                "getTelegramLinkStatus must send 'token' query param"
            )
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            // Generated decoder uses camelCase keys.
            let data = """
            {
              "linked": true,
              "telegramIdHash": "hash-xyz"
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.getTelegramLinkStatus(token: "tok-abc123")

        XCTAssertTrue(result.linked)
        XCTAssertEqual(result.telegramIdHash, "hash-xyz")
    }

    func testGetTelegramLinkStatusLinkedFalseWhenNotYetLinked() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = """
            {
              "linked": false
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.getTelegramLinkStatus(token: "tok-pending")

        XCTAssertFalse(result.linked)
        XCTAssertNil(result.telegramIdHash)
    }

    func testGetTelegramLinkStatus401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.getTelegramLinkStatus(token: "tok-abc123")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testGetTelegramLinkStatus404MapsToNotFound() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.getTelegramLinkStatus(token: "tok-expired")
            XCTFail("Expected .notFound")
        } catch APIError.notFound {
            // expected: request() maps 404 → .notFound
        } catch {
            XCTFail("Expected .notFound, got \(error)")
        }
    }

    func testGetTelegramLinkStatus500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.getTelegramLinkStatus(token: "tok-abc123")
            XCTFail("Expected server error")
        } catch APIError.server(status: 500) {
            // expected
        } catch {
            XCTFail("Expected .server(status: 500), got \(error)")
        }
    }
}
