//
//  CoachViewModel.swift
//  AmakaFlow
//
//  ViewModel for AI coach chat and fatigue advice (AMA-1147)
//

import Foundation
import Combine

@MainActor
class CoachViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var fatigueAdvice: FatigueAdvice?
    @Published var isLoadingAdvice = false
    @Published var errorMessage: String?
    @Published var coachMemories: [CoachMemory] = []
    @Published var messageCount = 0
    @Published var rateLimitHit = false

    /// Maximum messages per session before warning
    static let rateLimitWarningThreshold = 20

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Chat

    func sendMessage(_ text: String) async {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        isLoading = true
        errorMessage = nil
        messageCount += 1

        do {
            let response = try await dependencies.apiService.sendCoachMessage(message: text)
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response.message,
                suggestions: response.suggestions,
                actionItems: response.actionItems
            )
            messages.append(assistantMessage)
            rateLimitHit = false
        } catch {
            if (error as? APIError)?.errorDescription?.contains("429") == true ||
               error.localizedDescription.contains("rate") {
                rateLimitHit = true
                errorMessage = "Rate limit reached. Please wait a moment before sending more messages."
            } else {
                errorMessage = "Could not reach coach: \(error.localizedDescription)"
            }
            print("[CoachViewModel] sendMessage failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Coach Memory

    func loadCoachMemories() async {
        do {
            coachMemories = try await dependencies.apiService.fetchCoachMemories()
        } catch {
            print("[CoachViewModel] loadCoachMemories failed: \(error)")
        }
    }

    /// Whether the user is approaching the rate limit
    var isNearRateLimit: Bool {
        messageCount >= Self.rateLimitWarningThreshold
    }

    // MARK: - Fatigue Advice

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

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let timestamp = Date()
    let suggestions: [CoachSuggestion]?
    let actionItems: [CoachActionItem]?

    init(role: ChatRole, content: String, suggestions: [CoachSuggestion]? = nil, actionItems: [CoachActionItem]? = nil) {
        self.role = role
        self.content = content
        self.suggestions = suggestions
        self.actionItems = actionItems
    }
}

enum ChatRole {
    case user
    case assistant
}
