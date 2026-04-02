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
                if assistantMessage.content.isEmpty {
                    if let idx = messages.lastIndex(where: { $0.id == assistantMessage.id }) {
                        messages.remove(at: idx)
                    }
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
