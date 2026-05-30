//
//  APIIntegrationTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for new API client methods and view models (AMA-1147)
//

import XCTest
@testable import AmakaFlowCompanion

private final class RecordingAPIObservabilityLogger: APIObservabilityLogging {
    private(set) var events: [APILogEvent] = []

    func log(_ event: APILogEvent) {
        events.append(event)
    }
}

private struct APITransportTestPayload: Decodable {
    let name: String
}

// MARK: - API Transport Observability Tests

final class APITransportObservabilityTests: XCTestCase {
    private var logger: RecordingAPIObservabilityLogger!
    private var api: APIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        logger = RecordingAPIObservabilityLogger()
        api = APIService(session: MockURLProtocol.mockSession(), observabilityLogger: logger)
    }

    override func tearDown() {
        api = nil
        logger = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func test404MapsToNotFoundAndEmitsFailLog() async throws {
        var outgoingRequestId: String?
        MockURLProtocol.requestHandler = { request in
            outgoingRequestId = request.value(forHTTPHeaderField: "X-Request-ID")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-404"]
            )!
            return (response, Data())
        }

        do {
            _ = try await api.requestData(makeRequest(path: "/missing", query: "token=secret"))
            XCTFail("Expected .notFound")
        } catch APIError.notFound {
            let fail = try XCTUnwrap(logger.events.last)
            XCTAssertEqual(fail.phase, .fail)
            XCTAssertEqual(fail.endpoint, "/missing")
            XCTAssertEqual(fail.httpMethod, "GET")
            XCTAssertEqual(fail.statusCode, 404)
            XCTAssertGreaterThanOrEqual(fail.durationMs, 0)
            XCTAssertFalse(fail.requestId.isEmpty)
            XCTAssertEqual(fail.requestId, outgoingRequestId)
            XCTAssertEqual(fail.serverRequestId, "rndr-404")
            XCTAssertEqual(fail.errorType, "notFound")
        } catch {
            XCTFail("Expected .notFound, got \(error)")
        }
    }

    func test500MapsToServerStatus() async throws {
        var outgoingRequestId: String?
        MockURLProtocol.requestHandler = { request in
            outgoingRequestId = request.value(forHTTPHeaderField: "X-Request-ID")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-500"]
            )!
            return (response, Data())
        }

        do {
            _ = try await api.requestData(makeRequest())
            XCTFail("Expected .server(status: 500)")
        } catch APIError.server(status: 500) {
            let fail = try XCTUnwrap(logger.events.last)
            XCTAssertEqual(fail.phase, .fail)
            XCTAssertEqual(fail.statusCode, 500)
            XCTAssertFalse(fail.requestId.isEmpty)
            XCTAssertEqual(fail.requestId, outgoingRequestId)
            XCTAssertEqual(fail.serverRequestId, "rndr-500")
            XCTAssertEqual(fail.errorType, "server")
        } catch {
            XCTFail("Expected .server(status: 500), got \(error)")
        }
    }

    func testTransportErrorMapsToNetwork() async throws {
        MockURLProtocol.setError(URLError(.timedOut))

        do {
            _ = try await api.requestData(makeRequest())
            XCTFail("Expected .network")
        } catch APIError.network(underlying: let underlying) {
            XCTAssertEqual((underlying as? URLError)?.code, .timedOut)
            let fail = try XCTUnwrap(logger.events.last)
            XCTAssertEqual(fail.phase, .fail)
            XCTAssertNil(fail.statusCode)
            XCTAssertFalse(fail.requestId.isEmpty)
            XCTAssertNil(fail.serverRequestId)
            XCTAssertEqual(fail.errorType, "network")
        } catch {
            XCTFail("Expected .network, got \(error)")
        }
    }

    func testDecodeMismatchMapsToDecoding() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-decode"]
            )!
            return (response, #"{"unexpected":"shape"}"#.data(using: .utf8)!)
        }

        do {
            _ = try await api.request(makeRequest(), decode: APITransportTestPayload.self)
            XCTFail("Expected .decoding")
        } catch APIError.decoding(underlying: _) {
            let fail = try XCTUnwrap(logger.events.last)
            XCTAssertEqual(fail.phase, .fail)
            XCTAssertEqual(fail.statusCode, 200)
            XCTAssertFalse(fail.requestId.isEmpty)
            XCTAssertEqual(fail.serverRequestId, "rndr-decode")
            XCTAssertEqual(fail.errorType, "decoding")
        } catch {
            XCTFail("Expected .decoding, got \(error)")
        }
    }

    func test200SuccessEmitsStartAndEndLogs() async throws {
        var outgoingRequestId: String?
        MockURLProtocol.requestHandler = { request in
            outgoingRequestId = request.value(forHTTPHeaderField: "X-Request-ID")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-success"]
            )!
            return (response, #"{"name":"ok"}"#.data(using: .utf8)!)
        }

        let result = try await api.request(makeRequest(path: "/ok"), decode: APITransportTestPayload.self)

        XCTAssertEqual(result.name, "ok")
        XCTAssertEqual(logger.events.map(\.phase), [.start, .end])
        let start = logger.events[0]
        XCTAssertEqual(start.endpoint, "/ok")
        XCTAssertEqual(start.httpMethod, "GET")
        XCTAssertGreaterThanOrEqual(start.durationMs, 0)
        XCTAssertFalse(start.requestId.isEmpty)
        XCTAssertEqual(start.requestId, outgoingRequestId)
        XCTAssertNil(start.serverRequestId)

        let end = logger.events[1]
        XCTAssertEqual(end.endpoint, "/ok")
        XCTAssertEqual(end.statusCode, 200)
        XCTAssertGreaterThanOrEqual(end.durationMs, 0)
        XCTAssertEqual(end.requestId, start.requestId)
        XCTAssertEqual(end.serverRequestId, "rndr-success")
        XCTAssertNil(end.errorType)
    }

    private func makeRequest(path: String = "/test", query: String? = nil) -> URLRequest {
        var components = URLComponents(string: "https://example.test\(path)")!
        components.query = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        return request
    }
}

// MARK: - Coach API Repository Endpoint Tests

final class CoachAPIRepositoryEndpointTests: XCTestCase {
    private var logger: RecordingAPIObservabilityLogger!
    private var api: APIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        logger = RecordingAPIObservabilityLogger()
        api = APIService(session: MockURLProtocol.mockSession(), observabilityLogger: logger)
    }

    override func tearDown() {
        api = nil
        logger = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testSetDeviceRolesPutsEncodedDeviceIDAndRolesToBFF() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(
                request.url?.absoluteString.contains("/v1/devices/device%2Fwith%20space%3Fid/roles") == true,
                "Expected encoded device id in URL, got \(request.url?.absoluteString ?? "nil")"
            )

            let body = try Self.httpBodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: [String]])
            XCTAssertEqual(json["roles"], ["workouts", "strength"])

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-device-roles"]
            )!
            let data = """
            { "success": true, "roles": ["workouts", "strength"] }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.setDeviceRoles(id: "device/with space?id", roles: [.workouts, .strength])

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.roles, [.workouts, .strength])
        XCTAssertEqual(logger.events.map(\.phase), [.start, .end])
    }

    func testSetDeviceRolesPreservesRawServerErrorBody() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 422,
                httpVersion: "HTTP/1.1",
                headerFields: ["X-Request-ID": "req-invalid-role"]
            )!
            let data = """
            { "detail": "Invalid device role" }
            """.data(using: .utf8)!
            return (response, data)
        }

        do {
            _ = try await api.setDeviceRoles(id: "device-1", roles: [.strength])
            XCTFail("Expected serverErrorWithBody")
        } catch APIError.serverErrorWithBody(let status, let body) {
            XCTAssertEqual(status, 422)
            XCTAssertTrue(body.contains("Invalid device role"))
            XCTAssertEqual(MockURLProtocol.interceptedRequests.first?.httpMethod, "PUT")
            XCTAssertTrue(MockURLProtocol.interceptedRequests.first?.url?.absoluteString.contains("/v1/devices/device-1/roles") == true)
            XCTAssertEqual(logger.events.map(\.phase), [.start, .fail])
        } catch {
            XCTFail("Expected serverErrorWithBody, got \(error)")
        }
    }

    func testFetchDayStatesHitsBFFPlanningDaysAndDecodesCamelCaseDayState() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/planning/days")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "from" })?.value, "2026-05-26")
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "to" })?.value, "2026-05-27")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-planning-days"]
            )!
            return (response, Self.dayStatesJSON)
        }

        let states = try await api.fetchDayStates(from: "2026-05-26", to: "2026-05-27")

        XCTAssertEqual(states.count, 1)
        let state = try XCTUnwrap(states.first)
        XCTAssertEqual(state.date, "2026-05-26")
        XCTAssertEqual(state.readinessScore, 87)
        XCTAssertEqual(state.readiness, .green)
        XCTAssertEqual(state.fatigueScore, 87)
        XCTAssertEqual(state.goalPhase, "base")
        XCTAssertEqual(state.acuteLoad, 12.5)
        XCTAssertEqual(state.chronicLoad, 30.0)
        XCTAssertEqual(state.constraints, ["travel"])
        XCTAssertEqual(state.availableBlocks.first?.label, "Lunch")
        XCTAssertEqual(state.plannedSessions.first?.estimatedDurationMinutes, 45)
        XCTAssertEqual(state.plannedWorkouts.first?.sport, "run")
        XCTAssertEqual(state.completedSessions.first?.durationMin, 42)
        XCTAssertEqual(state.completedWorkouts, ["completed-1"])
        XCTAssertEqual(logger.events.map(\.phase), [.start, .end])
    }

    func testFetchDayStateReturnsFirstElementFromBFFRangeEndpoint() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/planning/days")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let from = components?.queryItems?.first(where: { $0.name == "from" })?.value
            let to = components?.queryItems?.first(where: { $0.name == "to" })?.value
            XCTAssertEqual(from, to)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Self.dayStatesJSON)
        }

        let state = try await api.fetchDayState()

        XCTAssertEqual(state.date, "2026-05-26")
        XCTAssertEqual(state.readinessScore, 87)
    }

    func testFetchDayStateThrowsNotFoundWhenBFFReturnsEmptyRange() async throws {
        MockURLProtocol.setResponse(statusCode: 200, data: "[]".data(using: .utf8)!)

        do {
            _ = try await api.fetchDayState()
            XCTFail("Expected .notFound")
        } catch APIError.notFound {
            XCTAssertEqual(MockURLProtocol.interceptedRequests.first?.url?.path, "/v1/planning/days")
        } catch {
            XCTFail("Expected .notFound, got \(error)")
        }
    }

    func testDetectConflictsHitsBFFPlanningConflictsWithFromToAndDecodesConflict() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/planning/conflicts")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "from" })?.value, "2026-05-26")
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "to" })?.value, "2026-05-27")
            XCTAssertNil(components?.queryItems?.first(where: { $0.name == "start_date" }))
            XCTAssertNil(components?.queryItems?.first(where: { $0.name == "end_date" }))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-planning-conflicts"]
            )!
            let data = """
            [
              {
                "id": "conflict-1",
                "date": "2026-05-26",
                "type": "pre_fatigue",
                "description": "Fatigue is elevated before a hard workout.",
                "severity": "warning",
                "suggestion": "Move the hard session by one day."
              }
            ]
            """.data(using: .utf8)!
            return (response, data)
        }

        let conflicts = try await api.detectConflicts(startDate: "2026-05-26", endDate: "2026-05-27")

        XCTAssertEqual(conflicts.count, 1)
        let conflict = try XCTUnwrap(conflicts.first)
        XCTAssertEqual(conflict.id, "conflict-1")
        XCTAssertEqual(conflict.type, .preFatigue)
        XCTAssertEqual(conflict.severity, .warning)
        XCTAssertEqual(conflict.suggestion, "Move the hard session by one day.")
        XCTAssertEqual(logger.events.map(\.phase), [.start, .end])
    }

    func testGenerateWeekHitsBFFPlanningGenerateWeekAndDecodesRestDay() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/planning/generate-week")

            let body = try Self.httpBodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["startDate"] as? String, "2026-05-25")
            let preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
            XCTAssertEqual(preferences["maxDaysPerWeek"] as? Int, 5)
            XCTAssertEqual(preferences["preferredRestDays"] as? [Int], [1])
            XCTAssertEqual(preferences["longRunDay"] as? Int, 6)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-generate-week"]
            )!
            let data = """
            {
              "weekStartDate": "2026-05-25",
              "days": [
                {
                  "date": "2026-05-25",
                  "workouts": [],
                  "isRestDay": true,
                  "rationale": "Recovery after a high-load weekend."
                },
                {
                  "date": "2026-05-26",
                  "workouts": [
                    {
                      "id": "planned-tempo",
                      "name": "Tempo Run",
                      "sport": "running",
                      "estimatedDurationMinutes": 45,
                      "scheduledTime": "07:00",
                      "priority": "key"
                    }
                  ],
                  "isRestDay": false,
                  "rationale": "Key aerobic stimulus."
                }
              ],
              "rationale": "Balanced week around availability.",
              "totalLoadScore": 72.5
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let plan = try await api.generateWeek(
            request: GenerateWeekRequest(
                startDate: "2026-05-25",
                preferences: WeekPreferences(maxDaysPerWeek: 5, preferredRestDays: [1], longRunDay: 6)
            )
        )

        XCTAssertEqual(plan.weekStartDate, "2026-05-25")
        XCTAssertEqual(plan.days.count, 2)
        XCTAssertTrue(plan.days[0].isRestDay)
        XCTAssertEqual(plan.days[0].rationale, "Recovery after a high-load weekend.")
        XCTAssertEqual(plan.days[1].workouts.first?.name, "Tempo Run")
        XCTAssertEqual(plan.days[1].workouts.first?.priority, .key)
        XCTAssertEqual(plan.totalLoadScore, 72.5)
        XCTAssertEqual(logger.events.map(\.phase), [.start, .end])
    }

    func testParseWorkoutTextHitsBFFIngestParseTextAndDecodesExerciseList() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/ingest/parse-text")

            let body = try Self.httpBodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json["text"], "Back squat 3x5 @ 225 lb RPE 8")
            XCTAssertEqual(json["source"], "manual_import")
            XCTAssertNil(json["context"])

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-parse-text"]
            )!
            let data = """
            {
              "success": true,
              "exercises": [
                {
                  "rawName": "Back squat",
                  "sets": 3,
                  "reps": "5",
                  "distance": null,
                  "supersetGroup": null,
                  "order": 1,
                  "weight": "225",
                  "weightUnit": "lb",
                  "rpe": 8.0,
                  "notes": null,
                  "restSeconds": null
                }
              ],
              "detectedFormat": "strength",
              "confidence": 0.91,
              "source": "manual_import"
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await api.parseWorkoutText(
            text: "Back squat 3x5 @ 225 lb RPE 8",
            context: "manual_import"
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.detectedFormat, "strength")
        XCTAssertEqual(result.confidence, 0.91)
        XCTAssertEqual(result.source, "manual_import")
        XCTAssertEqual(result.exercises.count, 1)
        let exercise = try XCTUnwrap(result.exercises.first)
        XCTAssertEqual(exercise.rawName, "Back squat")
        XCTAssertEqual(exercise.sets, 3)
        XCTAssertEqual(exercise.reps, "5")
        XCTAssertNil(exercise.distance)
        XCTAssertNil(exercise.supersetGroup)
        XCTAssertEqual(exercise.order, 1)
        XCTAssertEqual(exercise.weight, "225")
        XCTAssertEqual(exercise.weightUnit, "lb")
        XCTAssertEqual(exercise.rpe, 8.0)
        XCTAssertNil(exercise.notes)
        XCTAssertNil(exercise.restSeconds)
        XCTAssertEqual(logger.events.map(\.phase), [.start, .end])
    }

    func testConflictTypeAndSeverityDecodeAllBackendRawValuesAndFallback() throws {
        let backendTypes: [(String, ConflictType)] = [
            ("pre_fatigue", .preFatigue),
            ("consecutive_hard", .consecutiveHard),
            ("same_muscle_group", .sameMuscleGroup),
            ("overload", .overload),
            ("no_recovery", .noRecovery)
        ]
        for (rawValue, expected) in backendTypes {
            let decoded = try JSONDecoder().decode(ConflictType.self, from: "\"\(rawValue)\"".data(using: .utf8)!)
            XCTAssertEqual(decoded, expected, "Expected \(rawValue) to decode")
        }

        let backendSeverities: [(String, ConflictSeverity)] = [
            ("warning", .warning),
            ("critical", .critical)
        ]
        for (rawValue, expected) in backendSeverities {
            let decoded = try JSONDecoder().decode(ConflictSeverity.self, from: "\"\(rawValue)\"".data(using: .utf8)!)
            XCTAssertEqual(decoded, expected, "Expected \(rawValue) to decode")
        }

        XCTAssertEqual(try JSONDecoder().decode(ConflictType.self, from: "\"future_conflict\"".data(using: .utf8)!), .unknown)
        XCTAssertEqual(try JSONDecoder().decode(ConflictSeverity.self, from: "\"future_severity\"".data(using: .utf8)!), .unknown)
    }

    func testGhostEndpointThrowsNotImplementedWithoutNetworkCall() async throws {
        do {
            _ = try await api.fetchShoeComparison()
            XCTFail("Expected .notImplemented")
        } catch APIError.notImplemented {
            XCTAssertTrue(MockURLProtocol.interceptedRequests.isEmpty)
        } catch {
            XCTFail("Expected .notImplemented, got \(error)")
        }
    }

    func testFetchAgentActionsHitsBFFAgentActionsAndDecodesCamelCaseEnvelope() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/agent/actions")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "status" })?.value, "pending")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-agent-actions"]
            )!
            let data = """
            [
              {
                "id": "act-1",
                "kind": "session_moved",
                "title": "Move tempo run",
                "rationale": "Recovery dipped overnight.",
                "status": "pending",
                "decisionRequired": true,
                "reversible": true,
                "riskLevel": "medium",
                "preview": "Tue 7am → Wed 6pm",
                "expiresAt": null,
                "createdAt": "2026-05-26T12:00:00Z",
                "appliedAt": null,
                "payload": {"sessionId": "s1"}
              }
            ]
            """.data(using: .utf8)!
            return (response, data)
        }

        let actions = try await api.fetchAgentActions(status: "pending")

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.id, "act-1")
        XCTAssertEqual(actions.first?.status, .pending)
        XCTAssertEqual(actions.first?.riskLevel, .medium)
        XCTAssertEqual(MockURLProtocol.interceptedRequests.first?.url?.path, "/v1/agent/actions")
    }

    func testRespondToActionPostsDecisionToBFFAgentRespondRoute() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/agent/actions/act-1/respond")
            let body = try Self.httpBodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json["decision"], "approve")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Self.agentActionJSON(status: "applied"))
        }

        let action = try await api.respondToAction(id: "act-1", decision: "approve")

        XCTAssertEqual(action.status, .applied)
        XCTAssertEqual(MockURLProtocol.interceptedRequests.first?.url?.path, "/v1/agent/actions/act-1/respond")
    }

    func testUndoActionPostsToBFFAgentUndoRoute() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/agent/actions/act-1/undo")
            XCTAssertNil(request.httpBody)

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Self.agentActionJSON(status: "undone"))
        }

        let action = try await api.undoAction(id: "act-1")

        XCTAssertEqual(action.status, .undone)
        XCTAssertEqual(MockURLProtocol.interceptedRequests.first?.url?.path, "/v1/agent/actions/act-1/undo")
    }

    func testTelegramSetupAndStatusUseMobileBFFRoutesAndGeneratedCamelCase() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-telegram"]
            )!

            switch request.url?.path {
            case "/v1/messaging/telegram/setup":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNil(request.url?.query)
                let data = """
                {
                  "token": "token-1",
                  "deepLink": "https://t.me/amakaflow_userbot?start=token-1",
                  "nativeLink": "tg://resolve?domain=amakaflow_userbot&start=token-1",
                  "expiresInSeconds": 900
                }
                """.data(using: .utf8)!
                return (response, data)
            case "/v1/messaging/telegram/status":
                XCTAssertEqual(request.httpMethod, "GET")
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "token" })?.value, "token-1")
                let data = """
                { "linked": true, "telegramIdHash": "tg_hash_123" }
                """.data(using: .utf8)!
                return (response, data)
            default:
                XCTFail("Unexpected Telegram request path: \(request.url?.path ?? "nil")")
                return (response, Data("{}".utf8))
            }
        }

        let token = try await api.mintTelegramLinkToken()
        let status = try await api.getTelegramLinkStatus(token: token.token)

        XCTAssertEqual(token.token, "token-1")
        XCTAssertEqual(token.deepLink, "https://t.me/amakaflow_userbot?start=token-1")
        XCTAssertEqual(token.nativeLink, "tg://resolve?domain=amakaflow_userbot&start=token-1")
        XCTAssertEqual(token.expiresInSeconds, 900)
        XCTAssertTrue(status.linked)
        XCTAssertEqual(status.telegramIdHash, "tg_hash_123")
        XCTAssertNil(status.telegramId)

        let paths = MockURLProtocol.interceptedRequests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/v1/messaging/telegram/setup", "/v1/messaging/telegram/status"])
        XCTAssertFalse(paths.contains { $0.contains("/api/telegram/") })
        XCTAssertEqual(logger.events.map(\.phase), [.start, .end, .start, .end])
    }

    private static let dayStatesJSON = """
    [
      {
        "date": "2026-05-26",
        "plannedSessions": [
          {
            "id": "planned-1",
            "source": "amakaflow",
            "sourceId": "agent-1",
            "date": "2026-05-26",
            "type": "run",
            "intensity": "easy",
            "durationMin": 45,
            "structuredSteps": [{"kind": "warmup", "durationMin": 10}],
            "modifiable": true,
            "rationale": "Aerobic base"
          }
        ],
        "completedSessions": [
          {
            "id": "completed-1",
            "source": "garmin",
            "date": "2026-05-26",
            "type": "run",
            "durationMin": 42,
            "actualData": {"avgHr": 142}
          }
        ],
        "readinessScore": 87,
        "availableBlocks": [
          {"start": "2026-05-26T12:00:00Z", "end": "2026-05-26T13:00:00Z", "label": "Lunch"}
        ],
        "constraints": ["travel"],
        "goalPhase": "base",
        "acuteLoad": 12.5,
        "chronicLoad": 30.0
      }
    ]
    """.data(using: .utf8)!

    func testPostReadinessSamplePutsAppleHealthHRVToBFF() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/v1/readiness/sample")

            let body = try Self.httpBodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["source"] as? String, "apple_health")
            XCTAssertEqual(json["sample_date"] as? String, "2026-05-30")
            XCTAssertEqual(json["hrv"] as? Double, 55.5)
            XCTAssertNil(json["resting_hr"])
            XCTAssertNil(json["sleep_hours"])
            XCTAssertNil(json["sleep_quality"])

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Rndr-Id": "rndr-readiness-sample"]
            )!
            return (response, #"{"success":true,"date":"2026-05-30","source":"apple_health"}"#.data(using: .utf8)!)
        }

        let result = try await api.postReadinessSample(
            hrv: 55.5,
            restingHr: nil,
            sleepHours: nil,
            sleepQuality: nil,
            sampleDate: "2026-05-30"
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.date, "2026-05-30")
        XCTAssertEqual(result.source, "apple_health")
        XCTAssertEqual(logger.events.map(\.phase), [.start, .end])
    }

    func testPostReadinessSampleErrorsMapToCTAError() async throws {
        for status in [422, 503] {
            MockURLProtocol.reset()
            logger = RecordingAPIObservabilityLogger()
            api = APIService(session: MockURLProtocol.mockSession(), observabilityLogger: logger)
            MockURLProtocol.requestHandler = { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["X-Request-ID": "req-readiness-\(status)"]
                )!
                return (response, #"{"detail":"readiness sample error"}"#.data(using: .utf8)!)
            }

            do {
                _ = try await api.postReadinessSample(
                    hrv: 55,
                    restingHr: nil,
                    sleepHours: nil,
                    sleepQuality: nil,
                    sampleDate: "2026-05-30"
                )
                XCTFail("Expected readiness sample status \(status) to throw")
            } catch {
                let mapped = CTAError.map(error)
                guard case .http(let mappedStatus, let body, _) = mapped else {
                    XCTFail("Expected CTAError.http for \(status), got \(mapped)")
                    continue
                }
                XCTAssertEqual(mappedStatus, status)
                XCTAssertTrue(body?.contains("readiness sample error") == true)
                XCTAssertEqual(logger.events.map(\.phase), [.start, .fail])
                XCTAssertEqual(MockURLProtocol.interceptedRequests.first?.url?.path, "/v1/readiness/sample")
            }
        }
    }

    private static func httpBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func agentActionJSON(status: String) -> Data {
        """
        {
          "id": "act-1",
          "kind": "session_moved",
          "title": "Move tempo run",
          "rationale": "Recovery dipped overnight.",
          "status": "\(status)",
          "decisionRequired": false,
          "reversible": true,
          "riskLevel": "low",
          "preview": "Tue 7am → Wed 6pm",
          "expiresAt": null,
          "createdAt": "2026-05-26T12:00:00Z",
          "appliedAt": "2026-05-26T12:01:00Z",
          "payload": null
        }
        """.data(using: .utf8)!
    }
}

// MARK: - Model Decoding Tests

final class PlanningModelTests: XCTestCase {

    func testDayStateDecoding() throws {
        let json = """
        {
            "date": "2026-03-21",
            "readiness": "green",
            "planned_workouts": [],
            "completed_workouts": ["w1"],
            "fatigue_score": 0.35,
            "notes": "Good day"
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let state = try decoder.decode(DayState.self, from: json)

        XCTAssertEqual(state.date, "2026-03-21")
        XCTAssertEqual(state.readiness, .green)
        XCTAssertEqual(state.completedWorkouts, ["w1"])
        XCTAssertEqual(state.fatigueScore, 0.35)
        XCTAssertEqual(state.notes, "Good day")
    }

    func testConflictDecoding() throws {
        let json = """
        {
            "id": "c1",
            "date": "2026-03-22",
            "type": "overload",
            "description": "Too many hard sessions",
            "severity": "high",
            "suggestion": "Move one session to Thursday"
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let conflict = try decoder.decode(Conflict.self, from: json)

        XCTAssertEqual(conflict.id, "c1")
        XCTAssertEqual(conflict.type, .overload)
        XCTAssertEqual(conflict.severity, .high)
        XCTAssertNotNil(conflict.suggestion)
    }

    func testProposedPlanDecoding() throws {
        let json = """
        {
            "week_start_date": "2026-03-23",
            "days": [
                {
                    "date": "2026-03-23",
                    "workouts": [],
                    "is_rest_day": true,
                    "rationale": "Recovery day"
                }
            ],
            "rationale": "Balanced week",
            "total_load_score": 42.5
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let plan = try decoder.decode(ProposedPlan.self, from: json)

        XCTAssertEqual(plan.weekStartDate, "2026-03-23")
        XCTAssertEqual(plan.days.count, 1)
        XCTAssertTrue(plan.days[0].isRestDay)
        XCTAssertEqual(plan.totalLoadScore, 42.5)
    }

    func testReadinessLevelAllCases() {
        XCTAssertNotNil(ReadinessLevel(rawValue: "green"))
        XCTAssertNotNil(ReadinessLevel(rawValue: "yellow"))
        XCTAssertNotNil(ReadinessLevel(rawValue: "red"))
        XCTAssertNotNil(ReadinessLevel(rawValue: "rest"))
        XCTAssertNotNil(ReadinessLevel(rawValue: "unknown"))
        XCTAssertNil(ReadinessLevel(rawValue: "invalid"))
    }
}

// MARK: - Coach Model Tests

final class CoachModelTests: XCTestCase {

    func testCoachResponseDecoding() throws {
        let json = """
        {
            "id": "resp1",
            "message": "Focus on recovery today",
            "suggestions": [
                {"id": "s1", "text": "Light yoga", "type": "recovery"}
            ],
            "action_items": [
                {"id": "a1", "title": "Schedule rest day", "description": "Take tomorrow off"}
            ]
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let response = try decoder.decode(CoachResponse.self, from: json)

        XCTAssertEqual(response.message, "Focus on recovery today")
        XCTAssertEqual(response.suggestions?.count, 1)
        XCTAssertEqual(response.suggestions?.first?.type, .recovery)
        XCTAssertEqual(response.actionItems?.count, 1)
    }

    func testFatigueAdviceDecoding() throws {
        let json = """
        {
            "level": "moderate",
            "message": "Take it easy",
            "recommendations": ["Stretch", "Hydrate"],
            "suggested_rest_days": 2,
            "recovery_activities": ["yoga", "walking"]
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let advice = try decoder.decode(FatigueAdvice.self, from: json)

        XCTAssertEqual(advice.level, .moderate)
        XCTAssertEqual(advice.recommendations.count, 2)
        XCTAssertEqual(advice.suggestedRestDays, 2)
    }

    func testCoachMemoryDecoding() throws {
        let json = """
        {
            "id": "mem1",
            "content": "User prefers morning runs",
            "category": "preference",
            "created_at": "2026-03-20",
            "relevance": 0.95
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let memory = try decoder.decode(CoachMemory.self, from: json)

        XCTAssertEqual(memory.id, "mem1")
        XCTAssertEqual(memory.category, "preference")
        XCTAssertEqual(memory.relevance, 0.95)
    }
}

// MARK: - Action Model Tests

final class ActionModelTests: XCTestCase {

    func testAgentActionDecodesBFFEnvelopeWithUnknownFallbacksAndNullOptionals() throws {
        let json = """
        {
            "id": "act1",
            "kind": "future_agent_verb",
            "title": "Move interval session",
            "rationale": "Based on your goals",
            "status": "future_status",
            "decisionRequired": true,
            "reversible": true,
            "riskLevel": "future_risk",
            "preview": null,
            "expiresAt": null,
            "createdAt": "2026-03-21T10:00:00Z",
            "appliedAt": null,
            "payload": {"workoutId": "w1", "nested": {"ok": true}}
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let action = try decoder.decode(AgentAction.self, from: json)

        XCTAssertEqual(action.id, "act1")
        XCTAssertEqual(action.kind, "future_agent_verb")
        XCTAssertEqual(action.status, .unknown)
        XCTAssertEqual(action.riskLevel, .unknown)
        XCTAssertNil(action.preview)
        XCTAssertNil(action.expiresAt)
        XCTAssertEqual(action.createdAt, "2026-03-21T10:00:00Z")
        XCTAssertEqual(action.payload?["workoutId"]?.value as? String, "w1")
    }
}

// MARK: - Analytics Model Tests

final class AnalyticsModelTests: XCTestCase {

    func testShoeStatsDecoding() throws {
        let json = """
        {
            "id": "shoe1",
            "name": "Pegasus 41",
            "brand": "Nike",
            "total_distance_km": 523.4,
            "total_runs": 87,
            "average_pace_min_km": 5.12,
            "retired_at": null,
            "added_at": "2025-06-01"
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let shoe = try decoder.decode(ShoeStats.self, from: json)

        XCTAssertEqual(shoe.name, "Pegasus 41")
        XCTAssertEqual(shoe.brand, "Nike")
        XCTAssertEqual(shoe.totalDistanceKm, 523.4)
        XCTAssertEqual(shoe.totalRuns, 87)
        XCTAssertNil(shoe.retiredAt)
    }

    func testSubscriptionDecoding() throws {
        let json = """
        {
            "plan": "pro",
            "status": "active",
            "current_period_end": "2026-04-21",
            "cancel_at_period_end": false,
            "features": ["coach", "analytics", "planning"]
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let sub = try decoder.decode(Subscription.self, from: json)

        XCTAssertEqual(sub.plan, "pro")
        XCTAssertEqual(sub.status, .active)
        XCTAssertEqual(sub.features?.count, 3)
    }

    func testNotificationPreferencesDecoding() throws {
        let json = """
        {
            "workout_reminders": true,
            "coach_messages": false,
            "weekly_report": true,
            "conflict_alerts": true,
            "recovery_reminders": false,
            "reminder_minutes_before": 60
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let prefs = try decoder.decode(NotificationPreferences.self, from: json)

        XCTAssertTrue(prefs.workoutReminders)
        XCTAssertFalse(prefs.coachMessages)
        XCTAssertEqual(prefs.reminderMinutesBefore, 60)
    }

    func testNotificationPreferencesDefaults() {
        let prefs = NotificationPreferences()
        XCTAssertTrue(prefs.workoutReminders)
        XCTAssertTrue(prefs.coachMessages)
        XCTAssertTrue(prefs.weeklyReport)
        XCTAssertEqual(prefs.reminderMinutesBefore, 30)
    }
}

// MARK: - Mock API Service Tests

final class MockAPIServiceNewEndpointsTests: XCTestCase {

    @MainActor
    func testMockFetchDayStates() async throws {
        let mock = MockAPIService()
        let sampleState = DayState(
            date: "2026-03-21",
            readiness: .green,
            plannedWorkouts: [],
            completedWorkouts: [],
            fatigueScore: nil,
            notes: nil
        )
        mock.fetchDayStatesResult = .success([sampleState])

        let states = try await mock.fetchDayStates(from: "2026-03-21", to: "2026-03-27")
        XCTAssertTrue(mock.fetchDayStatesCalled)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].readiness, .green)
    }

    @MainActor
    func testMockSendCoachMessage() async throws {
        let mock = MockAPIService()
        mock.sendCoachMessageResult = .success(
            CoachResponse(id: "1", message: "Rest today", suggestions: nil, actionItems: nil)
        )

        let response = try await mock.sendCoachMessage(message: "How should I train?", context: nil)
        XCTAssertTrue(mock.sendCoachMessageCalled)
        XCTAssertEqual(response.message, "Rest today")
    }

    @MainActor
    func testMockFetchAgentActions() async throws {
        let mock = MockAPIService()
        let action = AgentAction(
            id: "a1",
            kind: "session_added",
            title: "Add run",
            status: .pending,
            decisionRequired: true,
            reversible: false,
            createdAt: "2026-05-26T12:00:00Z"
        )
        mock.fetchAgentActionsResult = .success([action])

        let actions = try await mock.fetchAgentActions(status: nil)
        XCTAssertTrue(mock.fetchAgentActionsCalled)
        XCTAssertEqual(actions.count, 1)
    }

    @MainActor
    func testMockRespondToAction() async throws {
        let mock = MockAPIService()
        let response = try await mock.respondToAction(id: "a1", decision: "approve")
        XCTAssertTrue(mock.respondToActionCalled)
        XCTAssertEqual(mock.respondToActionDecision, "approve")
        XCTAssertEqual(response.id, AgentAction.samplePending.id)
    }

    @MainActor
    func testMockUndoAction() async throws {
        let mock = MockAPIService()
        let response = try await mock.undoAction(id: "a1")
        XCTAssertTrue(mock.undoActionCalled)
        XCTAssertEqual(mock.undoActionId, "a1")
        XCTAssertEqual(response.id, AgentAction.sampleApplied.id)
    }

    @MainActor
    func testMockFetchShoeComparison() async throws {
        let mock = MockAPIService()
        let shoe = ShoeStats(
            id: "s1", name: "Vaporfly", brand: "Nike",
            totalDistanceKm: 100, totalRuns: 20,
            averagePaceMinKm: 4.5, retiredAt: nil, addedAt: nil
        )
        mock.fetchShoeComparisonResult = .success([shoe])

        let shoes = try await mock.fetchShoeComparison()
        XCTAssertTrue(mock.fetchShoeComparisonCalled)
        XCTAssertEqual(shoes.count, 1)
        XCTAssertEqual(shoes[0].name, "Vaporfly")
    }

    @MainActor
    func testMockFetchNotificationPreferences() async throws {
        let mock = MockAPIService()
        let prefs = try await mock.fetchNotificationPreferences()
        XCTAssertTrue(mock.fetchNotificationPreferencesCalled)
        XCTAssertTrue(prefs.workoutReminders)
    }
}

// MARK: - ViewModel Tests

final class CalendarViewModelTests: XCTestCase {

    @MainActor
    func testLoadDayStatesPopulatesDict() async {
        let mock = MockAPIService()
        let state = DayState(
            date: "2026-03-21",
            readiness: .yellow,
            plannedWorkouts: [],
            completedWorkouts: [],
            fatigueScore: 0.6,
            notes: nil
        )
        mock.fetchDayStatesResult = .success([state])

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = CalendarViewModel(dependencies: deps)

        await vm.loadDayStates(from: Date(), to: Date())
        XCTAssertFalse(vm.dayStates.isEmpty)
        XCTAssertEqual(vm.dayStates["2026-03-21"]?.readiness, .yellow)
    }

    @MainActor
    func testGenerateWeekSetsProposedPlan() async {
        let mock = MockAPIService()
        let plan = ProposedPlan(
            weekStartDate: "2026-03-23",
            days: [],
            rationale: "Test plan",
            totalLoadScore: 50
        )
        mock.generateWeekResult = .success(plan)

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = CalendarViewModel(dependencies: deps)

        await vm.generateWeek()
        XCTAssertNotNil(vm.proposedPlan)
        XCTAssertEqual(vm.proposedPlan?.rationale, "Test plan")
    }
}

// NOTE: CoachViewModelTests updated for AMA-1410 streaming ViewModel.
// Full streaming coverage is in CoachViewModelStreamingTests.swift.
final class CoachViewModelTests: XCTestCase {

    @MainActor
    func testSendMessageAppendsMessages() async {
        let mockStream = MockChatStreamService()
        mockStream.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Coach reply"),
            .messageEnd(sessionId: "s1", tokensUsed: 10, latencyMs: 100)
        ]
        let mockPairing = MockPairingService()
        mockPairing.storedToken = "test-token"
        mockPairing.isPaired = true

        let deps = AppDependencies(
            apiService: MockAPIService(),
            pairingService: mockPairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: mockStream
        )
        let vm = CoachViewModel(dependencies: deps)

        await vm.sendMessage("Hello coach")
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].role, .user)
        XCTAssertEqual(vm.messages[0].content, "Hello coach")
        XCTAssertEqual(vm.messages[1].role, .assistant)
        XCTAssertEqual(vm.messages[1].content, "Coach reply")
    }

    @MainActor
    func testSendMessageHandlesError() async {
        let mockStream = MockChatStreamService()
        mockStream.errorToThrow = APIError.serverError(500)
        let mockPairing = MockPairingService()
        mockPairing.storedToken = "test-token"
        mockPairing.isPaired = true

        let deps = AppDependencies(
            apiService: MockAPIService(),
            pairingService: mockPairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: mockStream
        )
        let vm = CoachViewModel(dependencies: deps)

        await vm.sendMessage("Hello")
        XCTAssertEqual(vm.messages.count, 0) // User message removed on failure
        // AMA-1803 P2: errorMessage replaced by typed CTAError.
        XCTAssertNotNil(vm.error)
    }

    @MainActor
    func testLoadFatigueAdvice() async {
        let mock = MockAPIService()
        mock.getFatigueAdviceResult = .success(
            FatigueAdvice(level: .low, message: "You're fine", recommendations: ["Run"], suggestedRestDays: nil, recoveryActivities: nil)
        )

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = CoachViewModel(dependencies: deps)

        await vm.loadFatigueAdvice()
        XCTAssertNotNil(vm.fatigueAdvice)
        XCTAssertEqual(vm.fatigueAdvice?.level, .low)
    }
}

final class ActivityFeedViewModelTests: XCTestCase {

    @MainActor
    func testLoadActions() async {
        let mock = MockAPIService()
        let action = AgentAction(
            id: "a1",
            kind: "rest_day",
            title: "Rest day",
            rationale: "Take a break",
            status: .pending,
            decisionRequired: true,
            reversible: true,
            createdAt: "2026-05-26T12:00:00Z"
        )
        mock.fetchAgentActionsResult = .success([action])

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = ActivityFeedViewModel(dependencies: deps)

        await vm.loadActions()
        XCTAssertEqual(vm.actions.count, 1)
        XCTAssertEqual(vm.actions[0].title, "Rest day")
    }

    @MainActor
    func testApproveAction() async {
        let mock = MockAPIService()
        let action = AgentAction(
            id: "a1",
            kind: "general",
            title: "Test",
            status: .pending,
            decisionRequired: true,
            reversible: true,
            createdAt: "2026-05-26T12:00:00Z"
        )
        mock.fetchAgentActionsResult = .success([])

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = ActivityFeedViewModel(dependencies: deps)

        await vm.approveAction(action)
        XCTAssertTrue(mock.respondToActionCalled)
    }
}

final class AgentInboxViewModelTests: XCTestCase {

    @MainActor
    func testNeedsYouCoachDidAndHistorySplit() async {
        let mock = MockAPIService()
        let pending = AgentAction(id: "pending", kind: "session_moved", title: "Pending", status: .pending, decisionRequired: true, reversible: true, createdAt: "2026-05-26T12:00:00Z")
        let applied = AgentAction(id: "applied", kind: "rest_day", title: "Applied", status: .applied, decisionRequired: false, reversible: true, createdAt: "2026-05-26T12:00:00Z")
        let rejected = AgentAction(id: "rejected", kind: "week_generated", title: "Rejected", status: .rejected, decisionRequired: false, reversible: false, createdAt: "2026-05-26T12:00:00Z")
        mock.fetchAgentActionsResult = .success([pending, applied, rejected])
        let vm = AgentInboxViewModel(dependencies: makeDependencies(apiService: mock))

        await vm.load()

        XCTAssertEqual(vm.needsYou.map(\.id), ["pending"])
        XCTAssertEqual(vm.coachDid.map(\.id), ["applied"])
        XCTAssertEqual(vm.historyTail.map(\.id), ["rejected"])
    }

    @MainActor
    func testApproveRejectUndoCallRepositoryAndRefresh() async {
        let mock = MockAPIService()
        mock.fetchAgentActionsResult = .success([])
        let vm = AgentInboxViewModel(dependencies: makeDependencies(apiService: mock))

        await vm.approve(id: "a1")
        XCTAssertTrue(mock.respondToActionCalled)
        XCTAssertEqual(mock.respondToActionId, "a1")
        XCTAssertEqual(mock.respondToActionDecision, "approve")
        XCTAssertTrue(mock.fetchAgentActionsCalled)

        mock.respondToActionCalled = false
        await vm.reject(id: "a2")
        XCTAssertTrue(mock.respondToActionCalled)
        XCTAssertEqual(mock.respondToActionId, "a2")
        XCTAssertEqual(mock.respondToActionDecision, "reject")

        await vm.undo(id: "a3")
        XCTAssertTrue(mock.undoActionCalled)
        XCTAssertEqual(mock.undoActionId, "a3")
    }

    @MainActor
    func testThrownErrorSetsAPIErrorDisplay() async {
        let mock = MockAPIService()
        mock.fetchAgentActionsResult = .failure(APIError.server(status: 500))
        let vm = AgentInboxViewModel(dependencies: makeDependencies(apiService: mock))

        await vm.load()

        XCTAssertEqual(vm.apiErrorDisplay?.category, .server)
        XCTAssertEqual(vm.apiErrorDisplay?.message, "The server had a problem. Please try again.")
    }

    @MainActor
    private func makeDependencies(apiService: APIServiceProviding) -> AppDependencies {
        AppDependencies(
            apiService: apiService,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
    }
}

final class ShoeComparisonViewModelTests: XCTestCase {

    @MainActor
    func testLoadShoes() async {
        let mock = MockAPIService()
        let shoes = [
            ShoeStats(id: "s1", name: "Shoe A", brand: nil, totalDistanceKm: 100, totalRuns: 10, averagePaceMinKm: nil, retiredAt: nil, addedAt: nil),
            ShoeStats(id: "s2", name: "Shoe B", brand: nil, totalDistanceKm: 200, totalRuns: 20, averagePaceMinKm: nil, retiredAt: nil, addedAt: nil),
        ]
        mock.fetchShoeComparisonResult = .success(shoes)

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = ShoeComparisonViewModel(dependencies: deps)

        await vm.loadShoes()
        XCTAssertEqual(vm.shoes.count, 2)
        XCTAssertEqual(vm.totalDistance, 300)
        XCTAssertEqual(vm.totalRuns, 30)
    }
}

final class TrainingPreferencesViewModelTests: XCTestCase {

    @MainActor
    func testLoadPreferences() async {
        let mock = MockAPIService()
        let prefs = NotificationPreferences(
            workoutReminders: false,
            coachMessages: true,
            weeklyReport: false,
            conflictAlerts: true,
            recoveryReminders: true,
            reminderMinutesBefore: 60
        )
        mock.fetchNotificationPreferencesResult = .success(prefs)

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = TrainingPreferencesViewModel(dependencies: deps)

        await vm.loadPreferences()
        XCTAssertFalse(vm.preferences.workoutReminders)
        XCTAssertEqual(vm.preferences.reminderMinutesBefore, 60)
    }

    @MainActor
    func testSavePreferences() async {
        let mock = MockAPIService()
        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = TrainingPreferencesViewModel(dependencies: deps)

        await vm.savePreferences()
        XCTAssertTrue(mock.updateNotificationPreferencesCalled)
        XCTAssertTrue(vm.saveSuccess)
    }
}
