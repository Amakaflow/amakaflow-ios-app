//
//  ChatStreamServiceTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for SSE streaming models and parsing (AMA-1410)
//

import XCTest
@testable import AmakaFlowCompanion

final class ChatStreamServiceTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Model Tests

    func testChatStageDisplayNames() {
        XCTAssertEqual(ChatStage.analyzing.displayName, "Analyzing")
        XCTAssertEqual(ChatStage.complete.displayName, "Complete")
    }

    func testChatStageIcons() {
        XCTAssertEqual(ChatStage.searching.iconName, "magnifyingglass")
        XCTAssertEqual(ChatStage.creating.iconName, "dumbbell.fill")
    }

    func testToolCallDisplayNames() {
        let searchTool = ChatToolCall(id: "t1", name: "search_workout_library", status: .running)
        XCTAssertEqual(searchTool.displayName, "Searching workouts")

        let unknownTool = ChatToolCall(id: "t2", name: "some_future_tool", status: .pending)
        XCTAssertEqual(unknownTool.displayName, "Working")
    }

    func testToolCallIcons() {
        let calendarTool = ChatToolCall(id: "t1", name: "get_calendar_events", status: .completed)
        XCTAssertEqual(calendarTool.iconName, "calendar")

        let unknownTool = ChatToolCall(id: "t2", name: "unknown", status: .pending)
        XCTAssertEqual(unknownTool.iconName, "wrench.fill")
    }

    func testGeneratedWorkoutDecoding() throws {
        let json = """
        {
            "name": "Upper Body Push",
            "duration": "45 min",
            "difficulty": "Intermediate",
            "exercises": [
                {"name": "Bench Press", "sets": 4, "reps": "8", "muscle_group": "Chest", "notes": null},
                {"name": "OHP", "sets": 3, "reps": "10", "muscle_group": "Shoulders", "notes": "Strict form"}
            ]
        }
        """.data(using: .utf8)!

        let workout = try JSONDecoder().decode(GeneratedWorkout.self, from: json)
        XCTAssertEqual(workout.name, "Upper Body Push")
        XCTAssertEqual(workout.exercises.count, 2)
        XCTAssertEqual(workout.exercises[0].muscleGroup, "Chest")
        XCTAssertEqual(workout.exercises[1].notes, "Strict form")
    }

    func testWorkoutSearchResultDecoding() throws {
        let json = """
        {"id": "w1", "name": "HIIT Blast", "duration": "30 min", "exercise_count": 8}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(WorkoutSearchResult.self, from: json)
        XCTAssertEqual(result.id, "w1")
        XCTAssertEqual(result.exerciseCount, 8)
    }

    // MARK: - SSE Framer Unit Tests

    func testSSEFramerFeedsCompletedBlocksAndFlushesRemainder() {
        var framer = SSEFramer()
        let input = "event: foo\ndata: {\"x\":1}\n\nevent: bar\ndata: {\"x\":2}"
        var blocks: [Data] = []
        for byte in input.utf8 {
            blocks.append(contentsOf: framer.feed(byte))
        }
        let remainder = framer.flush()

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(String(data: blocks[0], encoding: .utf8), "event: foo\ndata: {\"x\":1}")
        XCTAssertEqual(String(data: remainder, encoding: .utf8), "event: bar\ndata: {\"x\":2}")
    }

    func testSSEFramerHandlesCRLFDelimiter() {
        var framer = SSEFramer()
        let input = "event: foo\r\ndata: {}\r\n\r\nevent: bar\r\ndata: {}"
        var blocks: [Data] = []
        for byte in input.utf8 {
            blocks.append(contentsOf: framer.feed(byte))
        }
        let remainder = framer.flush()

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(String(data: blocks[0], encoding: .utf8), "event: foo\r\ndata: {}")
        XCTAssertEqual(String(data: remainder, encoding: .utf8), "event: bar\r\ndata: {}")
    }

    func testSSEFramerHandlesCRDelimiter() {
        var framer = SSEFramer()
        let input = "event: foo\rdata: {}\r\revent: bar\rdata: {}"
        var blocks: [Data] = []
        for byte in input.utf8 {
            blocks.append(contentsOf: framer.feed(byte))
        }
        let remainder = framer.flush()

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(String(data: blocks[0], encoding: .utf8), "event: foo\rdata: {}")
        XCTAssertEqual(String(data: remainder, encoding: .utf8), "event: bar\rdata: {}")
    }

    // MARK: - Real Stream Tests

    func testStreamYieldsContentDeltaEventsFromChunkedSSEBody() async throws {
        let chunks = [
            "event: message_start\n",
            "data: {\"session_id\":\"s1\"}\n\n",
            "event: content_delta\n",
            "data: {\"text\":\"Ho",
            "w \"}\n\n",
            "event: content_delta\ndata: {\"text\":\"about an ",
            "easy run?\"}\n\n",
            "event: message_end\n",
            "data: {\"session_id\":\"s1\",\"tokens_used\":219}\n\n"
        ].map { Data($0.utf8) }
        MockURLProtocol.setChunkedResponse(chunks: chunks)

        let service = ChatStreamService(session: MockURLProtocol.mockSession())
        let request = ChatStreamRequest(message: "What should I do today?", sessionId: nil, context: nil)

        var events: [SSEEvent] = []
        for try await event in service.stream(request: request, token: "test-token") {
            events.append(event)
        }

        XCTAssertEqual(MockURLProtocol.interceptedRequests.count, 1)
        XCTAssertEqual(MockURLProtocol.interceptedRequests.first?.httpMethod, "POST")
        XCTAssertEqual(MockURLProtocol.interceptedRequests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(events.first, .messageStart(sessionId: "s1", traceId: nil))
        XCTAssertEqual(events.compactMap { event -> String? in
            if case .contentDelta(let text) = event { return text }
            return nil
        }.joined(), "How about an easy run?")
        XCTAssertEqual(events.last, .messageEnd(sessionId: "s1", tokensUsed: 219, latencyMs: nil))
        XCTAssertEqual(events.count, 4)
    }

    func testStreamRequestBodyMatchesGeneratedChatStreamRequestShape() async throws {
        let chunks = [
            "event: message_start\ndata: {\"session_id\":\"s1\"}\n\n",
            "event: message_end\ndata: {\"session_id\":\"s1\"}\n\n"
        ].map { Data($0.utf8) }
        MockURLProtocol.setChunkedResponse(chunks: chunks)

        let service = ChatStreamService(session: MockURLProtocol.mockSession())
        let context = ChatStreamContext(
            currentPage: "coach",
            selectedWorkoutId: "workout-1",
            selectedDate: "2026-06-02"
        )
        let request = ChatStreamRequest(message: "What should I do today?", sessionId: "session-1", context: context)

        var events: [SSEEvent] = []
        for try await event in service.stream(request: request, token: "test-token") {
            events.append(event)
        }

        let intercepted = try XCTUnwrap(MockURLProtocol.interceptedRequests.first)
        XCTAssertEqual(intercepted.url?.path, "/v1/chat/stream")
        let body = try Self.httpBodyData(from: intercepted)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["message"] as? String, "What should I do today?")
        XCTAssertEqual(json["session_id"] as? String, "session-1")
        XCTAssertNil(json["sessionId"])
        let contextJSON = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertEqual(contextJSON["current_page"] as? String, "coach")
        XCTAssertEqual(contextJSON["selected_workout_id"] as? String, "workout-1")
        XCTAssertEqual(contextJSON["selected_date"] as? String, "2026-06-02")
        XCTAssertNil(contextJSON["currentPage"])
        XCTAssertNil(contextJSON["selectedWorkoutId"])
        XCTAssertEqual(events.first, .messageStart(sessionId: "s1", traceId: nil))
    }

    func testStreamYieldsErrorAndContinuesPastMalformedChunkedSSEBlock() async throws {
        let chunks = [
            "event: message_start\n",
            "data: {\"session_id\":\"s1\"}\n\n",
            "event: content_delta\n",
            "data: {\"text\":\"Before \"}\n\n",
            "event: error\n",
            "data: {\"type\":\"feature_dis",
            "abled\",\"message\":\"Feature unavailable\"}\n\n",
            "event: content_delta\n",
            "data: {not ",
            "json}\n\n",
            "event: content_delta\ndata: {\"text\":\"After\"}\r\n",
            "\r\n",
            "event: message_end\n",
            "data: {\"session_id\":\"s1\",\"tokens_used\":31}\n\n"
        ].map { Data($0.utf8) }
        MockURLProtocol.setChunkedResponse(chunks: chunks)

        let service = ChatStreamService(session: MockURLProtocol.mockSession())
        let request = ChatStreamRequest(message: "What should I do today?", sessionId: nil, context: nil)

        var events: [SSEEvent] = []
        for try await event in service.stream(request: request, token: "test-token") {
            events.append(event)
        }

        XCTAssertEqual(events, [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Before "),
            .error(type: "feature_disabled", message: "Feature unavailable", usage: nil, limit: nil),
            .contentDelta(text: "After"),
            .messageEnd(sessionId: "s1", tokensUsed: 31, latencyMs: nil)
        ])
    }

    // AMA-302: multi-line HTTP error body must preserve newlines between lines.
    func testStreamHTTPErrorBodyPreservesMultiLineNewlines() async throws {
        let errorBody = "First line\nSecond line\nThird line"
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!
            return (response, Data(errorBody.utf8))
        }

        let service = ChatStreamService(session: MockURLProtocol.mockSession())
        let req = ChatStreamRequest(message: "test", sessionId: nil, context: nil)

        do {
            for try await _ in service.stream(request: req, token: "test-token") {}
            XCTFail("Expected ChatStreamError.httpError")
        } catch ChatStreamError.httpError(let statusCode, let body) {
            XCTAssertEqual(statusCode, 503)
            XCTAssertTrue(body.contains("First line\nSecond line"), "Expected '\\n' separator between error body lines, got: \(body)")
        } catch {
            XCTFail("Expected ChatStreamError.httpError, got \(error)")
        }
    }

    // MARK: - SSE Parsing Tests

    func testParseContentDeltaEvent() throws {
        let block = "event: content_delta\ndata: {\"text\":\"Hello world\"}"
        let event = SSEParser.parse(block: block)
        XCTAssertEqual(event, .contentDelta(text: "Hello world"))
    }

    func testParseMessageStartEvent() throws {
        let block = "event: message_start\ndata: {\"session_id\":\"abc-123\",\"trace_id\":\"tr-1\"}"
        let event = SSEParser.parse(block: block)
        XCTAssertEqual(event, .messageStart(sessionId: "abc-123", traceId: "tr-1"))
    }

    func testParseFirstTokenEvent() throws {
        let block = "event: first_token\ndata: {\"latency_ms\":432,\"source_stage\":\"llm\",\"mode\":\"live\"}"
        let event = SSEParser.parse(block: block)
        XCTAssertEqual(event, .firstToken(latencyMs: 432, sourceStage: "llm", mode: "live"))
    }

    func testParseFunctionCallEvent() throws {
        let block = "event: function_call\ndata: {\"id\":\"toolu_01\",\"name\":\"search_workout_library\"}"
        let event = SSEParser.parse(block: block)
        XCTAssertEqual(event, .functionCall(id: "toolu_01", name: "search_workout_library"))
    }

    func testParseFunctionResultEvent() throws {
        let block = "event: function_result\ndata: {\"tool_use_id\":\"toolu_01\",\"name\":\"search_workout_library\",\"result\":\"{\\\"workouts\\\":[]}\"}"
        let event = SSEParser.parse(block: block)
        XCTAssertEqual(event, .functionResult(toolUseId: "toolu_01", name: "search_workout_library", result: "{\"workouts\":[]}"))
    }

    func testParseStageEvent() throws {
        let block = "event: stage\ndata: {\"stage\":\"analyzing\",\"message\":\"Understanding your request\"}"
        let event = SSEParser.parse(block: block)
        XCTAssertEqual(event, .stage(stage: .analyzing, message: "Understanding your request"))
    }

    func testParseMessageEndEvent() throws {
        let block = "event: message_end\ndata: {\"session_id\":\"abc-123\",\"tokens_used\":500,\"latency_ms\":1200}"
        let event = SSEParser.parse(block: block)
        XCTAssertEqual(event, .messageEnd(sessionId: "abc-123", tokensUsed: 500, latencyMs: 1200))
    }

    func testParseErrorEvent() throws {
        let block = "event: error\ndata: {\"type\":\"rate_limit_exceeded\",\"message\":\"Too many requests\",\"usage\":50,\"limit\":50}"
        let event = SSEParser.parse(block: block)
        XCTAssertEqual(event, .error(type: "rate_limit_exceeded", message: "Too many requests", usage: 50, limit: 50))
    }

    func testParseHeartbeatEvent() throws {
        let block = "event: heartbeat\ndata: {\"status\":\"executing_tool\",\"tool_name\":\"search_workout_library\",\"elapsed_seconds\":5.2}"
        let event = SSEParser.parse(block: block)
        XCTAssertEqual(event, .heartbeat(status: "executing_tool", toolName: "search_workout_library", elapsedSeconds: 5.2))
    }

    func testParseUnknownEventReturnsNil() throws {
        let block = "event: unknown_event\ndata: {\"foo\":\"bar\"}"
        let event = SSEParser.parse(block: block)
        XCTAssertNil(event)
    }

    func testParseEmptyBlockReturnsNil() throws {
        let event = SSEParser.parse(block: "")
        XCTAssertNil(event)
    }

    func testSplitSSEBuffer() throws {
        let buffer = "event: content_delta\ndata: {\"text\":\"A\"}\n\nevent: content_delta\ndata: {\"text\":\"B\"}\n\n"
        let (blocks, remainder) = SSEParser.splitBuffer(buffer)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(remainder, "")
    }

    func testSplitSSEBufferWithIncomplete() throws {
        let buffer = "event: content_delta\ndata: {\"text\":\"A\"}\n\nevent: content_del"
        let (blocks, remainder) = SSEParser.splitBuffer(buffer)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(remainder, "event: content_del")
    }


    // MARK: - Program Stream Tests

    func testProgramStreamDesignThenGenerateThreadsPreviewIdFromChunkedSSEBody() async throws {
        MockURLProtocol.setChunkedResponse(chunks: [
            "event: stage\n",
            "data: {\"stage\":\"designing\",\"message\":\"Designing your 8-week program...\"}\n\n",
            "event: preview\n",
            "data: {\"preview_id\":\"outline-1\",\"program\":{\"name\":\"Outline\",\"goal\":\"strength\",\"duration_weeks\":8,\"sessions_per_week\":3,\"periodization_model\":\"linear\",\"weeks\":[]}}\n\n"
        ].map { Data($0.utf8) })

        let service = ProgramStreamService(session: MockURLProtocol.mockSession())
        let designRequest = DesignProgramRequest(
            goal: "strength",
            experienceLevel: "intermediate",
            durationWeeks: 8,
            sessionsPerWeek: 3,
            equipment: ["barbell"],
            timePerSession: 60,
            preferredDays: ["Monday", "Wednesday", "Friday"],
            injuries: nil,
            focusAreas: nil,
            avoidExercises: nil
        )

        var designEvents: [ProgramStreamEvent] = []
        for try await event in service.designProgram(request: designRequest, token: "test-token") {
            designEvents.append(event)
        }

        let designRequestURL = try XCTUnwrap(MockURLProtocol.interceptedRequests.first)
        XCTAssertEqual(designRequestURL.url?.path, "/v1/programs/design/stream")
        XCTAssertEqual(designRequestURL.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        let designBody = try Self.httpBodyData(from: designRequestURL)
        let designJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: designBody) as? [String: Any])
        XCTAssertEqual(designJSON["experience_level"] as? String, "intermediate")
        XCTAssertNil(designJSON["experienceLevel"])

        let outlinePreviewId = try XCTUnwrap(designEvents.compactMap { event -> String? in
            if case .preview(let previewId, _) = event { return previewId }
            return nil
        }.last)
        XCTAssertEqual(outlinePreviewId, "outline-1")

        MockURLProtocol.reset()
        MockURLProtocol.setChunkedResponse(chunks: [
            "event: stage\n",
            "data: {\"stage\":\"generating\",\"message\":\"Creating Week 1 workouts...\",\"sub_progress\":{\"current\":1,\"total\":8}}\n\n",
            "event: preview\n",
            "data: {\"preview_id\":\"full-1\",\"program\":{\"name\":\"Full Program\",\"goal\":\"strength\",\"duration_weeks\":8,\"sessions_per_week\":3,\"periodization_model\":\"linear\",\"weeks\":[{\"week_number\":1,\"focus\":\"Base\",\"intensity_percentage\":70,\"volume_modifier\":1.0,\"is_deload\":false,\"workouts\":[{\"name\":\"Lower Strength\",\"day_of_week\":0,\"workout_type\":\"strength\",\"target_duration_minutes\":60,\"exercises\":[{\"name\":\"Back Squat\",\"sets\":4,\"reps\":\"5\",\"rest_seconds\":180}]}]}]}}\n\n"
        ].map { Data($0.utf8) })

        var generateEvents: [ProgramStreamEvent] = []
        for try await event in service.generateProgram(previewId: outlinePreviewId, token: "test-token") {
            generateEvents.append(event)
        }

        let generateRequest = try XCTUnwrap(MockURLProtocol.interceptedRequests.first)
        XCTAssertEqual(generateRequest.url?.path, "/v1/programs/generate/stream")
        let generateBody = try Self.httpBodyData(from: generateRequest)
        let generateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: generateBody) as? [String: Any])
        XCTAssertEqual(generateJSON["preview_id"] as? String, "outline-1")
        XCTAssertNil(generateJSON["previewId"])

        XCTAssertEqual(generateEvents.compactMap { event -> String? in
            if case .preview(let previewId, _) = event { return previewId }
            return nil
        }.last, "full-1")
        XCTAssertEqual(generateEvents.compactMap { event -> ProposedProgram? in
            if case .preview(_, let payload) = event { return payload.program }
            return nil
        }.last?.weeks.first?.workouts.first?.exercises.first?.name, "Back Squat")
    }

    func testProgramStreamErrorEventSurfacesRecoverableMessage() async throws {
        MockURLProtocol.setChunkedResponse(chunks: [
            "event: stage\ndata: {\"stage\":\"designing\",\"message\":\"Designing...\"}\n\n",
            "event: error\n",
            "data: {\"stage\":\"designing\",\"message\":\"Too many active pipelines. Please wait for one to finish.\",\"recoverable\":true}\n\n"
        ].map { Data($0.utf8) })

        let service = ProgramStreamService(session: MockURLProtocol.mockSession())
        let request = DesignProgramRequest(
            goal: "strength",
            experienceLevel: "intermediate",
            durationWeeks: 8,
            sessionsPerWeek: 3,
            equipment: ["barbell"],
            timePerSession: nil,
            preferredDays: nil,
            injuries: nil,
            focusAreas: nil,
            avoidExercises: nil
        )

        var events: [ProgramStreamEvent] = []
        for try await event in service.designProgram(request: request, token: "test-token") {
            events.append(event)
        }

        XCTAssertEqual(events.last, .error(message: "Too many active pipelines. Please wait for one to finish.", recoverable: true))
    }

    func testProgramStreamParserHandlesCRLFFramedEvents() throws {
        let buffer = """
        event: stage\r
        data: {\"stage\":\"designing\",\"message\":\"Designing...\"}\r
        \r
        event: preview\r
        data: {\"preview_id\":\"outline-crlf\",\"program\":{\"name\":\"Outline\",\"goal\":\"strength\",\"duration_weeks\":8,\"sessions_per_week\":3,\"periodization_model\":\"linear\",\"weeks\":[]}}\r
        \r
        """

        let split = SSEParser.splitBuffer(buffer)
        XCTAssertEqual(split.blocks.count, 2)
        XCTAssertEqual(split.remainder, "")

        let events = split.blocks.compactMap { ProgramStreamService.parseEvent(block: $0, decoder: JSONDecoder()) }
        XCTAssertEqual(events.first, .stage(stage: "designing", message: "Designing...", subProgress: nil))
        XCTAssertEqual(events.compactMap { event -> String? in
            if case .preview(let previewId, _) = event { return previewId }
            return nil
        }.last, "outline-crlf")
    }

    // RED: O(n²) per-byte normaliser converts lone \r → \n before the following
    // \n arrives, making \r\n look like \n\n and prematurely splitting blocks.
    // This test catches that regression.
    func testProgramStreamCRLFDelimitedStreamFramedCorrectly() async throws {
        let body = "event: stage\r\ndata: {\"stage\":\"saving\",\"message\":\"Saving...\"}\r\n\r\n" +
                   "event: complete\r\ndata: {\"program_name\":\"P\",\"workout_count\":1,\"workout_ids\":[\"w1\"],\"scheduled_count\":1}\r\n\r\n"
        MockURLProtocol.setChunkedResponse(chunks: [Data(body.utf8)])

        let service = ProgramStreamService(session: MockURLProtocol.mockSession())
        var events: [ProgramStreamEvent] = []
        for try await event in service.saveProgram(previewId: "p1", scheduleStartDate: nil, token: "test-token") {
            events.append(event)
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .stage(stage: "saving", message: "Saving...", subProgress: nil))
        XCTAssertEqual(events.last, .complete(workoutIds: ["w1"], scheduledCount: 1, workoutCount: 1))
    }

    func testProgramStreamParsesSaveCompleteEvent() async throws {
        MockURLProtocol.setChunkedResponse(chunks: [
            "event: stage\ndata: {\"stage\":\"saving\",\"message\":\"Saving program to library...\"}\n\n",
            "event: complete\n",
            "data: {\"program_name\":\"Full Program\",\"workout_count\":2,\"workout_ids\":[\"w1\",\"w2\"],\"scheduled_count\":2}\n\n"
        ].map { Data($0.utf8) })

        let service = ProgramStreamService(session: MockURLProtocol.mockSession())
        var events: [ProgramStreamEvent] = []
        for try await event in service.saveProgram(previewId: "full-1", scheduleStartDate: "2026-06-08", token: "test-token") {
            events.append(event)
        }

        let request = try XCTUnwrap(MockURLProtocol.interceptedRequests.first)
        XCTAssertEqual(request.url?.path, "/v1/programs/save/stream")
        let body = try Self.httpBodyData(from: request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["preview_id"] as? String, "full-1")
        XCTAssertEqual(json["schedule_start_date"] as? String, "2026-06-08")
        XCTAssertEqual(events.last, .complete(workoutIds: ["w1", "w2"], scheduledCount: 2, workoutCount: 2))
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
}
