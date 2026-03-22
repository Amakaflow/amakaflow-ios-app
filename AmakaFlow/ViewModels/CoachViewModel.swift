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

        do {
            let response = try await dependencies.apiService.sendCoachMessage(message: text)
            let assistantMessage = ChatMessage(role: .assistant, content: response.message)
            messages.append(assistantMessage)
        } catch {
            errorMessage = "Could not reach coach: \(error.localizedDescription)"
            print("[CoachViewModel] sendMessage failed: \(error)")
        }

        isLoading = false
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
}

enum ChatRole {
    case user
    case assistant
}
