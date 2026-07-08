//
//  DeviceAPIRepositoryTests.swift
//  AmakaFlowCompanionTests
//
//  Contract tests for DeviceAPIRepository endpoints (issue #432).
//  Uses MockURLProtocol via APIService session transport path.
//  Covers path, method, response decoding, and APIError mapping
//  (401, 500).
//
//  Endpoints covered:
//    POST   /api/watch-delivery/resend
//    POST   /mobile/devices/register-push-token
//    GET    /mobile/profile
//    GET    /api/privacy/export
//    DELETE /account
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - resendWatchDelivery

@MainActor
final class ResendWatchDeliveryTests: XCTestCase {
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

    func testResendWatchDeliveryHitsMapperAPIWithPOST() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/watch-delivery/resend",
                           "resendWatchDelivery must POST to /api/watch-delivery/resend")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        try await api.resendWatchDelivery()
    }

    func testResendWatchDelivery401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.resendWatchDelivery()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testResendWatchDelivery500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.resendWatchDelivery()
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - fetchProfile

@MainActor
final class FetchProfileTests: XCTestCase {
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

    func testFetchProfileHitsMapperAPIWithGETAndDecodesUserProfile() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/mobile/profile",
                           "fetchProfile must GET /mobile/profile")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = """
            {
              "success": true,
              "profile": {
                "id": "user-123",
                "email": "test@example.com",
                "name": "Test User",
                "avatar_url": null
              }
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let profile = try await api.fetchProfile()

        XCTAssertEqual(profile.id, "user-123")
        XCTAssertEqual(profile.email, "test@example.com")
        XCTAssertEqual(profile.name, "Test User")
    }

    func testFetchProfile401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchProfile()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testFetchProfile500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchProfile()
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - registerPushToken

@MainActor
final class RegisterPushTokenTests: XCTestCase {
    private var api: APIService!
    private var savedIsPaired: Bool!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        api = APIService(session: MockURLProtocol.mockSession())
        savedIsPaired = PairingService.shared.isPaired
        PairingService.shared.isPaired = true
    }

    override func tearDown() {
        PairingService.shared.isPaired = savedIsPaired
        api = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testRegisterPushTokenHitsMapperAPIWithPOSTAndBody() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/mobile/devices/register-push-token",
                           "registerPushToken must POST to /mobile/devices/register-push-token")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        try await api.registerPushToken(apnsToken: "abc123", deviceId: "device-001")
    }

    func testRegisterPushTokenUnpairedThrowsUnauthorized() async throws {
        PairingService.shared.isPaired = false

        do {
            try await api.registerPushToken(apnsToken: "abc123", deviceId: "device-001")
            XCTFail("Expected .unauthorized for unpaired state")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testRegisterPushToken401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.registerPushToken(apnsToken: "abc123", deviceId: "device-001")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testRegisterPushToken500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.registerPushToken(apnsToken: "abc123", deviceId: "device-001")
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - exportUserData

@MainActor
final class ExportUserDataTests: XCTestCase {
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

    func testExportUserDataHitsMapperAPIPrivacyExportWithGET() async throws {
        let exportPayload = #"{"user_id":"u1","workouts":[]}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/privacy/export",
                           "exportUserData must GET /api/privacy/export")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, exportPayload)
        }

        let data = try await api.exportUserData()

        XCTAssertEqual(data, exportPayload)
    }

    func testExportUserData401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.exportUserData()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }
}

// MARK: - deleteAccount

@MainActor
final class DeleteAccountTests: XCTestCase {
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

    func testDeleteAccountHitsMapperAPIAccountWithDELETE() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/account",
                           "deleteAccount must DELETE /account")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        try await api.deleteAccount()
    }

    func testDeleteAccount401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.deleteAccount()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testDeleteAccount500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.deleteAccount()
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}
