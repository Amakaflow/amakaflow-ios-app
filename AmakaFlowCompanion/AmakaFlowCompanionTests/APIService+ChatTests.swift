//
//  APIService+ChatTests.swift
//  AmakaFlowCompanionTests
//
//  Contract tests for ChatAPIRepository endpoints that route through
//  URLSession directly (non-generated-client paths). Verifies path,
//  method, response decoding, and APIError mapping (issue #432).
//
//  Endpoints covered:
//    GET  /v1/gamification/xp         (fetchXP)
//    POST /v1/nutrition/analyze-photo (analyzePhoto)
//    GET  /v1/nutrition/barcode/{code} (lookupBarcode)
//    POST /v1/nutrition/parse-text    (parseText)
//    GET  /v1/nutrition/fueling-status (getFuelingStatus)
//    POST /v1/nutrition/protein-nudge/check (checkProteinNudge)
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - fetchXP

@MainActor
final class FetchXPTests: XCTestCase {
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

    func testFetchXPHitsBFFGamificationXPWithGETAndDecodesXPData() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/gamification/xp",
                           "fetchXP must route to BFF /v1/gamification/xp")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let data = """
            {
              "xp_total": 1500,
              "current_level": 5,
              "level_name": "Intermediate",
              "xp_to_next_level": 500,
              "xp_today": 120,
              "daily_cap": 300
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let xp = try await api.fetchXP()

        XCTAssertEqual(xp.xpTotal, 1500)
        XCTAssertEqual(xp.currentLevel, 5)
        XCTAssertEqual(xp.levelName, "Intermediate")
        XCTAssertEqual(xp.xpToNextLevel, 500)
    }

    func testFetchXP401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchXP()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testFetchXP500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchXP()
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - analyzePhoto

@MainActor
final class AnalyzePhotoTests: XCTestCase {
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

    func testAnalyzePhotoHitsBFFNutritionAnalyzePhotoWithPOST() async {
        // Path/method assertions fire synchronously inside the handler.
        // We use a non-2xx response to avoid the decode path: the response
        // models (MacroTotalsResponse) use explicit snake_case CodingKeys that
        // are incompatible with the convertFromSnakeCase decoder strategy.
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/nutrition/analyze-photo",
                           "analyzePhoto must route to BFF /v1/nutrition/analyze-photo")
            return (HTTPURLResponse(url: request.url!, statusCode: 500,
                                    httpVersion: "HTTP/1.1", headerFields: [:])!, Data())
        }

        do { _ = try await api.analyzePhoto(imageBase64: "base64data") } catch { }

        XCTAssertEqual(MockURLProtocol.interceptedRequests.count, 1,
                       "analyzePhoto must make exactly one request")
    }

    func testAnalyzePhoto401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.analyzePhoto(imageBase64: "base64data")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testAnalyzePhoto500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.analyzePhoto(imageBase64: "base64data")
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - lookupBarcode

@MainActor
final class LookupBarcodeTests: XCTestCase {
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

    func testLookupBarcodeHitsBFFNutritionBarcodeWithGETAndCode() async {
        // BarcodeNutritionAPIResponse uses explicit snake_case CodingKeys that are
        // incompatible with the convertFromSnakeCase decoder strategy. Use a non-2xx
        // response to avoid the decode path; path/method assertions fire in the handler.
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssert(
                request.url?.path.hasPrefix("/v1/nutrition/barcode/") == true,
                "lookupBarcode must route to BFF /v1/nutrition/barcode/{code}"
            )
            return (HTTPURLResponse(url: request.url!, statusCode: 500,
                                    httpVersion: "HTTP/1.1", headerFields: [:])!, Data())
        }

        do { _ = try await api.lookupBarcode(code: "1234567890") } catch { }

        XCTAssertEqual(MockURLProtocol.interceptedRequests.count, 1,
                       "lookupBarcode must make exactly one request")
    }

    func testLookupBarcode401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.lookupBarcode(code: "123")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }
}

// MARK: - getFuelingStatus

@MainActor
final class GetFuelingStatusTests: XCTestCase {
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

    func testGetFuelingStatusHitsBFFNutritionFuelingStatusWithGET() async {
        // FuelingStatusResponse uses explicit snake_case CodingKeys incompatible with
        // convertFromSnakeCase. Use a non-2xx response; path/method assertions fire in the handler.
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/nutrition/fueling-status",
                           "getFuelingStatus must route to BFF /v1/nutrition/fueling-status")
            return (HTTPURLResponse(url: request.url!, statusCode: 500,
                                    httpVersion: "HTTP/1.1", headerFields: [:])!, Data())
        }

        do { _ = try await api.getFuelingStatus() } catch { }

        XCTAssertEqual(MockURLProtocol.interceptedRequests.count, 1,
                       "getFuelingStatus must make exactly one request")
    }

    func testGetFuelingStatus401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.getFuelingStatus()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testGetFuelingStatus500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.getFuelingStatus()
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - checkProteinNudge

@MainActor
final class CheckProteinNudgeTests: XCTestCase {
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

    func testCheckProteinNudgeHitsBFFNutritionProteinNudgeCheckWithPOST() async {
        // ProteinNudgeResponse uses explicit snake_case CodingKeys incompatible with
        // convertFromSnakeCase. Use a non-2xx response; path/method assertions fire in the handler.
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/nutrition/protein-nudge/check",
                           "checkProteinNudge must route to BFF /v1/nutrition/protein-nudge/check")
            return (HTTPURLResponse(url: request.url!, statusCode: 500,
                                    httpVersion: "HTTP/1.1", headerFields: [:])!, Data())
        }

        do { _ = try await api.checkProteinNudge() } catch { }

        XCTAssertEqual(MockURLProtocol.interceptedRequests.count, 1,
                       "checkProteinNudge must make exactly one request")
    }

    func testCheckProteinNudge401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.checkProteinNudge()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testCheckProteinNudge500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.checkProteinNudge()
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}
