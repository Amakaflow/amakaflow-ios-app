//
//  ActivityFeedViewModel.swift
//  AmakaFlow
//
//  ViewModel for agent actions / activity feed (AMA-1956)
//

import Foundation
import Combine

@MainActor
class ActivityFeedViewModel: ObservableObject {
    @Published var actions: [AgentAction] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func loadActions() async {
        isLoading = true
        errorMessage = nil

        do {
            actions = try await dependencies.apiService.fetchAgentActions(status: nil)
        } catch {
            errorMessage = "Could not load activity feed: \(error.localizedDescription)"
            print("[ActivityFeedViewModel] loadActions failed: \(error)")
        }

        isLoading = false
    }

    func approveAction(_ action: AgentAction) async {
        do {
            _ = try await dependencies.apiService.respondToAction(id: action.id, decision: "approve")
            await loadActions()
        } catch {
            errorMessage = "Could not approve action: \(error.localizedDescription)"
        }
    }

    func rejectAction(_ action: AgentAction) async {
        do {
            _ = try await dependencies.apiService.respondToAction(id: action.id, decision: "reject")
            await loadActions()
        } catch {
            errorMessage = "Could not reject action: \(error.localizedDescription)"
        }
    }

    func undoAction(_ action: AgentAction) async {
        do {
            _ = try await dependencies.apiService.undoAction(id: action.id)
            await loadActions()
        } catch {
            errorMessage = "Could not undo action: \(error.localizedDescription)"
        }
    }
}
