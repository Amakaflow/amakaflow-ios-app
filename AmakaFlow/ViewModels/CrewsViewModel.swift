//
//  CrewsViewModel.swift
//  AmakaFlow
//
//  ViewModel for Training Crews — private groups with shared feed (AMA-1277)
//

import Foundation
import Combine

@MainActor
class CrewsViewModel: ObservableObject {
    @Published var crews: [Crew] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Detail state
    @Published var selectedCrewDetail: CrewDetail?
    @Published var isLoadingDetail = false
    @Published var crewFeedPosts: [CrewFeedPost] = []
    @Published var isLoadingFeed = false

    // Creation state
    @Published var isCreating = false
    @Published var createError: String?

    // Join state
    @Published var isJoining = false
    @Published var joinError: String?
    @Published var joinSuccess = false

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - List Crews

    func loadCrews() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await dependencies.apiService.fetchMyCrews()
            crews = response.crews
        } catch {
            errorMessage = "Could not load crews: \(error.localizedDescription)"
            print("[CrewsViewModel] loadCrews failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Crew Detail

    func loadCrewDetail(id: String) async {
        isLoadingDetail = true

        do {
            let detail = try await dependencies.apiService.fetchCrewDetail(id: id)
            selectedCrewDetail = detail
        } catch {
            errorMessage = "Could not load crew: \(error.localizedDescription)"
            print("[CrewsViewModel] loadCrewDetail failed: \(error)")
        }

        isLoadingDetail = false
    }

    // MARK: - Crew Feed

    func loadCrewFeed(crewId: String) async {
        isLoadingFeed = true

        do {
            let response = try await dependencies.apiService.fetchCrewFeed(crewId: crewId)
            crewFeedPosts = response.posts
        } catch {
            errorMessage = "Could not load feed: \(error.localizedDescription)"
            print("[CrewsViewModel] loadCrewFeed failed: \(error)")
        }

        isLoadingFeed = false
    }

    // MARK: - Create Crew

    func createCrew(name: String, description: String?, maxMembers: Int) async -> Bool {
        isCreating = true
        createError = nil

        do {
            let request = CreateCrewRequest(name: name, description: description, maxMembers: maxMembers)
            try await dependencies.apiService.createCrew(request)
            await loadCrews()
            isCreating = false
            return true
        } catch {
            createError = "Could not create crew: \(error.localizedDescription)"
            print("[CrewsViewModel] createCrew failed: \(error)")
            isCreating = false
            return false
        }
    }

    // MARK: - Join Crew

    func joinCrew(crewId: String, inviteCode: String) async -> Bool {
        isJoining = true
        joinError = nil
        joinSuccess = false

        do {
            let request = JoinCrewRequest(inviteCode: inviteCode)
            try await dependencies.apiService.joinCrew(crewId: crewId, request: request)
            joinSuccess = true
            await loadCrews()
            isJoining = false
            return true
        } catch {
            joinError = "Could not join crew: \(error.localizedDescription)"
            print("[CrewsViewModel] joinCrew failed: \(error)")
            isJoining = false
            return false
        }
    }

    // MARK: - Leave Crew

    func leaveCrew(crewId: String) async -> Bool {
        do {
            try await dependencies.apiService.leaveCrew(crewId: crewId)
            await loadCrews()
            return true
        } catch {
            errorMessage = "Could not leave crew: \(error.localizedDescription)"
            print("[CrewsViewModel] leaveCrew failed: \(error)")
            return false
        }
    }
}
