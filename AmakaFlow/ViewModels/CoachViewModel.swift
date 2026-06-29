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

enum CoachVoiceDependency: String, Equatable, CaseIterable {
    case permissionDenied = "permission_denied"
    case recorderUnavailable = "recorder_unavailable"
    case sttDown = "stt_down"
    case ttsDown = "tts_down"
    case networkDown = "network_down"
    case gatewayDown = "gateway_down"

    var title: String {
        switch self {
        case .permissionDenied: return "Microphone permission is off"
        case .recorderUnavailable: return "Recorder is unavailable"
        case .sttDown: return "Couldn't transcribe that"
        case .ttsDown: return "Spoken output is unavailable"
        case .networkDown: return "Network is unavailable"
        case .gatewayDown: return "Coach gateway is unavailable"
        }
    }

    var detail: String {
        switch self {
        case .permissionDenied:
            return "Same coach, text only. Type what you wanted to say."
        case .recorderUnavailable:
            return "Use the saved fixture or type manually. No live recording is required."
        case .sttDown:
            return "We saved your recording. Play it back, retry, or type instead."
        case .ttsDown:
            return "The coach response stays visible as text. Speech is skipped for this turn."
        case .networkDown:
            return "Your transcript was not sent. Text entry and retry remain available."
        case .gatewayDown:
            return "The shared BFF / gateway path is missing data, so nothing is guessed or auto-sent."
        }
    }

    var fallbackMode: CoachDegradeMode {
        switch self {
        case .permissionDenied, .sttDown, .networkDown:
            return .manual
        case .recorderUnavailable:
            return .mock
        case .ttsDown:
            return .skip
        case .gatewayDown:
            return .dataGap
        }
    }

    var fallbackAction: String {
        switch self {
        case .permissionDenied, .sttDown, .networkDown:
            return "manual"
        case .recorderUnavailable:
            return "mock"
        case .ttsDown:
            return "skip"
        case .gatewayDown:
            return "data_gap"
        }
    }
}

enum CoachVoicePhase: Equatable {
    case idle
    case listening
    case transcriptionFallback
    case degraded
}

struct CoachVoiceState: Equatable {
    var phase: CoachVoicePhase = .idle
    var partialTranscript: String = ""
    var manualTranscript: String = ""
    var durationLabel: String = "0:00"
    var savedRecordingLabel: String?
    var dependency: CoachVoiceDependency?
    var lastSubmittedTranscript: String?
    var lastSpokenText: String?
    var isPlayingSavedRecording: Bool = false
    var textResponseVisible: Bool = true
    var pendingActionConfirmationVisible: Bool = true

    var fallbackMode: CoachDegradeMode {
        dependency?.fallbackMode ?? .text
    }

    var fallbackAction: String {
        dependency?.fallbackAction ?? "text"
    }

    var isPresented: Bool {
        phase != .idle
    }

    func applyingInputDegrade(_ dependency: CoachVoiceDependency) -> CoachVoiceState {
        var next = self
        next.phase = dependency == .ttsDown ? .degraded : .transcriptionFallback
        next.dependency = dependency
        next.savedRecordingLabel = dependency == .ttsDown ? nil : "0:06"
        next.manualTranscript = partialTranscript
        next.isPlayingSavedRecording = false
        next.textResponseVisible = true
        next.pendingActionConfirmationVisible = true
        return next
    }

    func applyingOutputDegrade(_ dependency: CoachVoiceDependency) -> CoachVoiceState {
        var next = self
        next.dependency = dependency
        next.textResponseVisible = true
        next.pendingActionConfirmationVisible = true
        next.phase = .degraded
        next.isPlayingSavedRecording = false
        return next
    }
}

enum CoachTurnMode: String, Equatable, CaseIterable {
    case live
    case mock
    case skip
    case dataGap = "data_gap"
}

enum CoachTurnSourceStage: String, Equatable, CaseIterable {
    case app
    case bff
    case gateway
    case coachCore = "coach_core"
    case llm
    case dependencyDown = "dependency_down"
    case telemetrySink = "telemetry_sink"

    static func fromStreamErrorType(_ type: String) -> CoachTurnSourceStage {
        let normalized = type.lowercased()
        if normalized.contains("bff") { return .bff }
        if normalized.contains("gateway") { return .gateway }
        if normalized.contains("llm") || normalized.contains("ai") { return .llm }
        if normalized.contains("coach") || normalized.contains("stream") { return .coachCore }
        return .dependencyDown
    }
}

enum CoachStreamingPhase: String, Equatable, CaseIterable {
    case idle
    case waiting
    case firstTokenReceived = "first_token_received"
    case partialResponse = "partial_response"
    case completed
    case failed
    case interrupted
    case degraded

    var footerLabel: String? {
        switch self {
        case .waiting:
            return "WAITING"
        case .firstTokenReceived:
            return "FIRST TOKEN"
        case .partialResponse:
            return "STREAMING"
        default:
            return nil
        }
    }

    var statusLine: String {
        switch self {
        case .waiting:
            return "Reading your recent sessions..."
        case .firstTokenReceived:
            return "Starting the response..."
        case .partialResponse:
            return "Building the response..."
        case .failed:
            return "The turn failed. Retry is available."
        case .interrupted:
            return "Stopped. Partial text stays visible."
        case .degraded:
            return "Shared coach path degraded. Text fallback is available."
        case .completed, .idle:
            return ""
        }
    }
}

struct CoachTurnTelemetryEvent: Equatable {
    enum Name: String {
        case sendStarted = "send_started"
        case messageStarted = "message_started"
        case firstToken = "first_token"
        case partialChunk = "partial_chunk"
        case pendingActionSurfaced = "pending_action_surfaced"
        case completed
        case failed
        case interrupted
        case degraded
        case telemetrySinkDown = "telemetry_sink_down"
    }

    let name: Name
    let turnId: String
    let mode: CoachTurnMode
    let sourceStage: CoachTurnSourceStage
    let streamingPhase: CoachStreamingPhase
    let latencyMs: Int?
    let sessionId: String?
    let traceId: String?
    let details: String?
}

protocol CoachTurnTelemetryProviding {
    @MainActor
    func emit(_ event: CoachTurnTelemetryEvent) throws
}

struct CoachTurnDebugTelemetrySink: CoachTurnTelemetryProviding {
    @MainActor
    func emit(_ event: CoachTurnTelemetryEvent) throws {
        var metadata: [String: String] = [
            "turn_id": event.turnId,
            "mode": event.mode.rawValue,
            "source_stage": event.sourceStage.rawValue,
            "streaming_phase": event.streamingPhase.rawValue
        ]
        if let latencyMs = event.latencyMs {
            metadata["latency_ms"] = "\(latencyMs)"
        }
        if let sessionId = event.sessionId {
            metadata["session_id"] = sessionId
        }
        if let traceId = event.traceId {
            metadata["trace_id"] = traceId
        }
        DebugLogService.shared.log(
            "Coach turn telemetry: \(event.name.rawValue)",
            details: event.details ?? event.streamingPhase.statusLine,
            metadata: metadata
        )
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
    @Published var pendingActionLifecycle: [PendingActionContract] = []
    @Published var pendingActionBusyIds: Set<String> = []
    @Published var voiceState = CoachVoiceState()
    @Published private(set) var streamingLifecycle: [CoachStreamingPhase] = []
    @Published private(set) var coachTurnTelemetryEvents: [CoachTurnTelemetryEvent] = []
    @Published private(set) var telemetrySinkMode: CoachTurnMode = .live
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
    private var activeTurnTelemetry: CoachTurnTelemetryContext?
    private let maxCoachTurnTelemetryEvents = 100

    /// Monotonic id for the in-flight stream turn. Bumped on every new send and
    /// on cancel so a superseded/cancelled stream task can't run its late
    /// cleanup against a newer turn (which would clobber `isStreaming`, the
    /// error/degrade state, or remove the wrong placeholder). Only the task
    /// whose captured generation still matches may mutate shared turn state.
    private var streamGeneration = 0
    private var shouldSpeakNextCoachReply = false

    /// Monotonic id for the in-flight session restore. Bumped by startNewChat()
    /// so a late `fetchMessages` completion can't repopulate (or re-degrade) a
    /// thread the user has already cleared.
    private var restoreGeneration = 0

    /// AMA-2234: the steady-state degrade mode for the current dependency
    /// wiring. `.mock` when fixture/mock services are injected (dev/simulator
    /// validation), otherwise `nil` (healthy live shared path). Transient
    /// failures degrade to `.manual` / `.dataGap` and then fall back to this
    /// baseline on recovery — mock mode stays sticky because it reflects the
    /// environment, not a transient failure.
    private let baselineDegradeMode: CoachDegradeMode?

    private struct CoachTurnTelemetryContext {
        let turnId: String
        let startedAt: Date
        var traceId: String?
        var firstTokenRecorded = false
        var partialChunkCount = 0
    }

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
        // Snapshot the conversation identity. If startNewChat() (which bumps
        // restoreGeneration) or a session change happens while we're awaiting,
        // this restore is stale and must not repopulate or re-degrade the
        // now-cleared thread.
        let restoreGenerationSnapshot = restoreGeneration
        defer { isLoadingMessages = false }

        func restoreIsStale() -> Bool {
            restoreGenerationSnapshot != restoreGeneration || self.sessionId != sessionId
        }

        do {
            let restored = try await dependencies.coachSessionClient.fetchMessages(
                sessionId: sessionId,
                limit: 50,
                token: token
            )
            guard !restoreIsStale() else { return }
            guard !restored.isEmpty else {
                // An empty (but successful) restore is a normal new/empty thread,
                // not a data gap — clear any prior degraded state on retry.
                resetDegradeToBaseline()
                return
            }
            messages = restored.map {
                ChatMessage(
                    role: $0.role,
                    content: $0.content,
                    pendingActions: $0.pendingActions,
                    timestamp: $0.timestamp
                )
            }
            rebuildPendingActionLifecycle()
            didRestoreConversation = true
            // Successful restore: clear any prior data-gap and return to the
            // baseline (healthy, or sticky mock in dev).
            resetDegradeToBaseline()
        } catch CoachSessionError.sessionNotFound {
            guard !restoreIsStale() else { return }
            // 404 is a normal "new conversation" outcome, not a degradation.
            // Clear any prior data-gap so a recovered retry isn't stuck degraded.
            self.sessionId = nil
            resetDegradeToBaseline()
        } catch let error as CoachSessionError {
            guard !restoreIsStale() else { return }
            restoreError = error
            // History could not be loaded from the shared path — surface a
            // data_gap rather than silently showing an empty thread.
            degradeIfNotMock(.dataGap)
        } catch {
            guard !restoreIsStale() else { return }
            restoreError = .httpError(statusCode: 0, body: error.localizedDescription)
            degradeIfNotMock(.dataGap)
        }
    }

    func retryLoadMessages() async {
        restoreError = nil
        await loadMessagesIfNeeded()
    }

    // MARK: - First-token / Streaming Telemetry (AMA-2233)

    private func currentTelemetryMode(for error: CTAError? = nil) -> CoachTurnMode {
        if baselineDegradeMode == .mock {
            return .mock
        }
        if baselineDegradeMode == .skip || degradeMode == .skip {
            return .skip
        }
        if baselineDegradeMode == .dataGap || degradeMode == .dataGap {
            return .dataGap
        }
        if error != nil {
            return .dataGap
        }
        return .live
    }

    private func beginTurnTelemetry(for message: ChatMessage) {
        let turnId = UUID().uuidString
        activeTurnTelemetry = CoachTurnTelemetryContext(turnId: turnId, startedAt: Date())
        streamingLifecycle = [.waiting]
        message.streamingPhase = .waiting
        message.streamingMode = currentTelemetryMode()
        telemetrySinkMode = .live
        emitTelemetry(
            .sendStarted,
            mode: message.streamingMode,
            sourceStage: .app,
            phase: .waiting,
            latencyMs: nil,
            details: "iOS coach turn sent through shared stream path"
        )
    }

    private func transitionStream(
        _ phase: CoachStreamingPhase,
        message: ChatMessage,
        mode: CoachTurnMode? = nil,
        sourceStage: CoachTurnSourceStage,
        eventName: CoachTurnTelemetryEvent.Name,
        latencyMs: Int? = nil,
        details: String? = nil
    ) {
        if streamingLifecycle.last != phase {
            streamingLifecycle.append(phase)
        }
        message.streamingPhase = phase
        if let mode {
            message.streamingMode = mode
        }
        message.streamingSourceStage = sourceStage
        if phase == .firstTokenReceived, let latencyMs {
            message.firstTokenLatencyMs = latencyMs
        }
        emitTelemetry(
            eventName,
            mode: mode ?? message.streamingMode,
            sourceStage: sourceStage,
            phase: phase,
            latencyMs: latencyMs,
            details: details
        )
    }

    /// App-side first-token latency from send tap through first visible token.
    /// Source-reported `latency_ms` from the BFF is carried in telemetry details only.
    private func appMeasuredFirstTokenLatencyMs() -> Int {
        guard let startedAt = activeTurnTelemetry?.startedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
    }

    private func firstTokenDetails(sourceLatencyMs: Int? = nil) -> String {
        if let sourceLatencyMs {
            return "First token received (source_latency_ms=\(sourceLatencyMs))"
        }
        return "First token inferred from first content delta"
    }

    private func updateActiveTurn(_ update: (inout CoachTurnTelemetryContext) -> Void) {
        guard var context = activeTurnTelemetry else { return }
        update(&context)
        activeTurnTelemetry = context
    }

    private func emitTelemetry(
        _ name: CoachTurnTelemetryEvent.Name,
        mode: CoachTurnMode,
        sourceStage: CoachTurnSourceStage,
        phase: CoachStreamingPhase,
        latencyMs: Int?,
        details: String?
    ) {
        let turnId = activeTurnTelemetry?.turnId ?? UUID().uuidString
        let event = CoachTurnTelemetryEvent(
            name: name,
            turnId: turnId,
            mode: mode,
            sourceStage: sourceStage,
            streamingPhase: phase,
            latencyMs: latencyMs,
            sessionId: sessionId,
            traceId: activeTurnTelemetry?.traceId,
            details: details
        )
        coachTurnTelemetryEvents.append(event)
        trimCoachTurnTelemetryEvents()
        guard telemetrySinkMode != .dataGap else { return }
        do {
            try dependencies.coachTurnTelemetrySink.emit(event)
        } catch {
            telemetrySinkMode = .dataGap
            let sinkEvent = CoachTurnTelemetryEvent(
                name: .telemetrySinkDown,
                turnId: turnId,
                mode: .dataGap,
                sourceStage: .telemetrySink,
                streamingPhase: phase,
                latencyMs: latencyMs,
                sessionId: sessionId,
                traceId: activeTurnTelemetry?.traceId,
                details: "Telemetry sink unavailable: \(error.localizedDescription)"
            )
            coachTurnTelemetryEvents.append(sinkEvent)
            trimCoachTurnTelemetryEvents()
        }
    }

    private func trimCoachTurnTelemetryEvents() {
        if coachTurnTelemetryEvents.count > maxCoachTurnTelemetryEvents {
            coachTurnTelemetryEvents = Array(coachTurnTelemetryEvents.suffix(maxCoachTurnTelemetryEvents))
        }
    }

    // MARK: - Send Message (Streaming)

    @discardableResult
    func sendMessage(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reject sends while a turn is streaming or while session restore is in
        // flight: loadMessagesIfNeeded() snapshots `messages.isEmpty` before its
        // await and replaces `messages` wholesale when it resolves, so a send
        // started mid-restore would be overwritten. The composer also gates this,
        // but guard here too for direct/retry callers.
        guard !trimmed.isEmpty, !isStreaming, !isLoadingMessages else { return false }

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
        beginTurnTelemetry(for: assistantMessage)

        // Get auth token
        guard let token = dependencies.pairingService.getToken() else {
            transitionStream(
                .failed,
                message: assistantMessage,
                mode: .skip,
                sourceStage: .app,
                eventName: .failed,
                details: "Auth token unavailable; coach turn skipped"
            )
            messages.removeAll { $0.id == userMessage.id || $0.id == assistantMessage.id }
            assistantMessage.isStreaming = false
            isStreaming = false
            error = .unauthenticated()
            // Auth is its own surface, not a dependency-down condition — don't
            // leave a stale `.manual` / `.dataGap` banner on screen.
            resetDegradeToBaseline()
            activeTurnTelemetry = nil
            return false
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
                let failurePhase: CoachStreamingPhase = assistantMessage.content.isEmpty ? .failed : .degraded
                self.transitionStream(
                    failurePhase,
                    message: assistantMessage,
                    mode: .dataGap,
                    sourceStage: .dependencyDown,
                    eventName: failurePhase == .failed ? .failed : .degraded,
                    details: caughtError.localizedDescription
                )
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
                self.transitionStream(
                    .completed,
                    message: assistantMessage,
                    mode: self.currentTelemetryMode(),
                    sourceStage: .coachCore,
                    eventName: .completed,
                    latencyMs: assistantMessage.latencyMs,
                    details: "Coach stream completed"
                )
                self.resetDegradeToBaseline()
                self.speakVoiceReplyIfNeeded(assistantMessage.content)
            }
            self.activeTurnTelemetry = nil
        }

        // Wait for stream to complete
        await streamTask?.value
        return error == nil
    }

    // MARK: - Voice UX (AMA-2231)

    func startVoiceListening(
        partialTranscript: String = "",
        durationLabel: String = "0:00"
    ) {
        guard !isStreaming, !isLoadingMessages else { return }
        voiceState = CoachVoiceState(
            phase: .listening,
            partialTranscript: partialTranscript,
            manualTranscript: "",
            durationLabel: durationLabel,
            savedRecordingLabel: nil,
            dependency: nil,
            lastSubmittedTranscript: voiceState.lastSubmittedTranscript,
            lastSpokenText: voiceState.lastSpokenText,
            isPlayingSavedRecording: false,
            textResponseVisible: true,
            pendingActionConfirmationVisible: true
        )
    }

    func updateVoicePartialTranscript(_ transcript: String) {
        guard voiceState.phase == .listening else { return }
        var next = voiceState
        next.partialTranscript = transcript
        voiceState = next
    }

    func cancelVoiceInput() {
        shouldSpeakNextCoachReply = false
        voiceState = CoachVoiceState(
            lastSubmittedTranscript: voiceState.lastSubmittedTranscript,
            lastSpokenText: voiceState.lastSpokenText
        )
    }

    func setVoiceManualTranscript(_ transcript: String) {
        var next = voiceState
        next.manualTranscript = transcript
        voiceState = next
    }

    func playSavedVoiceRecording() {
        guard voiceState.savedRecordingLabel != nil else { return }
        let playbackText = [voiceState.manualTranscript, voiceState.partialTranscript]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Saved voice recording"
        var next = voiceState
        next.lastSpokenText = playbackText
        next.isPlayingSavedRecording = true
        voiceState = next
        dependencies.audioService.speak(playbackText, priority: .normal)
    }

    func retryVoiceInput() {
        startVoiceListening(partialTranscript: "", durationLabel: "0:00")
    }

    func degradeVoiceInput(_ dependency: CoachVoiceDependency) {
        voiceState = voiceState.applyingInputDegrade(dependency)
        degradeIfNotMock(dependency.fallbackMode)
    }

    @discardableResult
    func submitVoiceTranscript(_ transcript: String? = nil, speakResponse: Bool = true) async -> Bool {
        let source = transcript ?? (voiceState.manualTranscript.isEmpty ? voiceState.partialTranscript : voiceState.manualTranscript)
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            degradeVoiceInput(.sttDown)
            return false
        }

        var submittedState = voiceState
        submittedState.lastSubmittedTranscript = trimmed
        submittedState.textResponseVisible = true
        submittedState.pendingActionConfirmationVisible = true
        submittedState.phase = .idle
        submittedState.isPlayingSavedRecording = false
        voiceState = submittedState
        shouldSpeakNextCoachReply = speakResponse
        let priorDegradeMode = degradeMode
        let accepted = await sendMessage(trimmed)
        guard !accepted else { return true }

        shouldSpeakNextCoachReply = false
        if case .unauthenticated? = error {
            return false
        }

        if priorDegradeMode == .dataGap || degradeMode == .dataGap {
            degradeVoiceInput(.gatewayDown)
        } else if error != nil {
            degradeVoiceInput(.networkDown)
        }
        return false
    }

    func degradeVoiceOutput(_ dependency: CoachVoiceDependency = .ttsDown) {
        voiceState = voiceState.applyingOutputDegrade(dependency)
        shouldSpeakNextCoachReply = false
        degradeIfNotMock(dependency.fallbackMode)
    }

    private func speakVoiceReplyIfNeeded(_ text: String) {
        guard shouldSpeakNextCoachReply else { return }
        shouldSpeakNextCoachReply = false
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        var next = voiceState
        next.lastSpokenText = spoken
        next.textResponseVisible = true
        next.pendingActionConfirmationVisible = true
        voiceState = next
        dependencies.audioService.speak(spoken, priority: .normal)
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

    // MARK: - PendingActions (AMA-2230)

    func pendingAction(withId actionId: String) -> PendingActionContract? {
        pendingActionLifecycle.first { $0.actionId == actionId }
    }

    func isPendingActionBusy(_ action: PendingActionContract) -> Bool {
        pendingActionBusyIds.contains(action.actionId)
    }

    func confirmPendingAction(_ action: PendingActionContract, decision: PendingActionDecision) async {
        let currentAction = pendingAction(withId: action.actionId) ?? action
        guard currentAction.riskTier.requiresConfirmation else { return }
        guard currentAction.executionStatus.acceptsConfirmationDecision else { return }
        await executePendingAction(currentAction, decision: decision)
    }

    func retryPendingAction(_ action: PendingActionContract) async {
        let currentAction = pendingAction(withId: action.actionId) ?? action
        guard currentAction.riskTier.requiresConfirmation else { return }
        guard currentAction.executionStatus == .failedRetryable else { return }
        await executePendingAction(currentAction, decision: .approve)
    }

    private func executePendingAction(_ action: PendingActionContract, decision: PendingActionDecision) async {
        guard !pendingActionBusyIds.contains(action.actionId) else { return }

        guard let token = dependencies.pairingService.getToken() else {
            error = .unauthenticated()
            resetDegradeToBaseline()
            return
        }

        pendingActionBusyIds.insert(action.actionId)
        applyPendingActionStatus(.executing, to: action.actionId, responseStatus: "executing", error: nil)
        defer { pendingActionBusyIds.remove(action.actionId) }

        do {
            let response = try await dependencies.pendingActionsClient.confirm(
                action: action,
                decision: decision,
                token: token
            )
            if let updated = response.action {
                var decorated = updated.withFallbackPresentation()
                decorated.lastResponseStatus = response.status
                decorated.error = response.error ?? decorated.error
                if let responseStatus = PendingActionExecutionStatus(rawValue: response.status),
                   responseStatus != .replayedNoop {
                    decorated.executionStatus = responseStatus
                }
                upsertPendingAction(decorated)
            } else {
                let next: PendingActionExecutionStatus = decision == .approve ? .succeeded : .declined
                applyPendingActionStatus(next, to: action.actionId, responseStatus: response.status, error: response.error)
            }
            if response.error?.mode == "data_gap" {
                degradeIfNotMock(.dataGap)
            } else {
                resetDegradeToBaseline()
            }
        } catch {
            let envelope = PendingActionErrorEnvelope(
                mode: "data_gap",
                code: "ios_pending_action_execute_failed",
                message: error.localizedDescription,
                retryable: true,
                dataGaps: [["code": "pending_actions:ios_execute_failed", "source": "ios"]]
            )
            applyPendingActionStatus(.failedRetryable, to: action.actionId, responseStatus: "failed_retryable", error: envelope)
            degradeIfNotMock(.dataGap)
        }
    }

    func markPendingActionStale(_ action: PendingActionContract) {
        applyPendingActionStatus(.stale, to: action.actionId, responseStatus: "stale", error: nil)
    }

    private func appendPendingActions(_ actions: [PendingActionContract], to message: ChatMessage) {
        guard !actions.isEmpty else { return }
        for action in actions.map({ $0.withFallbackPresentation() }) where action.riskTier.requiresConfirmation {
            if !message.pendingActions.contains(where: { $0.actionId == action.actionId }) {
                message.pendingActions.append(action)
            }
            upsertPendingAction(action)
        }
        scrollTrigger = UUID()
    }

    private func upsertPendingAction(_ action: PendingActionContract) {
        if let idx = pendingActionLifecycle.firstIndex(where: { $0.actionId == action.actionId }) {
            pendingActionLifecycle[idx] = action
        } else {
            pendingActionLifecycle.insert(action, at: 0)
        }
        updateMessagePendingAction(action)
    }

    private func applyPendingActionStatus(
        _ status: PendingActionExecutionStatus,
        to actionId: String,
        responseStatus: String?,
        error: PendingActionErrorEnvelope?
    ) {
        guard let existing = pendingActionLifecycle.first(where: { $0.actionId == actionId }) else { return }
        var updated = existing
        updated.executionStatus = status
        updated.lastResponseStatus = responseStatus
        updated.error = error
        upsertPendingAction(updated)
    }

    private func updateMessagePendingAction(_ action: PendingActionContract) {
        for message in messages {
            if let idx = message.pendingActions.firstIndex(where: { $0.actionId == action.actionId }) {
                message.pendingActions[idx] = action
            }
        }
    }

    private func rebuildPendingActionLifecycle() {
        pendingActionLifecycle = messages
            .flatMap(\.pendingActions)
            .reduce(into: [PendingActionContract]()) { result, action in
                guard !result.contains(where: { $0.actionId == action.actionId }) else { return }
                result.append(action)
            }
    }

    // MARK: - Process SSE Event

    private func processEvent(_ event: SSEEvent, message: ChatMessage) {
        switch event {
        case .messageStart(let sid, let traceId):
            if sessionId != sid {
                sessionId = sid
            }
            updateActiveTurn { $0.traceId = traceId }
            transitionStream(
                .waiting,
                message: message,
                sourceStage: .bff,
                eventName: .messageStarted,
                details: "BFF/gateway stream opened"
            )

        case .firstToken(let latencyMs, let sourceStage, let mode):
            let resolvedMode = mode.flatMap(CoachTurnMode.init(rawValue:)) ?? currentTelemetryMode()
            let resolvedStage = sourceStage.flatMap(CoachTurnSourceStage.init(rawValue:)) ?? .llm
            let measuredLatency = appMeasuredFirstTokenLatencyMs()
            updateActiveTurn { $0.firstTokenRecorded = true }
            transitionStream(
                .firstTokenReceived,
                message: message,
                mode: resolvedMode,
                sourceStage: resolvedStage,
                eventName: .firstToken,
                latencyMs: measuredLatency,
                details: firstTokenDetails(sourceLatencyMs: latencyMs)
            )

        case .contentDelta(let text):
            if activeTurnTelemetry?.firstTokenRecorded != true {
                let latency = appMeasuredFirstTokenLatencyMs()
                updateActiveTurn { $0.firstTokenRecorded = true }
                transitionStream(
                    .firstTokenReceived,
                    message: message,
                    sourceStage: .llm,
                    eventName: .firstToken,
                    latencyMs: latency,
                    details: firstTokenDetails()
                )
            }
            message.content += text
            updateActiveTurn { $0.partialChunkCount += 1 }
            transitionStream(
                .partialResponse,
                message: message,
                sourceStage: .llm,
                eventName: .partialChunk,
                details: "Streaming partial response chunk"
            )
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
            let parsedPendingActions = PendingActionParse.actions(fromFunctionResult: result)
            appendPendingActions(parsedPendingActions, to: message)
            if !parsedPendingActions.isEmpty {
                transitionStream(
                    message.isStreaming ? .partialResponse : message.streamingPhase,
                    message: message,
                    sourceStage: .coachCore,
                    eventName: .pendingActionSurfaced,
                    details: "PendingAction surfaced; confirmation still required"
                )
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
            let failurePhase: CoachStreamingPhase = message.content.isEmpty ? .failed : .degraded
            transitionStream(
                failurePhase,
                message: message,
                mode: type == "rate_limit_exceeded" ? currentTelemetryMode() : .dataGap,
                sourceStage: CoachTurnSourceStage.fromStreamErrorType(type),
                eventName: failurePhase == .failed ? .failed : .degraded,
                details: errorMsg
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
        // Invalidate any in-flight restore so its late completion can't
        // repopulate or re-degrade the cleared thread, and re-enable input
        // immediately even if a restore is still suspended.
        restoreGeneration += 1
        isLoadingMessages = false
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        shouldSpeakNextCoachReply = false
        isStreaming = false
        messages.removeAll()
        sessionId = nil
        error = nil
        restoreError = nil
        didRestoreConversation = false
        lastSentMessageText = nil
        currentStage = nil
        completedStages = []
        streamingLifecycle = []
        activeTurnTelemetry = nil
        rateLimitInfo = nil
        pendingActionLifecycle.removeAll()
        pendingActionBusyIds.removeAll()
        voiceState = CoachVoiceState(
            lastSubmittedTranscript: voiceState.lastSubmittedTranscript,
            lastSpokenText: voiceState.lastSpokenText
        )
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
        shouldSpeakNextCoachReply = false
        isStreaming = false
        currentStage = nil
        completedStages = []
        // Stopping during the first-token wait must not leave a blank assistant
        // bubble behind — drop the empty placeholder instead of un-streaming it.
        if let last = messages.last, last.role == .assistant, last.content.isEmpty {
            transitionStream(
                .interrupted,
                message: last,
                sourceStage: .app,
                eventName: .interrupted,
                details: "Stopped before first token"
            )
            messages.removeLast()
        } else {
            if let last = messages.last, last.role == .assistant {
                transitionStream(
                    .interrupted,
                    message: last,
                    sourceStage: .app,
                    eventName: .interrupted,
                    details: "Stopped after partial response"
                )
                last.isStreaming = false
            } else {
                messages.last?.isStreaming = false
            }
        }
        activeTurnTelemetry = nil
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
    @Published var pendingActions: [PendingActionContract]
    @Published var tokensUsed: Int?
    @Published var latencyMs: Int?
    @Published var firstTokenLatencyMs: Int?
    @Published var streamingPhase: CoachStreamingPhase
    @Published var streamingMode: CoachTurnMode
    @Published var streamingSourceStage: CoachTurnSourceStage?
    @Published var isStreaming: Bool

    let suggestions: [CoachSuggestion]?
    let actionItems: [CoachActionItem]?

    init(
        role: ChatRole,
        content: String,
        suggestions: [CoachSuggestion]? = nil,
        actionItems: [CoachActionItem]? = nil,
        pendingActions: [PendingActionContract] = [],
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
        self.pendingActions = pendingActions
        self.tokensUsed = nil
        self.latencyMs = nil
        self.firstTokenLatencyMs = nil
        self.streamingPhase = isStreaming ? .waiting : .idle
        self.streamingMode = .live
        self.streamingSourceStage = nil
        self.isStreaming = isStreaming
        self.suggestions = suggestions
        self.actionItems = actionItems
    }
}

enum ChatRole {
    case user
    case assistant
}
