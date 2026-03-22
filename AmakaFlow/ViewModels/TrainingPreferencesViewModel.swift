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
    @Published var saveSuccess = false

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func loadPreferences() async {
        isLoading = true
        errorMessage = nil

        do {
            preferences = try await dependencies.apiService.fetchNotificationPreferences()
        } catch {
            print("[TrainingPreferencesViewModel] loadPreferences failed: \(error)")
        }

        isLoading = false
    }

    func savePreferences() async {
        isSaving = true
        errorMessage = nil
        saveSuccess = false

        do {
            preferences = try await dependencies.apiService.updateNotificationPreferences(preferences)
            saveSuccess = true
        } catch {
            errorMessage = "Could not save preferences: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
