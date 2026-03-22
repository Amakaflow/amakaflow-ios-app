//
//  ActivityFeedViewModel.swift
//  AmakaFlow
//
//  ViewModel for pending actions / activity feed (AMA-1147)
//

import Foundation
import Combine

@MainActor
class ActivityFeedViewModel: ObservableObject {
    @Published var actions: [PendingAction] = []
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
            actions = try await dependencies.apiService.fetchPendingActions()
        } catch {
            errorMessage = "Could not load activity feed: \(error.localizedDescription)"
            print("[ActivityFeedViewModel] loadActions failed: \(error)")
        }

        isLoading = false
    }

    func approveAction(_ action: PendingAction) async {
        do {
            _ = try await dependencies.apiService.respondToAction(id: action.id, response: "approve")
            await loadActions()
        } catch {
            errorMessage = "Could not approve action: \(error.localizedDescription)"
        }
    }

    func rejectAction(_ action: PendingAction) async {
        do {
            _ = try await dependencies.apiService.respondToAction(id: action.id, response: "reject")
            await loadActions()
        } catch {
            errorMessage = "Could not reject action: \(error.localizedDescription)"
        }
    }

    func undoAction(_ action: PendingAction) async {
        do {
            _ = try await dependencies.apiService.respondToAction(id: action.id, response: "undo")
            await loadActions()
        } catch {
            errorMessage = "Could not undo action: \(error.localizedDescription)"
        }
    }
}
