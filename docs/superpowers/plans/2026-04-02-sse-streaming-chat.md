# AMA-1410: SSE Streaming Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade iOS AI Coach chat from request/response to full SSE streaming, matching the web app's `POST /chat/stream` endpoint.

**Architecture:** New `ChatStreamService` handles SSE parsing via `URLSession.bytes(for:)`. Existing `CoachViewModel` is rewritten to drive streaming state. Three new view components render tool calls, stages, and workout previews inline.

**Tech Stack:** Swift, SwiftUI, URLSession async bytes, XCTest

**Spec:** `docs/superpowers/specs/2026-04-02-sse-streaming-chat-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `AmakaFlow/Models/ChatStreamModels.swift` | Create | SSE event types, ToolCall, ChatStage, GeneratedWorkout, WorkoutExercise, ChatStreamRequest |
| `AmakaFlow/Services/ChatStreamService.swift` | Create | SSE client — POST to /chat/stream, parse events, yield AsyncThrowingStream |
| `AmakaFlow/ViewModels/CoachViewModel.swift` | Rewrite | Streaming-aware state: process SSE events, session persistence, abort |
| `AmakaFlow/Models/CoachModels.swift` | Modify | Update ChatMessage to support mutable content, tool calls, stages |
| `AmakaFlow/Views/Components/ToolCallCard.swift` | Create | Inline tool call visualization with spinner/checkmark |
| `AmakaFlow/Views/Components/WorkoutPreviewCard.swift` | Create | Inline generated workout card with exercises |
| `AmakaFlow/Views/Components/StageIndicator.swift` | Create | Horizontal stage progress bar |
| `AmakaFlow/Views/CoachChatView.swift` | Rewrite | Integrate streaming bubble, tool cards, stages, workout cards, markdown, new chat |
| `AmakaFlow/DependencyInjection/AppDependencies.swift` | Modify | Add ChatStreamService to DI container + mock |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/ChatStreamServiceTests.swift` | Create | SSE parsing unit tests |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/CoachViewModelStreamingTests.swift` | Create | ViewModel state transition tests |

---

## Task 1: SSE Event Models

**Files:**
- Create: `AmakaFlow/Models/ChatStreamModels.swift`
- Test: `AmakaFlowCompanion/AmakaFlowCompanionTests/ChatStreamServiceTests.swift`

- [ ] **Step 1: Create the model file with all SSE types**

Create `AmakaFlow/Models/ChatStreamModels.swift`:

```swift
//
//  ChatStreamModels.swift
//  AmakaFlow
//
//  SSE streaming models for AI Coach chat (AMA-1410)
//

import Foundation

// MARK: - SSE Events

enum SSEEvent: Equatable {
    case messageStart(sessionId: String, traceId: String?)
    case contentDelta(text: String)
    case functionCall(id: String, name: String)
    case functionResult(toolUseId: String, name: String, result: String)
    case stage(stage: ChatStage, message: String)
    case heartbeat(status: String, toolName: String?, elapsedSeconds: Double?)
    case messageEnd(sessionId: String, tokensUsed: Int?, latencyMs: Int?)
    case error(type: String, message: String, usage: Int?, limit: Int?)
}

// MARK: - Chat Stage

enum ChatStage: String, Codable, CaseIterable {
    case analyzing
    case researching
    case searching
    case creating
    case complete

    var displayName: String {
        rawValue.capitalized
    }

    var iconName: String {
        switch self {
        case .analyzing: return "sparkles"
        case .researching: return "person.fill"
        case .searching: return "magnifyingglass"
        case .creating: return "dumbbell.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Tool Call

struct ChatToolCall: Identifiable, Equatable {
    let id: String
    let name: String
    var status: Status
    var result: String?
    var elapsedSeconds: Double?

    enum Status: Equatable {
        case pending, running, completed, error
    }

    var displayName: String {
        switch name {
        case "search_workout_library": return "Searching workouts"
        case "create_workout_plan": return "Creating workout plan"
        case "get_workout_history": return "Looking up history"
        case "get_calendar_events": return "Checking calendar"
        default: return "Working"
        }
    }

    var iconName: String {
        switch name {
        case "search_workout_library": return "magnifyingglass"
        case "create_workout_plan": return "dumbbell.fill"
        case "get_workout_history": return "clock.arrow.circlepath"
        case "get_calendar_events": return "calendar"
        default: return "wrench.fill"
        }
    }
}

// MARK: - Generated Workout (from tool results)

struct GeneratedWorkout: Codable, Equatable {
    let name: String?
    let duration: String?
    let difficulty: String?
    let exercises: [WorkoutExercise]
}

struct WorkoutExercise: Codable, Identifiable, Equatable {
    var id: String { name + (reps ?? "") + "\(sets ?? 0)" }
    let name: String
    let sets: Int?
    let reps: String?
    let muscleGroup: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, notes
        case muscleGroup = "muscle_group"
    }
}

// MARK: - Workout Search Result

struct WorkoutSearchResult: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let duration: String?
    let exerciseCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, duration
        case exerciseCount = "exercise_count"
    }
}

// MARK: - Stream Request

struct ChatStreamRequest: Codable {
    let message: String
    let sessionId: String?
    let context: ChatStreamContext?

    enum CodingKeys: String, CodingKey {
        case message
        case sessionId = "session_id"
        case context
    }
}

struct ChatStreamContext: Codable {
    let currentPage: String?
    let selectedWorkoutId: String?
    let selectedDate: String?

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case selectedWorkoutId = "selected_workout_id"
        case selectedDate = "selected_date"
    }
}

// MARK: - Rate Limit Info

struct RateLimitInfo: Equatable {
    let usage: Int
    let limit: Int
}
```

- [ ] **Step 2: Write tests for SSE event model equality and tool call display names**

Create `AmakaFlowCompanion/AmakaFlowCompanionTests/ChatStreamServiceTests.swift` with initial model tests:

```swift
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
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AmakaFlowCompanionTests/ChatStreamServiceTests 2>&1 | tail -20`

Expected: All 6 tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Models/ChatStreamModels.swift AmakaFlowCompanion/AmakaFlowCompanionTests/ChatStreamServiceTests.swift
git commit -m "feat(AMA-1410): Add SSE streaming models — events, stages, tool calls, workout types"
```

---

## Task 2: SSE Parser + ChatStreamService

**Files:**
- Create: `AmakaFlow/Services/ChatStreamService.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/ChatStreamServiceTests.swift`

- [ ] **Step 1: Write SSE parsing tests**

Add to `ChatStreamServiceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AmakaFlowCompanionTests/ChatStreamServiceTests 2>&1 | tail -20`

Expected: FAIL — `SSEParser` not defined.

- [ ] **Step 3: Implement ChatStreamService with SSE parser**

Create `AmakaFlow/Services/ChatStreamService.swift`:

```swift
//
//  ChatStreamService.swift
//  AmakaFlow
//
//  SSE streaming client for AI Coach chat (AMA-1410)
//  Connects to POST /chat/stream and yields parsed SSE events.
//

import Foundation

// MARK: - SSE Parser

enum SSEParser {
    /// Parse a single SSE event block (between double newlines) into an SSEEvent.
    static func parse(block: String) -> SSEEvent? {
        var eventType = ""
        var dataStr = ""

        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            if lineStr.hasPrefix("event:") {
                eventType = lineStr.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if lineStr.hasPrefix("data:") {
                let value = String(lineStr.dropFirst(5))
                let payload = value.hasPrefix(" ") ? String(value.dropFirst(1)) : value
                if dataStr.isEmpty {
                    dataStr = payload
                } else {
                    dataStr += "\n" + payload
                }
            }
        }

        guard !eventType.isEmpty, !dataStr.isEmpty,
              let data = dataStr.data(using: .utf8) else {
            return nil
        }

        return decodeEvent(type: eventType, data: data)
    }

    /// Split a buffer into complete SSE blocks and a remainder (incomplete trailing data).
    static func splitBuffer(_ buffer: String) -> (blocks: [String], remainder: String) {
        let normalized = buffer
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
        let remainder = parts.last ?? ""
        let blocks = parts.dropLast().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return (blocks, remainder)
    }

    private static func decodeEvent(type: String, data: Data) -> SSEEvent? {
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            switch type {
            case "message_start":
                guard let sessionId = json["session_id"] as? String else { return nil }
                let traceId = json["trace_id"] as? String
                return .messageStart(sessionId: sessionId, traceId: traceId)

            case "content_delta":
                guard let text = json["text"] as? String else { return nil }
                return .contentDelta(text: text)

            case "function_call":
                guard let id = json["id"] as? String,
                      let name = json["name"] as? String else { return nil }
                return .functionCall(id: id, name: name)

            case "function_result":
                guard let toolUseId = json["tool_use_id"] as? String,
                      let name = json["name"] as? String,
                      let result = json["result"] as? String else { return nil }
                return .functionResult(toolUseId: toolUseId, name: name, result: result)

            case "stage":
                guard let stageStr = json["stage"] as? String,
                      let stage = ChatStage(rawValue: stageStr),
                      let message = json["message"] as? String else { return nil }
                return .stage(stage: stage, message: message)

            case "heartbeat":
                guard let status = json["status"] as? String else { return nil }
                let toolName = json["tool_name"] as? String
                let elapsed = json["elapsed_seconds"] as? Double
                return .heartbeat(status: status, toolName: toolName, elapsedSeconds: elapsed)

            case "message_end":
                guard let sessionId = json["session_id"] as? String else { return nil }
                let tokensUsed = json["tokens_used"] as? Int
                let latencyMs = json["latency_ms"] as? Int
                return .messageEnd(sessionId: sessionId, tokensUsed: tokensUsed, latencyMs: latencyMs)

            case "error":
                guard let errorType = json["type"] as? String,
                      let message = json["message"] as? String else { return nil }
                let usage = json["usage"] as? Int
                let limit = json["limit"] as? Int
                return .error(type: errorType, message: message, usage: usage, limit: limit)

            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}

// MARK: - Chat Stream Service

protocol ChatStreamProviding {
    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error>
}

class ChatStreamService: ChatStreamProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let chatURL = AppEnvironment.current.chatAPIURL
                    guard let url = URL(string: "\(chatURL)/chat/stream") else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                        }
                        continuation.finish(throwing: ChatStreamError.httpError(
                            statusCode: httpResponse.statusCode, body: body
                        ))
                        return
                    }

                    var buffer = ""
                    for try await line in bytes.lines {
                        buffer += line + "\n"

                        // Check for double newline (event boundary)
                        // URLSession.bytes.lines strips newlines, so we reconstruct them.
                        // A blank line from the server means event boundary.
                        if line.isEmpty {
                            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty, let event = SSEParser.parse(block: trimmed) {
                                continuation.yield(event)
                            }
                            buffer = ""
                        }
                    }

                    // Process any remaining buffer
                    let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let event = SSEParser.parse(block: trimmed) {
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch {
                    if Task.isCancelled { return }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

enum ChatStreamError: LocalizedError {
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "Chat API error: \(code) — \(body)"
        }
    }
}

// MARK: - Mock for Testing

class MockChatStreamService: ChatStreamProviding {
    var eventsToYield: [SSEEvent] = []
    var errorToThrow: Error?
    var streamCalled = false

    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error> {
        streamCalled = true
        let events = eventsToYield
        let error = errorToThrow
        return AsyncThrowingStream { continuation in
            Task {
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AmakaFlowCompanionTests/ChatStreamServiceTests 2>&1 | tail -20`

Expected: All 17 tests pass (6 model + 11 parser tests).

- [ ] **Step 5: Commit**

```bash
cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Services/ChatStreamService.swift AmakaFlowCompanion/AmakaFlowCompanionTests/ChatStreamServiceTests.swift
git commit -m "feat(AMA-1410): Add ChatStreamService — SSE parser and streaming client"
```

---

## Task 3: Update ChatMessage Model for Streaming

**Files:**
- Modify: `AmakaFlow/ViewModels/CoachViewModel.swift` (ChatMessage struct lives here)
- Modify: `AmakaFlow/Models/CoachModels.swift`

- [ ] **Step 1: Rewrite ChatMessage to support streaming state**

Replace the `ChatMessage` and `ChatRole` at the bottom of `AmakaFlow/ViewModels/CoachViewModel.swift` (lines 99–120) with:

```swift
// MARK: - Chat Message Model

class ChatMessage: Identifiable, ObservableObject {
    let id: UUID
    let role: ChatRole
    @Published var content: String
    let timestamp: Date
    @Published var toolCalls: [ChatToolCall]
    @Published var completedStages: [ChatStage]
    @Published var currentStage: ChatStage?
    @Published var workoutData: GeneratedWorkout?
    @Published var searchResults: [WorkoutSearchResult]?
    @Published var tokensUsed: Int?
    @Published var latencyMs: Int?
    @Published var isStreaming: Bool

    // Keep backward compat for suggestions/actionItems from non-streaming responses
    let suggestions: [CoachSuggestion]?
    let actionItems: [CoachActionItem]?

    init(
        role: ChatRole,
        content: String,
        suggestions: [CoachSuggestion]? = nil,
        actionItems: [CoachActionItem]? = nil,
        isStreaming: Bool = false
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.toolCalls = []
        self.completedStages = []
        self.currentStage = nil
        self.workoutData = nil
        self.searchResults = nil
        self.tokensUsed = nil
        self.latencyMs = nil
        self.isStreaming = isStreaming
        self.suggestions = suggestions
        self.actionItems = actionItems
    }
}

enum ChatRole {
    case user
    case assistant
}
```

- [ ] **Step 2: Update CoachChatView references**

In `AmakaFlow/Views/CoachChatView.swift`, change the `ForEach` on line 31 from:

```swift
ForEach(viewModel.messages) { message in
```

to:

```swift
ForEach(viewModel.messages) { message in
```

No change needed — `ForEach` works with `Identifiable`. But we need to change line 50 from:

```swift
.onChange(of: viewModel.messages.count) { _ in
```

This stays the same. The key change is that `ChatMessage` is now a `class` (ObservableObject), so SwiftUI will observe `@Published` property changes on each message for live streaming updates.

- [ ] **Step 3: Run existing tests to ensure nothing breaks**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`

Expected: All existing tests pass. No tests currently test ChatMessage directly.

- [ ] **Step 4: Commit**

```bash
cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/ViewModels/CoachViewModel.swift
git commit -m "refactor(AMA-1410): Make ChatMessage observable class for streaming updates"
```

---

## Task 4: Rewrite CoachViewModel for Streaming

**Files:**
- Modify: `AmakaFlow/ViewModels/CoachViewModel.swift`
- Modify: `AmakaFlow/DependencyInjection/AppDependencies.swift`
- Test: `AmakaFlowCompanion/AmakaFlowCompanionTests/CoachViewModelStreamingTests.swift`

- [ ] **Step 1: Add ChatStreamService to AppDependencies**

In `AmakaFlow/DependencyInjection/AppDependencies.swift`, add to the struct:

```swift
let chatStreamService: ChatStreamProviding
```

Update `static let live`:
```swift
@MainActor
static let live = AppDependencies(
    apiService: APIService.shared,
    pairingService: PairingService.shared,
    audioService: AudioCueManager(),
    progressStore: LiveProgressStore.shared,
    watchSession: LiveWatchSession.shared,
    chatStreamService: ChatStreamService()
)
```

Update `static let mock`:
```swift
@MainActor
static let mock = AppDependencies(
    apiService: MockAPIService(),
    pairingService: MockPairingService(),
    audioService: MockAudioService(),
    progressStore: MockProgressStore(),
    watchSession: MockWatchSession(),
    chatStreamService: MockChatStreamService()
)
```

Update `static let fixture`:
```swift
@MainActor
static let fixture = AppDependencies(
    apiService: FixtureAPIService(),
    pairingService: PairingService.shared,
    audioService: AudioCueManager(),
    progressStore: LiveProgressStore.shared,
    watchSession: MockWatchSession(),
    chatStreamService: MockChatStreamService()
)
```

- [ ] **Step 2: Write ViewModel streaming tests**

Create `AmakaFlowCompanion/AmakaFlowCompanionTests/CoachViewModelStreamingTests.swift`:

```swift
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AmakaFlowCompanionTests/CoachViewModelStreamingTests 2>&1 | tail -20`

Expected: FAIL — `CoachViewModel` doesn't have streaming methods yet.

- [ ] **Step 4: Rewrite CoachViewModel for streaming**

Replace `AmakaFlow/ViewModels/CoachViewModel.swift` entirely:

```swift
//
//  CoachViewModel.swift
//  AmakaFlow
//
//  ViewModel for AI coach chat with SSE streaming (AMA-1410)
//

import Foundation
import Combine

@MainActor
class CoachViewModel: ObservableObject {
    // MARK: - Published State

    @Published var messages: [ChatMessage] = []
    @Published var isStreaming: Bool = false
    @Published var currentStage: ChatStage? = nil
    @Published var completedStages: [ChatStage] = []
    @Published var errorMessage: String? = nil
    @Published var rateLimitInfo: RateLimitInfo? = nil
    @Published var sessionId: String? {
        didSet { persistSessionId() }
    }

    // Fatigue (kept from original)
    @Published var fatigueAdvice: FatigueAdvice?
    @Published var isLoadingAdvice = false

    // MARK: - Private

    private let dependencies: AppDependencies
    private var streamTask: Task<Void, Never>?

    private static let sessionIdKey = "coach_chat_session_id"

    // MARK: - Init

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
        self.sessionId = UserDefaults.standard.string(forKey: Self.sessionIdKey)
    }

    // MARK: - Send Message (Streaming)

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        // Add user message
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        // Create assistant placeholder
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)

        isStreaming = true
        errorMessage = nil
        currentStage = nil
        completedStages = []

        // Get auth token
        guard let token = dependencies.pairingService.getToken() else {
            assistantMessage.content = "Not authenticated. Please pair your device first."
            assistantMessage.isStreaming = false
            isStreaming = false
            return
        }

        let request = ChatStreamRequest(
            message: trimmed,
            sessionId: sessionId,
            context: nil
        )

        let stream = dependencies.chatStreamService.stream(request: request, token: token)

        do {
            for try await event in stream {
                processEvent(event, message: assistantMessage)
            }
        } catch {
            if !Task.isCancelled {
                // Remove empty assistant message on error if no content received
                if assistantMessage.content.isEmpty {
                    if let idx = messages.lastIndex(where: { $0.id == assistantMessage.id }) {
                        messages.remove(at: idx)
                    }
                    // Also remove the user message
                    if let idx = messages.lastIndex(where: { $0.id == userMessage.id }) {
                        messages.remove(at: idx)
                    }
                }
                errorMessage = error.localizedDescription
            }
        }

        assistantMessage.isStreaming = false
        isStreaming = false
    }

    // MARK: - Process SSE Event

    private func processEvent(_ event: SSEEvent, message: ChatMessage) {
        switch event {
        case .messageStart(let sid, _):
            if sessionId != sid {
                sessionId = sid
            }

        case .contentDelta(let text):
            message.content += text

        case .functionCall(let id, let name):
            let toolCall = ChatToolCall(id: id, name: name, status: .running)
            message.toolCalls.append(toolCall)

        case .functionResult(let toolUseId, _, let result):
            if let idx = message.toolCalls.firstIndex(where: { $0.id == toolUseId }) {
                message.toolCalls[idx].status = .completed
                message.toolCalls[idx].result = result
            }
            // Try to parse workout data from result
            tryParseWorkoutData(result: result, message: message)

        case .stage(let stage, _):
            if let current = currentStage, current != stage {
                completedStages.append(current)
            }
            currentStage = stage
            if stage == .complete {
                completedStages.append(stage)
                currentStage = nil
            }

        case .heartbeat(_, _, let elapsed):
            // Update elapsed time on active tool call
            if let idx = message.toolCalls.lastIndex(where: { $0.status == .running }) {
                message.toolCalls[idx].elapsedSeconds = elapsed
            }

        case .messageEnd(_, let tokens, let latency):
            message.tokensUsed = tokens
            message.latencyMs = latency

        case .error(let type, let errorMsg, let usage, let limit):
            errorMessage = errorMsg
            if type == "rate_limit_exceeded", let usage, let limit {
                rateLimitInfo = RateLimitInfo(usage: usage, limit: limit)
            }
        }
    }

    // MARK: - Parse Workout Data from Tool Result

    private func tryParseWorkoutData(result: String, message: ChatMessage) {
        guard let data = result.data(using: .utf8) else { return }
        let decoder = JSONDecoder()

        // Try GeneratedWorkout
        if let workout = try? decoder.decode(GeneratedWorkout.self, from: data),
           !workout.exercises.isEmpty {
            message.workoutData = workout
            return
        }

        // Try nested in a wrapper
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let workoutsArray = json["workouts"] as? [[String: Any]],
           let firstWorkout = workoutsArray.first,
           let workoutData = try? JSONSerialization.data(withJSONObject: firstWorkout),
           let workout = try? decoder.decode(GeneratedWorkout.self, from: workoutData),
           !workout.exercises.isEmpty {
            message.workoutData = workout
        }
    }

    // MARK: - Session Management

    func startNewChat() {
        streamTask?.cancel()
        messages.removeAll()
        sessionId = nil
        errorMessage = nil
        currentStage = nil
        completedStages = []
        rateLimitInfo = nil
    }

    func cancelStream() {
        streamTask?.cancel()
    }

    private func persistSessionId() {
        if let sessionId {
            UserDefaults.standard.set(sessionId, forKey: Self.sessionIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.sessionIdKey)
        }
    }

    // MARK: - Fatigue Advice (kept from original)

    func loadFatigueAdvice() async {
        isLoadingAdvice = true
        do {
            fatigueAdvice = try await dependencies.apiService.getFatigueAdvice()
        } catch {
            print("[CoachViewModel] loadFatigueAdvice failed: \(error)")
        }
        isLoadingAdvice = false
    }
}

// MARK: - Chat Message Model

class ChatMessage: Identifiable, ObservableObject {
    let id: UUID
    let role: ChatRole
    @Published var content: String
    let timestamp: Date
    @Published var toolCalls: [ChatToolCall]
    @Published var completedStages: [ChatStage]
    @Published var currentStage: ChatStage?
    @Published var workoutData: GeneratedWorkout?
    @Published var searchResults: [WorkoutSearchResult]?
    @Published var tokensUsed: Int?
    @Published var latencyMs: Int?
    @Published var isStreaming: Bool

    let suggestions: [CoachSuggestion]?
    let actionItems: [CoachActionItem]?

    init(
        role: ChatRole,
        content: String,
        suggestions: [CoachSuggestion]? = nil,
        actionItems: [CoachActionItem]? = nil,
        isStreaming: Bool = false
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.toolCalls = []
        self.completedStages = []
        self.currentStage = nil
        self.workoutData = nil
        self.searchResults = nil
        self.tokensUsed = nil
        self.latencyMs = nil
        self.isStreaming = isStreaming
        self.suggestions = suggestions
        self.actionItems = actionItems
    }
}

enum ChatRole {
    case user
    case assistant
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AmakaFlowCompanionTests/CoachViewModelStreamingTests 2>&1 | tail -20`

Expected: All 8 tests pass.

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`

Expected: All tests pass. Fix any compilation issues from ChatMessage changing from struct to class.

- [ ] **Step 7: Commit**

```bash
cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/ViewModels/CoachViewModel.swift AmakaFlow/DependencyInjection/AppDependencies.swift AmakaFlowCompanion/AmakaFlowCompanionTests/CoachViewModelStreamingTests.swift
git commit -m "feat(AMA-1410): Rewrite CoachViewModel for SSE streaming with session persistence"
```

---

## Task 5: New View Components — ToolCallCard, WorkoutPreviewCard, StageIndicator

**Files:**
- Create: `AmakaFlow/Views/Components/ToolCallCard.swift`
- Create: `AmakaFlow/Views/Components/WorkoutPreviewCard.swift`
- Create: `AmakaFlow/Views/Components/StageIndicator.swift`

- [ ] **Step 1: Create ToolCallCard**

Create `AmakaFlow/Views/Components/ToolCallCard.swift`:

```swift
//
//  ToolCallCard.swift
//  AmakaFlow
//
//  Inline tool call visualization for coach chat (AMA-1410)
//

import SwiftUI

struct ToolCallCard: View {
    let toolCall: ChatToolCall

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: toolCall.iconName)
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.accentBlue)

            Text(toolCall.displayName)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer()

            switch toolCall.status {
            case .pending, .running:
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Theme.Colors.accentBlue)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.accentGreen)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.accentRed)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surfaceElevated)
        .cornerRadius(Theme.CornerRadius.md)
    }
}
```

- [ ] **Step 2: Create WorkoutPreviewCard**

Create `AmakaFlow/Views/Components/WorkoutPreviewCard.swift`:

```swift
//
//  WorkoutPreviewCard.swift
//  AmakaFlow
//
//  Inline generated workout preview for coach chat (AMA-1410)
//

import SwiftUI

struct WorkoutPreviewCard: View {
    let workout: GeneratedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header
            HStack {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(Theme.Colors.accentBlue)
                    .font(.system(size: 14))

                Text(workout.name ?? "Generated Workout")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            // Metadata
            if workout.duration != nil || workout.difficulty != nil {
                HStack(spacing: Theme.Spacing.sm) {
                    if let duration = workout.duration {
                        Text(duration)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    if workout.duration != nil && workout.difficulty != nil {
                        Text("·")
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    if let difficulty = workout.difficulty {
                        Text(difficulty)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }

            Divider()
                .background(Theme.Colors.borderLight)

            // Exercises
            ForEach(Array(workout.exercises.enumerated()), id: \.offset) { index, exercise in
                HStack {
                    Text(exercise.name)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    if let sets = exercise.sets, let reps = exercise.reps {
                        Text("\(sets)×\(reps)")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.accentBlue)
                    }
                }
                .opacity(0)
                .animation(.easeOut(duration: 0.2).delay(Double(index) * 0.08), value: true)
                .onAppear {} // triggers animation
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.lg)
    }
}
```

- [ ] **Step 3: Create StageIndicator**

Create `AmakaFlow/Views/Components/StageIndicator.swift`:

```swift
//
//  StageIndicator.swift
//  AmakaFlow
//
//  Horizontal stage progress indicator for coach chat (AMA-1410)
//

import SwiftUI

struct StageIndicator: View {
    let completedStages: [ChatStage]
    let currentStage: ChatStage?

    private var visibleStages: [ChatStage] {
        ChatStage.allCases.filter { $0 != .complete }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(visibleStages, id: \.self) { stage in
                HStack(spacing: Theme.Spacing.xs) {
                    if completedStages.contains(stage) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.Colors.accentGreen)
                    } else if currentStage == stage {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(Theme.Colors.accentBlue)
                    } else {
                        Image(systemName: stage.iconName)
                            .font(.system(size: 9))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    Text(stage.displayName)
                        .font(.system(size: 10, weight: currentStage == stage ? .semibold : .regular))
                        .foregroundColor(
                            currentStage == stage ? Theme.Colors.accentBlue :
                            completedStages.contains(stage) ? Theme.Colors.textSecondary :
                            Theme.Colors.textTertiary
                        )
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xs)
    }
}
```

- [ ] **Step 4: Commit**

```bash
cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Views/Components/ToolCallCard.swift AmakaFlow/Views/Components/WorkoutPreviewCard.swift AmakaFlow/Views/Components/StageIndicator.swift
git commit -m "feat(AMA-1410): Add ToolCallCard, WorkoutPreviewCard, and StageIndicator components"
```

---

## Task 6: Rewrite CoachChatView for Streaming

**Files:**
- Modify: `AmakaFlow/Views/CoachChatView.swift`

- [ ] **Step 1: Rewrite CoachChatView with streaming UI**

Replace `AmakaFlow/Views/CoachChatView.swift` entirely:

```swift
//
//  CoachChatView.swift
//  AmakaFlow
//
//  AI coach chat interface with SSE streaming (AMA-1410)
//

import SwiftUI

struct CoachChatView: View {
    @StateObject private var viewModel = CoachViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fatigue advisor banner
                if let advice = viewModel.fatigueAdvice {
                    fatigueBanner(advice)
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            if viewModel.messages.isEmpty {
                                coachWelcome
                            }

                            ForEach(viewModel.messages) { message in
                                chatBubble(message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.isStreaming) { streaming in
                        if !streaming { scrollToBottom(proxy) }
                    }
                }

                // Stage indicator (visible during streaming)
                if viewModel.isStreaming, (viewModel.currentStage != nil || !viewModel.completedStages.isEmpty) {
                    StageIndicator(
                        completedStages: viewModel.completedStages,
                        currentStage: viewModel.currentStage
                    )
                }

                // Rate limit banner
                if let info = viewModel.rateLimitInfo {
                    rateLimitBanner(info)
                }

                // Error message
                if let error = viewModel.errorMessage, viewModel.rateLimitInfo == nil {
                    Text(error)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.accentRed)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xs)
                }

                // Input bar
                inputBar
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.startNewChat()
                    } label: {
                        Image(systemName: "plus.bubble")
                            .foregroundColor(Theme.Colors.accentBlue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: FatigueAdvisorView(viewModel: viewModel)) {
                        Image(systemName: "heart.text.square")
                            .foregroundColor(Theme.Colors.accentBlue)
                    }
                }
            }
            .task {
                await viewModel.loadFatigueAdvice()
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Welcome

    private var coachWelcome: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.accentBlue)

            Text("Your AI Coach")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Ask about training plans, recovery, or anything fitness related.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: Theme.Spacing.sm) {
                quickPromptButton("How should I train this week?")
                quickPromptButton("Am I overtraining?")
                quickPromptButton("Suggest a recovery day workout")
            }
        }
        .padding(Theme.Spacing.xl)
    }

    private func quickPromptButton(_ text: String) -> some View {
        Button {
            Task { await viewModel.sendMessage(text) }
        } label: {
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.accentBlue)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.accentBlue.opacity(0.1))
                .cornerRadius(Theme.CornerRadius.lg)
        }
        .disabled(viewModel.isStreaming)
    }

    // MARK: - Chat Bubble

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer() }

            if message.role == .assistant {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.accentBlue)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.accentBlue.opacity(0.15))
                    .cornerRadius(16)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.xs) {
                // Message content (markdown for assistant)
                if message.role == .assistant {
                    assistantBubbleContent(message)
                } else {
                    Text(message.content)
                        .font(Theme.Typography.body)
                        .foregroundColor(.white)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(Theme.CornerRadius.lg)
                }

                // Tool calls
                if !message.toolCalls.isEmpty {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(message.toolCalls) { toolCall in
                            ToolCallCard(toolCall: toolCall)
                        }
                    }
                }

                // Workout preview
                if let workout = message.workoutData {
                    WorkoutPreviewCard(workout: workout)
                }

                // Suggestion chips (from non-streaming responses)
                if message.role == .assistant, let suggestions = message.suggestions, !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(suggestions, id: \.stableId) { suggestion in
                                sourceChip(suggestion)
                            }
                        }
                    }
                }

                // Action items
                if message.role == .assistant, let actions = message.actionItems, !actions.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(actions, id: \.stableId) { item in
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.Colors.accentBlue)
                                Text(item.title)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.accentBlue)
                            }
                        }
                    }
                }

                Text(message.timestamp, style: .time)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    @ViewBuilder
    private func assistantBubbleContent(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !message.content.isEmpty {
                // Try markdown, fall back to plain text
                if let attributed = try? AttributedString(markdown: message.content) {
                    Text(attributed)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.md)
                } else {
                    Text(message.content)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.md)
                }
            }

            // Streaming indicator
            if message.isStreaming && message.content.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    TypingIndicator()
                    Text("Coach is thinking...")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.md)
            }
        }
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.lg)
    }

    private func sourceChip(_ suggestion: CoachSuggestion) -> some View {
        Button {
            Task { await viewModel.sendMessage(suggestion.text) }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: chipIcon(suggestion.type))
                    .font(.system(size: 10))
                Text(suggestion.text)
                    .font(Theme.Typography.footnote)
                    .lineLimit(1)
            }
            .foregroundColor(Theme.Colors.accentBlue)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.accentBlue.opacity(0.1))
            .cornerRadius(Theme.CornerRadius.md)
        }
    }

    private func chipIcon(_ type: SuggestionType?) -> String {
        switch type {
        case .workout: return "figure.run"
        case .recovery: return "bed.double.fill"
        case .nutrition: return "fork.knife"
        case .general, .none: return "lightbulb.fill"
        }
    }

    // MARK: - Fatigue Banner

    private func fatigueBanner(_ advice: FatigueAdvice) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(fatigueColor(advice.level))
                .frame(width: 10, height: 10)
            Text(advice.message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface)
    }

    private func fatigueColor(_ level: FatigueLevel) -> Color {
        switch level {
        case .low: return Theme.Colors.accentGreen
        case .moderate: return Theme.Colors.accentOrange
        case .high, .critical: return Theme.Colors.accentRed
        }
    }

    // MARK: - Rate Limit

    private func rateLimitBanner(_ info: RateLimitInfo) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(Theme.Colors.accentRed)
            Text("Rate limit reached (\(info.usage)/\(info.limit) messages)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.accentRed)
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.accentRed.opacity(0.1))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Ask your coach...", text: $inputText)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.lg)
                .focused($isInputFocused)
                .disabled(viewModel.isStreaming)

            Button {
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                inputText = ""
                Task { await viewModel.sendMessage(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(
                        inputText.isEmpty || viewModel.isStreaming
                        ? Theme.Colors.textTertiary
                        : Theme.Colors.accentBlue
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.Colors.accentBlue)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Fatigue Advisor View

struct FatigueAdvisorView: View {
    @ObservedObject var viewModel: CoachViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if viewModel.isLoadingAdvice {
                    ProgressView("Analyzing your fatigue levels...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xl)
                } else if let advice = viewModel.fatigueAdvice {
                    HStack {
                        Text("Fatigue Level")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text(advice.level.rawValue.capitalized)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(fatigueColor(advice.level))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(fatigueColor(advice.level).opacity(0.15))
                            .cornerRadius(Theme.CornerRadius.md)
                    }

                    Text(advice.message)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Recommendations")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        ForEach(advice.recommendations, id: \.self) { rec in
                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.Colors.accentGreen)
                                    .font(.system(size: 14))
                                Text(rec)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }

                    if let restDays = advice.suggestedRestDays {
                        HStack {
                            Image(systemName: "bed.double.fill")
                                .foregroundColor(Theme.Colors.accentBlue)
                            Text("Suggested rest days: \(restDays)")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.surface)
                        .cornerRadius(Theme.CornerRadius.lg)
                    }
                } else {
                    Text("No fatigue data available yet. Complete some workouts first.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xl)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Fatigue Advisor")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.fatigueAdvice == nil {
                await viewModel.loadFatigueAdvice()
            }
        }
    }

    private func fatigueColor(_ level: FatigueLevel) -> Color {
        switch level {
        case .low: return Theme.Colors.accentGreen
        case .moderate: return Theme.Colors.accentOrange
        case .high, .critical: return Theme.Colors.accentRed
        }
    }
}

#Preview {
    CoachChatView()
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild build -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`

Expected: Build succeeds.

- [ ] **Step 3: Run full test suite**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Views/CoachChatView.swift
git commit -m "feat(AMA-1410): Rewrite CoachChatView with streaming, tool cards, stages, markdown, and workout previews"
```

---

## Task 7: Update Existing Tests and Fix Any Compilation Issues

**Files:**
- Modify: Any existing test files that reference `ChatMessage` as a struct
- Modify: Any files that construct `AppDependencies` without `chatStreamService`

- [ ] **Step 1: Find and fix all AppDependencies construction sites**

Search for `AppDependencies(` in test files. Each one needs the new `chatStreamService:` parameter added. Add `chatStreamService: MockChatStreamService()` to every existing test that constructs `AppDependencies` manually.

Key files to check:
- `AmakaFlowCompanionTests/WorkoutsViewModelTests.swift`
- `AmakaFlowCompanionTests/Phase2ViewModelTests.swift`
- `AmakaFlowCompanionTests/FeedViewModelTests.swift`
- `AmakaFlowCompanionTests/ChallengesViewModelTests.swift`
- Any other file constructing `AppDependencies`

In each file, find:
```swift
let dependencies = AppDependencies(
    apiService: mockAPIService,
    pairingService: mockPairingService,
    audioService: MockAudioService(),
    progressStore: MockProgressStore(),
    watchSession: MockWatchSession()
)
```

Replace with:
```swift
let dependencies = AppDependencies(
    apiService: mockAPIService,
    pairingService: mockPairingService,
    audioService: MockAudioService(),
    progressStore: MockProgressStore(),
    watchSession: MockWatchSession(),
    chatStreamService: MockChatStreamService()
)
```

- [ ] **Step 2: Run full test suite to verify**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`

Expected: All tests pass with no compilation errors.

- [ ] **Step 3: Commit**

```bash
cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app
git add -A
git commit -m "fix(AMA-1410): Update existing tests for ChatStreamService DI parameter"
```

---

## Task 8: Final Integration Verification

- [ ] **Step 1: Run the full test suite one final time**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild test -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -40`

Expected: All tests pass, including the new ChatStreamServiceTests and CoachViewModelStreamingTests.

- [ ] **Step 2: Verify build for device target**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && xcodebuild build -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj -scheme AmakaFlowCompanion -destination generic/platform=iOS 2>&1 | tail -10`

Expected: Build succeeds for device target (catches any simulator-only issues).

- [ ] **Step 3: Review git log**

Run: `cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app && git log --oneline -10`

Expected: Clean commit history:
```
<hash> fix(AMA-1410): Update existing tests for ChatStreamService DI parameter
<hash> feat(AMA-1410): Rewrite CoachChatView with streaming, tool cards, stages, markdown, and workout previews
<hash> feat(AMA-1410): Add ToolCallCard, WorkoutPreviewCard, and StageIndicator components
<hash> feat(AMA-1410): Rewrite CoachViewModel for SSE streaming with session persistence
<hash> feat(AMA-1410): Add ChatStreamService — SSE parser and streaming client
<hash> feat(AMA-1410): Add SSE streaming models — events, stages, tool calls, workout types
<hash> docs(AMA-1410): Design spec for SSE streaming chat parity
```

- [ ] **Step 4: Final commit — remove old unused coach endpoint from APIService (cleanup)**

In `AmakaFlow/Services/APIService.swift`, the `sendCoachMessage` method (around line 1418) is no longer used by the ViewModel. Keep it for now — it's part of the `APIServiceProviding` protocol and may be used by other code. Add a `// Legacy: replaced by ChatStreamService for streaming (AMA-1410)` comment above it.

```bash
cd /Volumes/SSD1/openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Services/APIService.swift
git commit -m "chore(AMA-1410): Mark legacy coach endpoint — replaced by ChatStreamService"
```
