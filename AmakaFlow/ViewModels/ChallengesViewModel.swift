//
//  ChallengesViewModel.swift
//  AmakaFlow
//
//  ViewModel for community challenges — browse, join, track, celebrate (AMA-1276)
//

import Foundation
import Combine

@MainActor
class ChallengesViewModel: ObservableObject {
    @Published var challenges: [Challenge] = []
    @Published var filteredChallenges: [Challenge] = []
    @Published var selectedTypeFilter: ChallengeType?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Detail state
    @Published var selectedChallenge: ChallengeDetailResponse?
    @Published var isLoadingDetail = false
    @Published var isJoining = false

    // Creation state
    @Published var isCreating = false
    @Published var createError: String?

    // Celebration state
    @Published var showCelebration = false
    @Published var completedBadge: ChallengeBadge?

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Challenge List

    func loadChallenges() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await dependencies.apiService.fetchChallenges()
            challenges = response.challenges
            applyFilter()
        } catch {
            errorMessage = "Could not load challenges: \(error.localizedDescription)"
            print("[ChallengesViewModel] loadChallenges failed: \(error)")
        }

        isLoading = false
    }

    func setTypeFilter(_ type: ChallengeType?) {
        selectedTypeFilter = type
        applyFilter()
    }

    private func applyFilter() {
        if let filter = selectedTypeFilter {
            filteredChallenges = challenges.filter { $0.type == filter }
        } else {
            filteredChallenges = challenges
        }
    }

    // MARK: - Challenge Detail

    func loadChallengeDetail(id: String) async {
        isLoadingDetail = true

        do {
            let response = try await dependencies.apiService.fetchChallengeDetail(id: id)
            selectedChallenge = response

            // Check for completion celebration
            if let progress = response.myProgress, progress.isCompleted, progress.badge != nil {
                completedBadge = progress.badge
                showCelebration = true
            }
        } catch {
            errorMessage = "Could not load challenge: \(error.localizedDescription)"
            print("[ChallengesViewModel] loadChallengeDetail failed: \(error)")
        }

        isLoadingDetail = false
    }

    // MARK: - Join Challenge

    func joinChallenge(id: String) async {
        isJoining = true

        do {
            try await dependencies.apiService.joinChallenge(id: id)
            // Reload detail to reflect joined state
            await loadChallengeDetail(id: id)
            // Reload list to update join status
            await loadChallenges()
        } catch {
            errorMessage = "Could not join challenge: \(error.localizedDescription)"
            print("[ChallengesViewModel] joinChallenge failed: \(error)")
        }

        isJoining = false
    }

    // MARK: - Create Challenge

    func createChallenge(_ request: CreateChallengeRequest) async -> Bool {
        isCreating = true
        createError = nil

        do {
            try await dependencies.apiService.createChallenge(request)
            await loadChallenges()
            isCreating = false
            return true
        } catch {
            createError = "Could not create challenge: \(error.localizedDescription)"
            print("[ChallengesViewModel] createChallenge failed: \(error)")
            isCreating = false
            return false
        }
    }

    // MARK: - Celebration

    func dismissCelebration() {
        showCelebration = false
        completedBadge = nil
    }
}
