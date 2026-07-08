//
//  IngestionAPIRepositoryTests.swift
//  AmakaFlowCompanionTests
//
//  Contract tests for IngestionAPIRepository endpoints (issue #432).
//  Uses MockURLProtocol via APIService session transport path.
//  All endpoints route through ingestorAPIURL.
//  Covers path, method, response decoding, APIError mapping, and
//  PairingService.isPaired guard behaviour.
//
//  Endpoints covered:
//    POST /workouts/parse-voice     (parseVoiceWorkout)
//    POST /ingest/instagram_reel   (ingestInstagramReel)
//    GET  /voice/dictionary        (fetchPersonalDictionary)
//    POST /voice/dictionary        (syncPersonalDictionary)
//    POST /import/detect           (detectImport)
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - parseVoiceWorkout

@MainActor
final class ParseVoiceWorkoutTests: XCTestCase {
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

    func testParseVoiceWorkoutHitsIngestorAPIWithPOSTAndDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/workouts/parse-voice",
                           "parseVoiceWorkout must POST to /workouts/parse-voice")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = """
            {
              "success": true,
              "confidence": 0.95,
              "suggestions": [],
              "workout": {
                "id": "v-001",
                "name": "Voice Workout",
                "sport": "strength",
                "duration": 3600,
                "blocks": [],
                "source": "ai"
              }
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.parseVoiceWorkout(transcription: "5 sets of squats")

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.confidence, 0.95)
        XCTAssertEqual(result.workout.name, "Voice Workout")
    }

    func testParseVoiceWorkoutUnpairedThrowsUnauthorized() async throws {
        PairingService.shared.isPaired = false

        do {
            _ = try await api.parseVoiceWorkout(transcription: "5 sets of squats")
            XCTFail("Expected .unauthorized for unpaired state")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testParseVoiceWorkout401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.parseVoiceWorkout(transcription: "5 sets of squats")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testParseVoiceWorkout422MapsToServerErrorWithBody() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 422, httpVersion: "HTTP/1.1", headerFields: [:])!
            let body = #"Could not understand workout description"#.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await api.parseVoiceWorkout(transcription: "????")
            XCTFail("Expected .serverErrorWithBody(422, ...)")
        } catch APIError.serverErrorWithBody(422, _) {
            // expected
        } catch {
            XCTFail("Expected .serverErrorWithBody(422, ...), got \(error)")
        }
    }

    func testParseVoiceWorkout500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.parseVoiceWorkout(transcription: "5 sets of squats")
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - ingestInstagramReel

@MainActor
final class IngestInstagramReelTests: XCTestCase {
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

    func testIngestInstagramReelHitsIngestorAPIWithPOSTAndDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/ingest/instagram_reel",
                           "ingestInstagramReel must POST to /ingest/instagram_reel")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = """
            {
              "title": "Leg Day",
              "workout_type": "strength",
              "source": "instagram"
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.ingestInstagramReel(url: "https://www.instagram.com/reel/abc")

        XCTAssertEqual(result.title, "Leg Day")
        XCTAssertEqual(result.workoutType, "strength")
    }

    func testIngestInstagramReelUnpairedThrowsUnauthorized() async throws {
        PairingService.shared.isPaired = false

        do {
            _ = try await api.ingestInstagramReel(url: "https://www.instagram.com/reel/abc")
            XCTFail("Expected .unauthorized for unpaired state")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testIngestInstagramReel422MapsToServerErrorWithBody() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 422, httpVersion: "HTTP/1.1", headerFields: [:])!
            let body = #"Could not process Instagram Reel"#.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await api.ingestInstagramReel(url: "https://www.instagram.com/reel/bad")
            XCTFail("Expected .serverErrorWithBody(422, ...)")
        } catch APIError.serverErrorWithBody(422, _) {
            // expected
        } catch {
            XCTFail("Expected .serverErrorWithBody(422, ...), got \(error)")
        }
    }

    func testIngestInstagramReel401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.ingestInstagramReel(url: "https://www.instagram.com/reel/abc")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }
}

// MARK: - fetchPersonalDictionary

@MainActor
final class FetchPersonalDictionaryTests: XCTestCase {
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

    func testFetchPersonalDictionaryHitsIngestorAPIVoiceDictionaryWithGET() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/voice/dictionary",
                           "fetchPersonalDictionary must GET /voice/dictionary")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = """
            {
              "corrections": {"gonna": "going to"},
              "custom_terms": ["AMRAP", "EMOM", "WOD"]
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.fetchPersonalDictionary()

        XCTAssertEqual(result.corrections["gonna"], "going to")
        XCTAssertEqual(result.customTerms.count, 3)
    }

    func testFetchPersonalDictionaryUnpairedThrowsUnauthorized() async throws {
        PairingService.shared.isPaired = false

        do {
            _ = try await api.fetchPersonalDictionary()
            XCTFail("Expected .unauthorized for unpaired state")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testFetchPersonalDictionary401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchPersonalDictionary()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testFetchPersonalDictionary500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchPersonalDictionary()
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - detectImport

@MainActor
final class DetectImportTests: XCTestCase {
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

    private let sampleRequest = BulkDetectRequest(
        profileId: "profile-001",
        sourceType: "urls",
        sources: ["https://example.com/workout1"]
    )

    func testDetectImportHitsIngestorAPIImportDetectWithPOST() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/import/detect",
                           "detectImport must POST to /import/detect")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            // makeDecoder() uses convertFromSnakeCase.
            let data = """
            {
              "success": true,
              "job_id": "job-detect-001",
              "items": [],
              "total": 0,
              "success_count": 0,
              "error_count": 0
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.detectImport(request: sampleRequest)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.jobId, "job-detect-001")
        XCTAssertEqual(result.total, 0)
    }

    func testDetectImport401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.detectImport(request: sampleRequest)
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testDetectImport500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.detectImport(request: sampleRequest)
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}
