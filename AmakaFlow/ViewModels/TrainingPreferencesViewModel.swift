//
//  TrainingPreferencesViewModel.swift
//  AmakaFlow
//
//  ViewModel for notification/training preferences (AMA-1147)
//

import Foundation
import Combine

@MainActor
class TrainingPreferencesViewModel: ObservableObject {
    @Published var preferences = NotificationPreferences()
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var apiErrorDisplay: APIErrorDisplayState?
    @Published var saveSuccess = false

    private let apiErrorState = APIErrorState()
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func loadPreferences() async {
        isLoading = true
        errorMessage = nil
        apiErrorDisplay = nil
        apiErrorState.clear()

        do {
            preferences = try await dependencies.apiService.fetchNotificationPreferences()
        } catch {
            apiErrorState.present(error)
            apiErrorDisplay = apiErrorState.current
            errorMessage = apiErrorDisplay?.message ?? "Could not load preferences"
            print("[TrainingPreferencesViewModel] loadPreferences failed: \(error)")
        }

        isLoading = false
    }

    func savePreferences() async {
        isSaving = true
        errorMessage = nil
        apiErrorDisplay = nil
        apiErrorState.clear()
        saveSuccess = false

        do {
            preferences = try await dependencies.apiService.updateNotificationPreferences(preferences)
            saveSuccess = true
        } catch {
            apiErrorState.present(error)
            apiErrorDisplay = apiErrorState.current
            errorMessage = apiErrorDisplay?.message ?? "Could not save preferences"
        }

        isSaving = false
    }
}
