//
//  BulkImportViewModel.swift
//  AmakaFlow
//
//  ViewModel for the 5-step bulk import wizard (AMA-1415)
//

import Foundation
import Combine

@MainActor
class BulkImportViewModel: ObservableObject {

    // MARK: - Step

    enum Step: Int, CaseIterable {
        case source
        case detect
        case match
        case preview
        case importing

        var title: String {
            switch self {
            case .source: return "Source"
            case .detect: return "Detection"
            case .match: return "Matching"
            case .preview: return "Preview"
            case .importing: return "Importing"
            }
        }
    }

    // MARK: - Published — Navigation & State

    @Published var currentStep: Step = .source
    @Published var inputType: BulkInputType = .urls
    @Published var urlInputs: [String] = [""]
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Published — Detection

    @Published var jobId: String?
    @Published var detectedItems: [DetectedItem] = []

    // MARK: - Published — Matching

    @Published var exerciseMatches: [ExerciseMatch] = []
    @Published var matchStats: (matched: Int, needsReview: Int, total: Int)?

    // MARK: - Published — Preview

    @Published var previewWorkouts: [PreviewWorkout] = []
    @Published var importStats: ImportStats?

    // MARK: - Published — Import

    @Published var importProgress: Int = 0
    @Published var importResults: [ImportResult] = []
    @Published var importComplete: Bool = false

    // MARK: - Private

    private let dependencies: AppDependencies
    private var pollingTask: Task<Void, Never>?

    // MARK: - Init

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - URL Input Management

    func addURL() {
        urlInputs.append("")
    }

    func removeURL(at index: Int) {
        guard urlInputs.indices.contains(index), urlInputs.count > 1 else { return }
        urlInputs.remove(at: index)
    }

    // MARK: - Exercise Mapping

    func updateExerciseMapping(exerciseId: String, garminName: String) {
        if let idx = exerciseMatches.firstIndex(where: { $0.id == exerciseId }) {
            exerciseMatches[idx].userSelection = garminName
        }
    }

    // MARK: - Workout Selection

    func toggleWorkoutSelection(_ id: String) {
        if let idx = previewWorkouts.firstIndex(where: { $0.id == id }) {
            previewWorkouts[idx].selected.toggle()
        }
    }

    // MARK: - Step 1 → 2: Detect

    func detect() async {
        guard let profileId = dependencies.pairingService.userProfile?.id, !profileId.isEmpty else {
            errorMessage = "Not authenticated. Please pair your device first."
            return
        }

        let validURLs = urlInputs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !validURLs.isEmpty else {
            errorMessage = "Please enter at least one URL."
            return
        }

        isLoading = true
        errorMessage = nil
        let request = BulkDetectRequest(
            profileId: profileId,
            sourceType: inputType.rawValue,
            sources: validURLs
        )

        do {
            let response = try await dependencies.apiService.detectImport(request: request)
            jobId = response.jobId
            detectedItems = response.items
            currentStep = .detect
            print("[BulkImportViewModel] Detected \(response.items.count) items, jobId: \(response.jobId)")
        } catch {
            errorMessage = "Detection failed: \(error.localizedDescription)"
            print("[BulkImportViewModel] detectImport error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Step 2 → 3: Match Exercises

    func matchExercises() async {
        guard let profileId = dependencies.pairingService.userProfile?.id, !profileId.isEmpty else {
            errorMessage = "Not authenticated. Please pair your device first."
            return
        }
        guard let currentJobId = jobId else { return }

        isLoading = true
        errorMessage = nil
        let request = BulkMatchRequest(
            jobId: currentJobId,
            profileId: profileId,
            userMappings: nil
        )

        do {
            let response = try await dependencies.apiService.matchExercises(request: request)
            exerciseMatches = response.exercises
            matchStats = (matched: response.matched, needsReview: response.needsReview, total: response.totalExercises)
            currentStep = .match
            print("[BulkImportViewModel] Matched \(response.matched)/\(response.totalExercises) exercises")
        } catch {
            errorMessage = "Exercise matching failed: \(error.localizedDescription)"
            print("[BulkImportViewModel] matchExercises error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Step 3 → 4: Preview

    func preview() async {
        guard let profileId = dependencies.pairingService.userProfile?.id, !profileId.isEmpty else {
            errorMessage = "Not authenticated. Please pair your device first."
            return
        }
        guard let currentJobId = jobId else { return }

        isLoading = true
        errorMessage = nil
        let selectedIds = detectedItems.map { $0.id }
        let request = BulkPreviewRequest(
            jobId: currentJobId,
            profileId: profileId,
            selectedIds: selectedIds
        )

        do {
            let response = try await dependencies.apiService.previewImport(request: request)
            previewWorkouts = response.workouts
            importStats = response.stats
            currentStep = .preview
            print("[BulkImportViewModel] Preview: \(response.workouts.count) workouts")
        } catch {
            errorMessage = "Preview failed: \(error.localizedDescription)"
            print("[BulkImportViewModel] previewImport error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Step 4 → 5: Execute Import

    func executeImport() async {
        guard let profileId = dependencies.pairingService.userProfile?.id, !profileId.isEmpty else {
            errorMessage = "Not authenticated. Please pair your device first."
            return
        }
        guard let currentJobId = jobId else { return }

        let selectedIds = previewWorkouts.filter { $0.selected }.map { $0.id }
        guard !selectedIds.isEmpty else {
            errorMessage = "Please select at least one workout to import."
            return
        }

        isLoading = true
        errorMessage = nil
        importProgress = 0
        importComplete = false
        currentStep = .importing
        let request = BulkExecuteRequest(
            jobId: currentJobId,
            profileId: profileId,
            workoutIds: selectedIds,
            device: "ios"
        )

        do {
            _ = try await dependencies.apiService.executeImport(request: request)
            print("[BulkImportViewModel] Import started, beginning poll")
            startPolling(jobId: currentJobId, profileId: profileId)
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
            print("[BulkImportViewModel] executeImport error: \(error)")
            isLoading = false
        }
    }

    // MARK: - Cancel Import

    func cancelImport() {
        pollingTask?.cancel()
        pollingTask = nil
        isLoading = false
        importComplete = true  // Mark as terminal so view shows done state
        if importResults.isEmpty {
            errorMessage = "Import cancelled"
        }

        guard let currentJobId = jobId,
              let profileId = dependencies.pairingService.userProfile?.id else { return }

        Task {
            do {
                try await dependencies.apiService.cancelImport(jobId: currentJobId, profileId: profileId)
                print("[BulkImportViewModel] Import cancelled")
            } catch {
                print("[BulkImportViewModel] cancelImport error (non-fatal): \(error)")
            }
        }
    }

    // MARK: - Polling

    private func startPolling(jobId: String, profileId: String) {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    let status = try await dependencies.apiService.fetchImportStatus(
                        jobId: jobId,
                        profileId: profileId
                    )
                    importProgress = status.progress
                    if let results = status.results {
                        importResults = results
                    }

                    print("[BulkImportViewModel] Poll status: \(status.status), progress: \(status.progress)%")

                    switch status.status {
                    case "complete":
                        importComplete = true
                        isLoading = false
                        return
                    case "failed", "cancelled":
                        errorMessage = status.error ?? "Import \(status.status)"
                        isLoading = false
                        return
                    default:
                        // still running — wait 2 seconds before next poll
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    print("[BulkImportViewModel] Poll error: \(error)")
                    errorMessage = "Failed to get import status: \(error.localizedDescription)"
                    isLoading = false
                    return
                }
            }
        }
    }
}
