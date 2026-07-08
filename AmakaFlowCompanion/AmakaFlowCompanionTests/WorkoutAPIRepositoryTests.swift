//
//  WorkoutAPIRepositoryTests.swift
//  AmakaFlowCompanionTests
//
//  Contract tests for WorkoutAPIRepository endpoints that use the
//  APIService.request() transport path. Verifies path, method, query
//  parameters, response decoding, and error mapping including the
//  401→refresh→retry-once guard (issue #311).
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - fetchScheduledWorkouts

@MainActor
final class FetchScheduledWorkoutsTests: XCTestCase {
    private var api: APIService!
    private var savedIsPaired: Bool!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        api = APIService(session: MockURLProtocol.mockSession())
        // Bypass the PairingService.isPaired guard so requests reach the network layer.
        savedIsPaired = PairingService.shared.isPaired
        PairingService.shared.isPaired = true
    }

    override func tearDown() {
        PairingService.shared.isPaired = savedIsPaired
        api = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchScheduledWorkoutsHitsBFFPlannedWithGetAndDateRange() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/workouts/planned",
                           "fetchScheduledWorkouts must route to BFF /v1/workouts/planned")
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertNotNil(
                comps?.queryItems?.first(where: { $0.name == "from" }),
                "fetchScheduledWorkouts must include 'from' date query param"
            )
            XCTAssertNotNil(
                comps?.queryItems?.first(where: { $0.name == "to" }),
                "fetchScheduledWorkouts must include 'to' date query param"
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-planned-ok"]
            )!
            let data = """
            {
              "workouts": [
                {
                  "id": "planned-001",
                  "userId": "user-1",
                  "title": "Morning Run",
                  "date": "2026-07-08",
                  "startTime": "07:00:00",
                  "status": "scheduled",
                  "source": "coach"
                }
              ]
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let workouts = try await api.fetchScheduledWorkouts()

        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts[0].workout.id, "planned-001")
        XCTAssertEqual(workouts[0].workout.name, "Morning Run")
    }

    func testFetchScheduledWorkoutsEmptyListDecodesSuccessfully() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (response, #"{"workouts":[]}"#.data(using: .utf8)!)
        }

        let workouts = try await api.fetchScheduledWorkouts()

        XCTAssertTrue(workouts.isEmpty)
    }

    // 401 → retry-once guard: refreshToken returns false in the test environment
    // (no live Clerk session), so the method rethrows .unauthorized after one attempt.
    func testFetchScheduledWorkouts401SurfacesUnauthorizedAfterRefreshFails() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1",
                headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchScheduledWorkouts()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            XCTAssertEqual(
                MockURLProtocol.interceptedRequests.first?.url?.path,
                "/v1/workouts/planned"
            )
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func testFetchScheduledWorkouts500MapsToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1",
                headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchScheduledWorkouts()
            XCTFail("Expected server error")
        } catch APIError.server(status: 500) {
            // correct
        } catch {
            XCTFail("Expected .server(500), got \(error)")
        }
    }
}

// MARK: - fetchPushedWorkouts

@MainActor
final class FetchPushedWorkoutsTests: XCTestCase {
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

    func testFetchPushedWorkoutsHitsMapperAPIWithDeviceParam() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/workouts/pushed")
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(
                comps?.queryItems?.first(where: { $0.name == "device" })?.value,
                "ios-companion",
                "fetchPushedWorkouts must send device=ios-companion"
            )

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-pushed-ok"])!
            let data = """
            [
              {
                "id": "pushed-001",
                "name": "Strength A",
                "sport": "strength",
                "duration": 2700,
                "source": "coach"
              }
            ]
            """.data(using: .utf8)!
            return (response, data)
        }

        let workouts = try await api.fetchPushedWorkouts()

        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts[0].id, "pushed-001")
        XCTAssertEqual(workouts[0].sport, .strength)
    }

    func testFetchPushedWorkouts401SurfacesUnauthorized() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1",
                headerFields: [:])!
            return (response, Data())
        }

        do {
            _ = try await api.fetchPushedWorkouts()
            XCTFail("Expected .unauthorized")
        } catch APIError.unauthorized {
            XCTAssertEqual(
                MockURLProtocol.interceptedRequests.first?.url?.path,
                "/workouts/pushed"
            )
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }
}
