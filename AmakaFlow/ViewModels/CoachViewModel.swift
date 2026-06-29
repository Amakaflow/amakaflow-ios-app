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

/// AMA-2234 (E9-3): explicit degradation modes for the single in-app coach
/// shell.
///
/// iOS does **not** own a coach brain. Every turn routes through the shared
/// mobile-BFF / Channel Gateway / coach core path (the same path Telegram
/// proved in Epic 8). When a shared dependency is unavailable the shell must
/// surface one of these honest modes instead of a blank screen, a crash, or a
/// silent "success". Mirrors the Epic 9 voice degradation contract
/// (`text` / `manual` / `mock` / `skip` / `data_gap`).
enum CoachDegradeMode: String, Equatable, CaseIterable {
    /// Typed text path is available and is always the source of truth.
    case text
    /// Shared coach path is unreachable right now — the user can keep typing
    /// and retry; nothing is auto-executed and nothing is faked as sent.
    case manual
    /// Dev/fixture dependencies are in use (simulator validation). No live
    /// BFF / gateway / LLM call is made.
    case mock
    /// An optional capability (e.g. voice, AMA-2231) is intentionally not in
    /// this slice. Same coach, text only.
    case skip
    /// Required session/history data is unavailable and must not be fabricated.
    case dataGap

    /// Contract token used in logs, telemetry, and tests.
    var contractToken: String {
        switch self {
        case .text: return "text"
        case .manual: return "manual"
        case .mock: return "mock"
        case .skip: return "skip"
        case .dataGap: return "data_gap"
        }
    }

    /// Whether the header health dot should render in the degraded color.
    var isDegraded: Bool { self != .text }

    /// Title shown on the degraded banner. `nil` when no banner is needed.
    var bannerTitle: String? {
        switch self {
        case .text: return nil
        case .manual: return "Coach is reachable by text only"
        case .mock: return "Dev mock mode"
        case .skip: return "Voice is unavailable right now"
        case .dataGap: return "Couldn't restore your earlier conversation"
        }
    }

    /// Supporting copy under the banner title.
    var bannerDetail: String? {
        switch self {
        case .text: return nil
        case .manual:
            return "We couldn't route that through your shared coach just now. "
                + "Your message wasn't sent — same coach as Telegram and Watch, text only. Tap retry."
        case .mock:
            return "Coach replies are local fixtures for validation. No live BFF / gateway / LLM call is made."
        case .skip:
            return "Same coach, text only — your messages still route normally."
        case .dataGap:
            return "Your history is temporarily unavailable, so we're not guessing it. "
                + "New messages still route through your shared coach."
        }
    }
}

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

    /// AMA-2234 (E9-3): current degradation mode for the coach shell. `nil`
    /// (or `.text`) means the shared coach path is healthy. Drives the header
    /// health dot and the text-only degraded banner. Never left in a state
    /// that hides a failure or fakes a success.
    @Published var degradeMode: CoachDegradeMode?
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

    /// Monotonic id for the in-flight stream turn. Bumped on every new send and
    /// on cancel so a superseded/cancelled stream task can't run its late
    /// cleanup against a newer turn (which would clobber `isStreaming`, the
    /// error/degrade state, or remove the wrong placeholder). Only the task
    /// whose captured generation still matches may mutate shared turn state.
    private var streamGeneration = 0

    /// AMA-2234: the steady-state degrade mode for the current dependency
    /// wiring. `.mock` when fixture/mock services are injected (dev/simulator
    /// validation), otherwise `nil` (healthy live shared path). Transient
    /// failures degrade to `.manual` / `.dataGap` and then fall back to this
    /// baseline on recovery — mock mode stays sticky because it reflects the
    /// environment, not a transient failure.
    private let baselineDegradeMode: CoachDegradeMode?

    private func sessionStorageKey(for userId: String) -> String {
        DefaultsKey.coachSessionID(userID: userId)
    }

    private var sessionIdKey: String {
        sessionStorageKey(for: boundSessionUserId ?? "unknown")
    }

    // MARK: - Init

    init(dependencies: AppDependencies = .current) {
        self.dependencies = dependencies
        // AMA-2234: fixture/mock coach wiring means we are exercising the
        // shell against local fixtures (simulator/dev), not the live shared
        // coach path. Surface that honestly as `.mock` rather than pretending
        // replies are live.
        let baseline: CoachDegradeMode? = dependencies.isMockCoachPath ? .mock : nil
        self.baselineDegradeMode = baseline
        self.degradeMode = baseline
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
            guard !restored.isEmpty else {
                // An empty (but successful) restore is a normal new/empty thread,
                // not a data gap — clear any prior degraded state on retry.
                resetDegradeToBaseline()
                return
            }
            messages = restored.map {
                ChatMessage(role: $0.role, content: $0.content, timestamp: $0.timestamp)
            }
            didRestoreConversation = true
            // Successful restore: clear any prior data-gap and return to the
            // baseline (healthy, or sticky mock in dev).
            resetDegradeToBaseline()
        } catch CoachSessionError.sessionNotFound {
            // 404 is a normal "new conversation" outcome, not a degradation.
            // Clear any prior data-gap so a recovered retry isn't stuck degraded.
            self.sessionId = nil
            resetDegradeToBaseline()
        } catch let error as CoachSessionError {
            restoreError = error
            // History could not be loaded from the shared path — surface a
            // data_gap rather than silently showing an empty thread.
            degradeIfNotMock(.dataGap)
        } catch {
            restoreError = .httpError(statusCode: 0, body: error.localizedDescription)
            degradeIfNotMock(.dataGap)
        }
    }

    func retryLoadMessages() async {
        restoreError = nil
        await loadMessagesIfNeeded()
    }

    // MARK: - Send Message (Streaming)

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reject sends while a turn is streaming or while session restore is in
        // flight: loadMessagesIfNeeded() snapshots `messages.isEmpty` before its
        // await and replaces `messages` wholesale when it resolves, so a send
        // started mid-restore would be overwritten. The composer also gates this,
        // but guard here too for direct/retry callers.
        guard !trimmed.isEmpty, !isStreaming, !isLoadingMessages else { return }

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
            // Auth is its own surface, not a dependency-down condition — don't
            // leave a stale `.manual` / `.dataGap` banner on screen.
            resetDegradeToBaseline()
            return
        }

        let request = ChatStreamRequest(
            message: trimmed,
            sessionId: sessionId,
            context: nil
        )

        streamTask?.cancel()
        streamGeneration += 1
        let generation = streamGeneration

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = self.dependencies.chatStreamService.stream(request: request, token: token)
            var caughtError: Error?
            do {
                for try await event in stream {
                    // Stop if cancelled or if a newer turn has superseded us.
                    guard !Task.isCancelled, self.streamGeneration == generation else { break }
                    self.processEvent(event, message: assistantMessage)
                }
            } catch {
                caughtError = error
            }

            // Only the active stream may finalize shared turn state. If Stop was
            // tapped (or a newer send started), this task's late cleanup must not
            // flip `isStreaming` off mid-turn or remove the new turn's bubbles.
            guard self.streamGeneration == generation else { return }

            if let caughtError, !Task.isCancelled {
                if assistantMessage.content.isEmpty {
                    self.messages.removeAll { $0.id == assistantMessage.id || $0.id == userMessage.id }
                }
                self.error = CTAError.map(caughtError)
            }
            // Clean up empty placeholder if an SSE .error event set the error
            if assistantMessage.content.isEmpty && self.error != nil {
                self.messages.removeAll { $0.id == assistantMessage.id || $0.id == userMessage.id }
            }
            assistantMessage.isStreaming = false
            self.isStreaming = false

            // AMA-2234: resolve the degrade mode once the turn settles. A
            // failed turn (transport down / 5xx / SSE error) degrades to
            // text-only `manual`; a clean turn returns to baseline. This is
            // what keeps a missing BFF / gateway / LLM from becoming a blank
            // screen, crash, or silent success.
            if let ctaError = self.error {
                self.applyDegrade(forTurnFailure: ctaError)
            } else if !Task.isCancelled {
                self.resetDegradeToBaseline()
            }
        }

        // Wait for stream to complete
        await streamTask?.value
    }

    // MARK: - Degradation (AMA-2234)

    /// Reset the degrade mode to the dependency baseline (healthy `nil`, or
    /// sticky `.mock` in dev/fixture mode).
    private func resetDegradeToBaseline() {
        degradeMode = baselineDegradeMode
    }

    /// Set a transient degrade mode unless we are pinned to `.mock` (dev),
    /// which reflects the environment and stays sticky.
    private func degradeIfNotMock(_ mode: CoachDegradeMode) {
        guard baselineDegradeMode != .mock else { return }
        degradeMode = mode
    }

    /// Map a settled coach-turn failure onto a degrade mode. Rate-limit and
    /// auth failures are not dependency-down conditions (they have their own
    /// surfaces), so they fall back to the baseline.
    private func applyDegrade(forTurnFailure error: CTAError) {
        if baselineDegradeMode == .mock {
            degradeMode = .mock
            return
        }
        if rateLimitInfo != nil {
            degradeMode = baselineDegradeMode
            return
        }
        switch error {
        case .unauthenticated:
            degradeMode = baselineDegradeMode
        case .network, .http, .lyingSuccess, .decoding, .unknown:
            // Shared coach path could not complete the turn → text-only.
            degradeMode = .manual
        }
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
        resetDegradeToBaseline()
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
        // Invalidate the in-flight task so its late cleanup can't reset state on
        // (or tear down) a subsequent turn the user starts right after Stop.
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        currentStage = nil
        completedStages = []
        // Stopping during the first-token wait must not leave a blank assistant
        // bubble behind — drop the empty placeholder instead of un-streaming it.
        if let last = messages.last, last.role == .assistant, last.content.isEmpty {
            messages.removeLast()
        } else {
            messages.last?.isStreaming = false
        }
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
