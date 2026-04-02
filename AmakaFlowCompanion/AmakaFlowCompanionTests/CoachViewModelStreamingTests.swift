//
//  CoachViewModelStreamingTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for CoachViewModel SSE streaming behavior (AMA-1410)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class CoachViewModelStreamingTests: XCTestCase {

    var viewModel: CoachViewModel!
    var mockStreamService: MockChatStreamService!
    var mockPairingService: MockPairingService!

    override func setUp() async throws {
        mockStreamService = MockChatStreamService()
        mockPairingService = MockPairingService()
        mockPairingService.storedToken = "test-jwt-token"
        mockPairingService.isPaired = true

        let dependencies = AppDependencies(
            apiService: MockAPIService(),
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: mockStreamService
        )

        viewModel = CoachViewModel(dependencies: dependencies)
    }

    func testSendMessageAddsUserMessage() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Hello!"),
            .messageEnd(sessionId: "s1", tokensUsed: 10, latencyMs: 100)
        ]

        await viewModel.sendMessage("Hi coach")

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].content, "Hi coach")
        XCTAssertEqual(viewModel.messages[1].role, .assistant)
        XCTAssertEqual(viewModel.messages[1].content, "Hello!")
    }

    func testStreamingAppendsContentDeltas() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Hello "),
            .contentDelta(text: "world!"),
            .messageEnd(sessionId: "s1", tokensUsed: 20, latencyMs: 200)
        ]

        await viewModel.sendMessage("Test")

        XCTAssertEqual(viewModel.messages[1].content, "Hello world!")
    }

    func testSessionIdPersisted() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "session-abc", traceId: nil),
            .messageEnd(sessionId: "session-abc", tokensUsed: 5, latencyMs: 50)
        ]

        await viewModel.sendMessage("Test")

        XCTAssertEqual(viewModel.sessionId, "session-abc")
    }

    func testToolCallTracked() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .functionCall(id: "t1", name: "search_workout_library"),
            .functionResult(toolUseId: "t1", name: "search_workout_library", result: "{}"),
            .contentDelta(text: "Found it!"),
            .messageEnd(sessionId: "s1", tokensUsed: 100, latencyMs: 1000)
        ]

        await viewModel.sendMessage("Find me a workout")

        let assistantMsg = viewModel.messages[1]
        XCTAssertEqual(assistantMsg.toolCalls.count, 1)
        XCTAssertEqual(assistantMsg.toolCalls[0].name, "search_workout_library")
        XCTAssertEqual(assistantMsg.toolCalls[0].status, .completed)
    }

    func testStageProgression() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .stage(stage: .analyzing, message: "Analyzing"),
            .stage(stage: .searching, message: "Searching"),
            .stage(stage: .complete, message: "Done"),
            .contentDelta(text: "Result"),
            .messageEnd(sessionId: "s1", tokensUsed: 50, latencyMs: 500)
        ]

        await viewModel.sendMessage("Plan my week")

        XCTAssertTrue(viewModel.completedStages.contains(.analyzing))
        XCTAssertTrue(viewModel.completedStages.contains(.searching))
    }

    func testErrorEventSetsErrorMessage() async {
        mockStreamService.eventsToYield = [
            .error(type: "rate_limit_exceeded", message: "Too many requests", usage: 50, limit: 50)
        ]

        await viewModel.sendMessage("Test")

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.rateLimitInfo?.usage, 50)
    }

    func testNewChatClearsState() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Hello"),
            .messageEnd(sessionId: "s1", tokensUsed: 5, latencyMs: 50)
        ]

        await viewModel.sendMessage("Hi")
        XCTAssertEqual(viewModel.messages.count, 2)

        viewModel.startNewChat()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNil(viewModel.sessionId)
    }

    func testStreamServiceCalledWithToken() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .messageEnd(sessionId: "s1", tokensUsed: 5, latencyMs: 50)
        ]

        await viewModel.sendMessage("Hi")

        XCTAssertTrue(mockStreamService.streamCalled)
    }
}
