//
//  CoachAPIRepositoryTests.swift
//  AmakaFlowCompanionTests
//
//  Contract tests for CoachAPIRepository endpoints (issue #311).
//  Uses MockURLProtocol via APIService.request() transport path.
//  Covers path, method, query params, response decoding, and APIError
//  mapping (401, 404, 422, 500).
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - getCoachingProfile

@MainActor
final class GetCoachingProfileTests: XCTestCase {
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

    func testGetCoachingProfileHitsBFFWithGETAndDecodesProfile() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/coaching/profile",
                           "getCoachingProfile must route to BFF /v1/coaching/profile")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let data = """
            {
              "user_id": "user-abc",
              "experience_level": "intermediate",
              "sessions_per_week": 4,
              "primary_goal": "strength",
              "created_at": "2026-01-01T00:00:00Z",
              "updated_at": "2026-07-01T00:00:00Z"
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let profile = try await api.getCoachingProfile()

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.userId, "user-abc")
        XCTAssertEqual(profile?.experienceLevel, "intermediate")
        XCTAssertEqual(profile?.sessionsPerWeek, 4)
        XCTAssertEqual(profile?.primaryGoal, "strength")
    }

    func testGetCoachingProfile404ReturnsNil() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data())
        }

        let profile = try await api.getCoachingProfile()

        XCTAssertNil(profile, "404 must be treated as empty (no profile yet), not an error")
    }

    func testGetCoachingProfile401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, Data())
        }

        do {
            _ = try await api.getCoachingProfile()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testGetCoachingProfile500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, Data())
        }

        do {
            _ = try await api.getCoachingProfile()
            XCTFail("Expected server error")
        } catch APIError.server(status: 500) {
            // expected
        } catch {
            XCTFail("Expected .server(500), got \(error)")
        }
    }
}

// MARK: - fetchDayStates

@MainActor
final class FetchDayStatesTests: XCTestCase {
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

    func testFetchDayStatesHitsBFFPlanningDaysWithDateRange() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/planning/days",
                           "fetchDayStates must route to BFF /v1/planning/days")
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertNotNil(
                comps?.queryItems?.first(where: { $0.name == "from" }),
                "fetchDayStates must include 'from' date query param"
            )
            XCTAssertNotNil(
                comps?.queryItems?.first(where: { $0.name == "to" }),
                "fetchDayStates must include 'to' date query param"
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            // DayState uses custom CodingKeys with camelCase key names.
            let data = """
            [
              {
                "date": "2026-07-08",
                "readiness": "green",
                "readinessScore": 80,
                "plannedWorkouts": [],
                "completedWorkouts": [],
                "plannedSessions": [],
                "completedSessions": [],
                "availableBlocks": [],
                "constraints": []
              }
            ]
            """.data(using: .utf8)!
            return (response, data)
        }

        let states = try await api.fetchDayStates(from: "2026-07-08", to: "2026-07-08")

        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].date, "2026-07-08")
        XCTAssertEqual(states[0].readiness, .green)
        XCTAssertEqual(states[0].readinessScore, 80)
    }

    func testFetchDayStatesEmptyArrayDecodesSuccessfully() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, "[]".data(using: .utf8)!)
        }

        let states = try await api.fetchDayStates(from: "2026-07-08", to: "2026-07-14")

        XCTAssertTrue(states.isEmpty)
    }

    func testFetchDayStates401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, Data())
        }

        do {
            _ = try await api.fetchDayStates(from: "2026-07-08", to: "2026-07-08")
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testFetchDayStates500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, Data())
        }

        do {
            _ = try await api.fetchDayStates(from: "2026-07-08", to: "2026-07-08")
            XCTFail("Expected server error")
        } catch APIError.server(status: 500) {
            // expected
        } catch {
            XCTFail("Expected .server(500), got \(error)")
        }
    }
}

// MARK: - generateWeek

@MainActor
final class GenerateWeekTests: XCTestCase {
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

    func testGenerateWeekHitsBFFWithPOSTAndDecodesProposedPlan() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/planning/generate-week",
                           "generateWeek must route to BFF /v1/planning/generate-week")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            // ProposedPlan uses convertFromSnakeCase decoder.
            let data = """
            {
              "week_start_date": "2026-07-07",
              "days": [],
              "rationale": "Recovery week based on high ATL",
              "total_load_score": 42.5
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let plan = try await api.generateWeek()

        XCTAssertEqual(plan.weekStartDate, "2026-07-07")
        XCTAssertEqual(plan.rationale, "Recovery week based on high ATL")
        XCTAssertEqual(plan.totalLoadScore, 42.5)
        XCTAssertTrue(plan.days.isEmpty)
    }

    func testGenerateWeek401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, Data())
        }

        do {
            _ = try await api.generateWeek()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testGenerateWeek422MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 422,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            let body = #"{"detail":"Validation error: missing required field"}"#.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await api.generateWeek()
            XCTFail("Expected server error")
        } catch APIError.serverErrorWithBody(422, _) {
            // expected: non-empty body triggers serverErrorWithBody
        } catch {
            XCTFail("Expected .serverErrorWithBody(422, ...), got \(error)")
        }
    }
}

// MARK: - fetchAgentActions

@MainActor
final class FetchAgentActionsTests: XCTestCase {
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

    func testFetchAgentActionsHitsBFFWithGETAndEmptyArray() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/agent/actions",
                           "fetchAgentActions must route to BFF /v1/agent/actions")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, "[]".data(using: .utf8)!)
        }

        let actions = try await api.fetchAgentActions()

        XCTAssertTrue(actions.isEmpty)
    }

    func testFetchAgentActionsWithStatusFilterSendsQueryParam() async throws {
        MockURLProtocol.requestHandler = { request in
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(
                comps?.queryItems?.first(where: { $0.name == "status" })?.value,
                "pending",
                "fetchAgentActions(status:) must include 'status' query param"
            )
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, "[]".data(using: .utf8)!)
        }

        let actions = try await api.fetchAgentActions(status: "pending")

        XCTAssertTrue(actions.isEmpty)
    }

    func testFetchAgentActions401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchAgentActions()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }
}
