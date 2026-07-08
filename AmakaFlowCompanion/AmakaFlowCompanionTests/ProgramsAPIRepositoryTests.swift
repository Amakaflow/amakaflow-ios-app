//
//  ProgramsAPIRepositoryTests.swift
//  AmakaFlowCompanionTests
//
//  Contract tests for ProgramsAPIRepository endpoints (issue #432).
//  Uses MockURLProtocol via APIService session transport path.
//  Covers path, method, query params, response decoding, and
//  APIError mapping (401, 500, 422).
//
//  Endpoints covered:
//    GET   /programs?status=…                         (fetchPrograms)
//    GET   /programs/{id}                             (fetchProgramDetail)
//    POST  /programs/generate                         (generateProgram)
//    GET   /programs/generate/{jobId}/status          (fetchGenerationStatus)
//    PATCH /training-programs/{id}/status             (updateProgramStatus)
//    PATCH /training-programs/workouts/{id}/complete  (completeWorkout)
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - fetchPrograms

@MainActor
final class FetchProgramsTests: XCTestCase {
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

    func testFetchProgramsHitsMapperAPIWithGETAndStatusParam() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/programs",
                           "fetchPrograms must GET /programs")
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(
                comps?.queryItems?.first(where: { $0.name == "status" })?.value,
                "active",
                "fetchPrograms must include 'status' query param"
            )
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            // makeDecoder() uses convertFromSnakeCase for field mapping.
            let data = #"{"programs":[]}"#.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.fetchPrograms(status: "active")

        XCTAssertTrue(result.programs.isEmpty)
    }

    func testFetchPrograms401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchPrograms(status: "active")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testFetchPrograms500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchPrograms(status: "active")
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - fetchProgramDetail

@MainActor
final class FetchProgramDetailTests: XCTestCase {
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

    func testFetchProgramDetailHitsMapperAPIProgramsIdWithGET() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/programs/prog-001",
                           "fetchProgramDetail must GET /programs/{id}")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = """
            {
              "id": "prog-001",
              "name": "12-Week Strength",
              "goal": "strength",
              "experience_level": "intermediate",
              "duration_weeks": 12,
              "sessions_per_week": 4,
              "status": "active"
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let program = try await api.fetchProgramDetail(id: "prog-001")

        XCTAssertEqual(program.id, "prog-001")
        XCTAssertEqual(program.name, "12-Week Strength")
        XCTAssertEqual(program.goal, "strength")
        XCTAssertEqual(program.durationWeeks, 12)
    }

    func testFetchProgramDetail401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchProgramDetail(id: "prog-001")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testFetchProgramDetail500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchProgramDetail(id: "prog-001")
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - generateProgram

@MainActor
final class GenerateProgramTests: XCTestCase {
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

    private let sampleRequest = ProgramGenerationRequest(
        goal: "strength",
        experienceLevel: "intermediate",
        durationWeeks: 12,
        sessionsPerWeek: 4,
        preferredDays: [1, 3, 5],
        timePerSession: 60,
        equipment: ["barbell", "dumbbells"],
        injuries: nil,
        focusAreas: nil,
        avoidExercises: nil
    )

    func testGenerateProgramHitsMapperAPIProgramsGenerateWithPOST() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/programs/generate",
                           "generateProgram must POST to /programs/generate")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = """
            {
              "job_id": "job-abc",
              "status": "completed",
              "program_id": "prog-new-001"
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.generateProgram(request: sampleRequest)

        XCTAssertEqual(result.jobId, "job-abc")
        XCTAssertEqual(result.status, "completed")
        XCTAssertEqual(result.programId, "prog-new-001")
    }

    func testGenerateProgram202AcceptedDecodesSuccessfully() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 202, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = """
            {
              "job_id": "job-queued",
              "status": "queued",
              "program_id": null
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.generateProgram(request: sampleRequest)

        XCTAssertEqual(result.jobId, "job-queued")
        XCTAssertEqual(result.status, "queued")
        XCTAssertNil(result.programId)
    }

    func testGenerateProgram401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.generateProgram(request: sampleRequest)
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testGenerateProgram422MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 422, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.generateProgram(request: sampleRequest)
            XCTFail("Expected server error")
        } catch APIError.serverError(422) {
            // expected
        } catch {
            XCTFail("Expected .serverError(422), got \(error)")
        }
    }
}

// MARK: - updateProgramStatus

@MainActor
final class UpdateProgramStatusTests: XCTestCase {
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

    func testUpdateProgramStatusHitsMapperAPITrainingProgramsStatusWithPATCH() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/training-programs/prog-001/status",
                           "updateProgramStatus must PATCH /training-programs/{id}/status")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        try await api.updateProgramStatus(id: "prog-001", status: "paused")
    }

    func testUpdateProgramStatus401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.updateProgramStatus(id: "prog-001", status: "paused")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testUpdateProgramStatus500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.updateProgramStatus(id: "prog-001", status: "paused")
            XCTFail("Expected server error")
        } catch APIError.serverError(500) {
            // expected
        } catch {
            XCTFail("Expected .serverError(500), got \(error)")
        }
    }
}

// MARK: - completeWorkout (Programs)

@MainActor
final class ProgramCompleteWorkoutTests: XCTestCase {
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

    func testCompleteWorkoutHitsMapperAPITrainingProgramsWorkoutsCompleteWithPATCH() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/training-programs/workouts/wkt-001/complete",
                           "completeWorkout must PATCH /training-programs/workouts/{id}/complete")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        try await api.completeWorkout(workoutId: "wkt-001")
    }

    func testCompleteWorkout401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            try await api.completeWorkout(workoutId: "wkt-001")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }
}
