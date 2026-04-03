//
//  ChatStreamServiceTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for SSE streaming models and parsing (AMA-1410)
//

import XCTest
@testable import AmakaFlowCompanion

final class ChatStreamServiceTests: XCTestCase {

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
}
