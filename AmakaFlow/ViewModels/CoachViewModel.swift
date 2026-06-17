//
//  CoachViewModel.swift
//  AmakaFlow
//
//  ViewModel for AI coach chat with SSE streaming (AMA-1410)
//

import Foundation
import Combine

/// AMA-2123: session-scoped coach store hoisted above tab shell.
typealias CoachSessionStore = CoachViewModel

@MainActor
class CoachViewModel: ObservableObject {
    // MARK: - Published State

    @Published var messages: [ChatMessage] = []
    @Published var isStreaming: Bool = false
    @Published var currentStage: ChatStage? = nil
    @Published var completedStages: [ChatStage] = []
    /// AMA-1803 P2: typed CTAError replaces `errorMessage: String?` so
    /// the View can render Retry only when the failure is transient,
    /// surface server `error_code` (when the SSE `.error` event carried
    /// a `type` field), and produce a Sentry breadcrumb correlated to
    /// AMA-1805 by request_id.
    @Published var error: CTAError? = nil
    @Published var rateLimitInfo: RateLimitInfo? = nil

    /// AMA-1803 P2: cached so the Retry button on the failure banner
    /// can re-send without the user having to type again.
    private var lastSentMessageText: String? = nil
    @Published var scrollTrigger = UUID()
    @Published var isLoadingMessages = false
    @Published var didRestoreConversation = false
    @Published var restoreError: CoachSessionError? = nil
    @Published var sessionId: String? {
        didSet { persistSessionId() }
    }

    // Fatigue (kept from original)
    @Published var fatigueAdvice: FatigueAdvice?
    @Published var isLoadingAdvice = false

    // MARK: - Private

    private let dependencies: AppDependencies
    private var streamTask: Task<Void, Never>?
    private var profileSubscription: AnyCancellable?
    private var boundSessionUserId: String?

    private func sessionStorageKey(for userId: String) -> String {
        DefaultsKey.coachSessionID(userID: userId)
    }

    private var sessionIdKey: String {
        sessionStorageKey(for: boundSessionUserId ?? "unknown")
    }

    // MARK: - Init

    init(dependencies: AppDependencies = .current) {
        self.dependencies = dependencies
        let initialUserId = dependencies.pairingService.userProfile?.id ?? "unknown"
        boundSessionUserId = initialUserId
        self.sessionId = UserDefaults.standard.string(forKey: sessionStorageKey(for: initialUserId))

        profileSubscription = dependencies.pairingService.userProfilePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.syncSessionIdForUserProfile(profile?.id)
            }
    }

    /// When Clerk hydrates after `App.init`, reload the per-user session id from storage.
    private func syncSessionIdForUserProfile(_ userId: String?) {
        let resolved = userId ?? "unknown"
        guard resolved != boundSessionUserId else { return }
        let previousUserId = boundSessionUserId ?? "unknown"
        let oldKey = sessionStorageKey(for: previousUserId)
        boundSessionUserId = resolved

        if messages.isEmpty, !isStreaming {
            sessionId = UserDefaults.standard.string(forKey: sessionIdKey)
        } else if previousUserId == "unknown",
                  let currentSessionId = sessionId,
                  resolved != "unknown" {
            // VM was built before auth resolved; migrate the in-memory session ID
            // to the real user's storage key so it survives the next app launch.
            UserDefaults.standard.removeObject(forKey: oldKey)
            UserDefaults.standard.set(currentSessionId, forKey: sessionIdKey)
        }
    }

    // MARK: - Session Restore (AMA-2123)

    func loadMessagesIfNeeded() async {
        guard messages.isEmpty, let sessionId, !isLoadingMessages else { return }
        guard let token = dependencies.pairingService.getToken() else { return }

        isLoadingMessages = true
        restoreError = nil
        defer { isLoadingMessages = false }

        do {
            let restored = try await dependencies.coachSessionClient.fetchMessages(
                sessionId: sessionId,
                limit: 50,
                token: token
            )
            guard !restored.isEmpty else { return }
            messages = restored.map {
                ChatMessage(role: $0.role, content: $0.content, timestamp: $0.timestamp)
            }
            didRestoreConversation = true
        } catch CoachSessionError.sessionNotFound {
            self.sessionId = nil
        } catch let error as CoachSessionError {
            restoreError = error
        } catch {
            restoreError = .httpError(statusCode: 0, body: error.localizedDescription)
        }
    }

    func retryLoadMessages() async {
        restoreError = nil
        await loadMessagesIfNeeded()
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
        error = nil
        rateLimitInfo = nil
        lastSentMessageText = trimmed
        currentStage = nil
        completedStages = []

        // Get auth token
        guard let token = dependencies.pairingService.getToken() else {
            messages.removeAll { $0.id == userMessage.id || $0.id == assistantMessage.id }
            assistantMessage.isStreaming = false
            isStreaming = false
            error = .unauthenticated()
            return
        }

        let request = ChatStreamRequest(
            message: trimmed,
            sessionId: sessionId,
            context: nil
        )

        streamTask?.cancel()

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = self.dependencies.chatStreamService.stream(request: request, token: token)
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    self.processEvent(event, message: assistantMessage)
                }
            } catch {
                if !Task.isCancelled {
                    if assistantMessage.content.isEmpty {
                        if let idx = self.messages.lastIndex(where: { $0.id == assistantMessage.id }) {
                            self.messages.remove(at: idx)
                        }
                        if let idx = self.messages.lastIndex(where: { $0.id == userMessage.id }) {
                            self.messages.remove(at: idx)
                        }
                    }
                    self.error = CTAError.map(error)
                }
            }
            // Clean up empty placeholder if an SSE .error event set the error
            if assistantMessage.content.isEmpty && self.error != nil {
                if let idx = self.messages.lastIndex(where: { $0.id == assistantMessage.id }) {
                    self.messages.remove(at: idx)
                }
                if let idx = self.messages.lastIndex(where: { $0.id == userMessage.id }) {
                    self.messages.remove(at: idx)
                }
            }
            assistantMessage.isStreaming = false
            self.isStreaming = false
        }

        // Wait for stream to complete
        await streamTask?.value
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
            scrollTrigger = UUID()

        case .functionCall(let id, let name):
            let toolCall = ChatToolCall(id: id, name: name, status: .running)
            message.toolCalls.append(toolCall)

        case .functionResult(let toolUseId, _, let result):
            if let idx = message.toolCalls.firstIndex(where: { $0.id == toolUseId }) {
                var updated = message.toolCalls[idx]
                updated.status = .completed
                updated.result = result
                message.toolCalls[idx] = updated
            }
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

        case .heartbeat(_, let toolName, let elapsed):
            // Match by toolName if available, fall back to last running tool call
            if let toolName,
               let idx = message.toolCalls.lastIndex(where: { $0.name == toolName && $0.status == .running }) {
                var updated = message.toolCalls[idx]
                updated.elapsedSeconds = elapsed
                message.toolCalls[idx] = updated
            } else if let idx = message.toolCalls.lastIndex(where: { $0.status == .running }) {
                var updated = message.toolCalls[idx]
                updated.elapsedSeconds = elapsed
                message.toolCalls[idx] = updated
            }

        case .messageEnd(_, let tokens, let latency):
            message.tokensUsed = tokens
            message.latencyMs = latency

        case .error(let type, let errorMsg, let usage, let limit):
            // AMA-1803 P2: SSE `.error` events from the chat-api are
            // semantically the same shape as the AMA-271 lying-success
            // pattern — HTTP/SSE 200 OK at the transport layer, but
            // the server is reporting a failure in the body. Map to
            // .lyingSuccess so the View renders the typed banner with
            // error_code (the `type` string from the server) and so
            // the Sentry tag matches AMA-1805's `lying_success_200`
            // failure_reason. Rate-limit gets the dedicated banner
            // via rateLimitInfo, distinct from the generic error UI.
            error = .lyingSuccess(
                message: errorMsg,
                errorCode: type,
                requestId: nil
            )
            if type == "rate_limit_exceeded", let usage, let limit {
                rateLimitInfo = RateLimitInfo(usage: usage, limit: limit)
            }
        }
    }

    // MARK: - Parse Workout Data from Tool Result

    private func tryParseWorkoutData(result: String, message: ChatMessage) {
        guard let data = result.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let workout = try? decoder.decode(GeneratedWorkout.self, from: data),
           !workout.exercises.isEmpty {
            message.workoutData = workout
            return
        }

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
        streamTask = nil
        isStreaming = false
        messages.removeAll()
        sessionId = nil
        error = nil
        restoreError = nil
        didRestoreConversation = false
        lastSentMessageText = nil
        currentStage = nil
        completedStages = []
        rateLimitInfo = nil
    }

    /// AMA-1803 P2: re-send the last user message after a transient
    /// failure. Wired to the ErrorToast Retry button. No-op if there's
    /// no cached message (defensive — Retry should be hidden by
    /// CTAError.isRetryable in those cases anyway).
    func retryLastMessage() async {
        guard let text = lastSentMessageText else { return }
        // Drop the typed error so the UI flips back to the normal
        // streaming state immediately. If the retry fails we re-set it.
        error = nil
        await sendMessage(text)
    }

    /// AMA-1803 P2: clear the typed error from the View when the user
    /// dismisses the banner. Mirrors `WorkoutEngine.acknowledgeSaveError`.
    func acknowledgeError() {
        error = nil
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        currentStage = nil
        completedStages = []
        messages.last?.isStreaming = false
    }

    private func persistSessionId() {
        if let sessionId {
            UserDefaults.standard.set(sessionId, forKey: self.sessionIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: self.sessionIdKey)
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
        isStreaming: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
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
