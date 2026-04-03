# AMA-1410: AI Coach Chat — SSE Streaming Parity

**Ticket:** AMA-1410
**Date:** 2026-04-02
**Status:** Design approved, ready for implementation planning

## Summary

Upgrade the iOS AI Coach chat from a simple request/response model to full SSE streaming parity with the web app. The iOS app will connect to the same `POST /chat/stream` endpoint (port 8005) that the web uses, enabling live text streaming, tool call visualization, progress stages, workout card previews, markdown rendering, and session persistence.

## Goals

1. Stream assistant responses live (text appears as it's generated)
2. Visualize tool calls inline (search, create, history lookups)
3. Show progress stages (Perplexity-style: analyzing → researching → creating)
4. Render workout cards when the AI generates/searches workouts
5. Render assistant messages as markdown
6. Persist chat sessions across app launches
7. Support abort/cancel of in-flight streams

## Non-Goals

- Voice input (separate ticket)
- Full 25-tool visualization (use generic card for non-core tools)
- TTS/voice responses
- Beta feedback widget
- Cross-session search

## Architecture

### Approach: URLSession SSE Streaming

Use `URLSession.bytes(for:)` (iOS 15+) to stream the SSE response body. Parse events incrementally. No third-party dependencies.

```
CoachChatView
    └─ CoachViewModel (ObservableObject, @MainActor)
         ├─ ChatStreamService (SSE client)
         │    └─ URLSession.bytes(for:) → AsyncThrowingStream<SSEEvent>
         └─ State: messages, currentStage, toolCalls, sessionId, etc.
```

### SSE Event Flow

The backend sends these SSE events (same as web):

| Event | iOS Handling |
|-------|-------------|
| `message_start` | Store `session_id`, create assistant message placeholder |
| `content_delta` | Append `text` to current assistant message content |
| `function_call` | Add tool call card (name, spinner) to current message |
| `function_result` | Update tool call status to completed, parse workout data if present |
| `stage` | Update stage indicator (analyzing/researching/searching/creating/complete) |
| `heartbeat` | Reset connection timeout, update elapsed time on active tool |
| `message_end` | Finalize message, store `tokens_used`/`latency_ms`, clear streaming state |
| `error` | Display error, handle rate limit (type: `rate_limit_exceeded`) |

## Data Models

### SSE Event Types

```swift
enum SSEEvent {
    case messageStart(sessionId: String, traceId: String?)
    case contentDelta(text: String)
    case functionCall(id: String, name: String)
    case functionResult(toolUseId: String, name: String, result: String)
    case stage(stage: ChatStage, message: String)
    case heartbeat(status: String, toolName: String?, elapsedSeconds: Double?)
    case messageEnd(sessionId: String, tokensUsed: Int?, latencyMs: Int?, pendingImports: [PendingImport]?)
    case error(type: String, message: String, usage: Int?, limit: Int?)
}
```

### ChatStage

```swift
enum ChatStage: String, Codable, CaseIterable {
    case analyzing
    case researching
    case searching
    case creating
    case complete
}
```

### Enhanced ChatMessage

```swift
struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    var content: String              // Mutable for streaming appends
    let timestamp: Date
    var toolCalls: [ToolCall]        // Inline tool visualizations
    var stages: [ChatStage]          // Completed stages
    var currentStage: ChatStage?     // Active stage
    var workoutData: GeneratedWorkout?  // Parsed workout from tool result
    var searchResults: [WorkoutSearchResult]?
    var tokensUsed: Int?
    var latencyMs: Int?
    var isStreaming: Bool             // True while content is arriving
}
```

### ToolCall

```swift
struct ToolCall: Identifiable {
    let id: String
    let name: String
    var status: ToolCallStatus       // pending → running → completed/error
    var result: String?
    var elapsedSeconds: Double?

    enum ToolCallStatus {
        case pending, running, completed, error
    }

    /// Human-readable display name
    var displayName: String {
        switch name {
        case "search_workout_library": return "Searching workouts"
        case "create_workout_plan": return "Creating workout plan"
        case "get_workout_history": return "Looking up history"
        case "get_calendar_events": return "Checking calendar"
        default: return "Working"
        }
    }

    /// SF Symbol for the tool
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
```

### GeneratedWorkout

```swift
struct GeneratedWorkout: Codable {
    let name: String?
    let duration: String?
    let difficulty: String?
    let exercises: [WorkoutExercise]
}

struct WorkoutExercise: Codable, Identifiable {
    var id: String { name }
    let name: String
    let sets: Int?
    let reps: String?
    let muscleGroup: String?
    let notes: String?
}

struct WorkoutSearchResult: Codable, Identifiable {
    let id: String
    let name: String
    let duration: String?
    let exerciseCount: Int?
}
```

### Chat Stream Request

```swift
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
```

## Components

### 1. ChatStreamService (New)

**File:** `AmakaFlow/Services/ChatStreamService.swift`

Responsibilities:
- Build authenticated POST request to `{chatAPIURL}/chat/stream`
- Stream response bytes via `URLSession.bytes(for:)`
- Parse SSE format: `event: <type>\ndata: <json>\n\n`
- Yield `SSEEvent` values via `AsyncThrowingStream`
- Support cancellation via `Task` cancellation

Key implementation detail — SSE parsing:
```
1. Read bytes into a String buffer
2. Split on "\n\n" (double newline = event boundary)
3. For each complete event block:
   a. Extract "event:" line → event type
   b. Extract "data:" line(s) → JSON payload
   c. Decode into SSEEvent enum case
4. Keep incomplete trailing data in buffer for next read
```

### 2. CoachViewModel (Rewrite)

**File:** `AmakaFlow/ViewModels/CoachViewModel.swift`

New responsibilities:
- `sendMessage(_ text:)` — Creates user message, opens stream, processes events
- `cancelStream()` — Cancels in-flight stream task
- `startNewChat()` — Clears messages and session ID
- Session ID persisted to `UserDefaults` (key: `coach_chat_session_id`)
- Messages stored in-memory (session persistence = server-side via session ID)
- Handles concurrent message guard (disable send while streaming)

State:
```swift
@Published var messages: [ChatMessage] = []
@Published var isStreaming: Bool = false
@Published var currentStage: ChatStage? = nil
@Published var completedStages: [ChatStage] = []
@Published var errorMessage: String? = nil
@Published var rateLimitInfo: RateLimitInfo? = nil
@Published var sessionId: String? // Persisted to UserDefaults

// Existing (kept)
@Published var fatigueAdvice: FatigueAdvice?
@Published var isLoadingAdvice: Bool = false
```

### 3. CoachChatView (Enhance)

**File:** `AmakaFlow/Views/CoachChatView.swift`

Changes:
- **Streaming bubble**: Assistant message bubble content updates live as `content` changes
- **Tool call cards**: Below message text, show `ToolCallCard` for each tool call
- **Stage indicator**: Above input bar during streaming, shows completed + active stage
- **Workout cards**: After tool result with workout data, render `WorkoutPreviewCard`
- **Markdown**: Use `Text(AttributedString(markdown: content))` for assistant messages
- **New chat button**: Toolbar item to clear session
- **Animated typing indicator**: Three-dot animation instead of ProgressView

### 4. ToolCallCard (New Component)

**File:** `AmakaFlow/Views/Components/ToolCallCard.swift`

Compact inline card:
```
┌─────────────────────────────┐
│ 🔍 Searching workouts...  ⟳ │  (spinner while running)
└─────────────────────────────┘

┌─────────────────────────────┐
│ 🔍 Searching workouts    ✓  │  (checkmark when done)
└─────────────────────────────┘
```

- SF Symbol icon (from `ToolCall.iconName`)
- Display name (from `ToolCall.displayName`)
- Status indicator: spinner (running), checkmark (completed), xmark (error)
- Surface background with rounded corners
- Subtle entrance animation

### 5. WorkoutPreviewCard (New Component)

**File:** `AmakaFlow/Views/Components/WorkoutPreviewCard.swift`

Displays a generated or searched workout inline in chat:
```
┌──────────────────────────────┐
│ 💪 Upper Body Push Day       │
│ 45 min · Intermediate        │
│ ─────────────────────────── │
│ Bench Press    4×8           │
│ OHP            3×10          │
│ Incline DB     3×12          │
│ Lateral Raise  3×15          │
└──────────────────────────────┘
```

- Workout name, duration, difficulty in header
- Exercise list with sets × reps
- Surface background, rounded corners
- Staggered entrance animation (80ms per exercise, matching web)

### 6. StageIndicator (New Component)

**File:** `AmakaFlow/Views/Components/StageIndicator.swift`

Horizontal progress bar showing AI pipeline stages:
```
✓ Analyzing  ✓ Researching  ⟳ Creating
```

- Each stage: icon + label
- Completed stages: checkmark + muted text
- Active stage: spinner + highlighted text
- Future stages: dimmed
- Compact height (~28pt), sits above input bar during streaming

## Session Management

- **Session ID**: Stored in `UserDefaults` under key `coach_chat_session_id`
- **On launch**: If session ID exists, load it (server has the history)
- **New chat**: Clear session ID from UserDefaults, clear local messages array
- **Message history**: Not loaded from server on launch (start fresh UI, but server remembers context). Future enhancement could add history loading.
- **On `message_start`**: If server returns a different session_id, update local storage

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Network error | Show inline error, keep messages, allow retry |
| 401 Unauthorized | Trigger token refresh via PairingService, retry once |
| Rate limit (429 or SSE error event) | Show rate limit banner, disable input |
| Stream interrupted | Show "Connection lost" error, keep partial message |
| Malformed SSE | Log warning, skip event, continue stream |
| Task cancelled (user navigates away) | Clean cancel, keep any partial content |

## Auth Integration

Uses existing `PairingService` JWT token. The `ChatStreamService` will:
1. Get token from `PairingService.shared.token`
2. Set `Authorization: Bearer <token>` header
3. On 401, call `PairingService.shared.refreshToken()` and retry once

The backend already supports Mobile Pairing JWT (HS256, audience: `ios_companion`).

## Files Changed Summary

| File | Action | Lines (est.) |
|------|--------|-------------|
| `Services/ChatStreamService.swift` | New | ~120 |
| `Models/CoachModels.swift` | Expand | +80 (SSE types, ToolCall, Workout) |
| `ViewModels/CoachViewModel.swift` | Rewrite | ~150 (was 97) |
| `Views/CoachChatView.swift` | Enhance | ~500 (was 407) |
| `Views/Components/ToolCallCard.swift` | New | ~50 |
| `Views/Components/WorkoutPreviewCard.swift` | New | ~70 |
| `Views/Components/StageIndicator.swift` | New | ~60 |
| `DependencyInjection/AppDependencies.swift` | Update | +5 |
| `DependencyInjection/APIServiceProviding.swift` | Update | +3 (protocol) |

**Total estimated new/changed:** ~550 lines new, ~250 lines modified

## Testing Strategy

### Unit Tests
- `ChatStreamServiceTests` — SSE parsing with mock data (event blocks → SSEEvent enum)
- `CoachViewModelTests` — State transitions on each event type, error handling, session persistence

### Integration Tests
- Verify `ChatStreamService` connects to mock SSE server and receives events correctly

### E2E / Manual
- Send a message, verify text streams live
- Verify tool call cards appear and animate
- Verify workout cards render when AI generates a workout
- Verify stage indicator progression
- Verify rate limit banner on 429
- Verify new chat clears state
- Verify session persists across app restart (server remembers context)

## Dependencies

- **iOS 15+** (for `URLSession.bytes(for:)`)
- **No new third-party dependencies**
- **Backend**: No changes needed — iOS will use the existing `POST /chat/stream` endpoint
