//
//  LeaderboardViewModel.swift
//  AmakaFlow
//
//  ViewModel for multi-dimension leaderboards (AMA-1278)
//

import Foundation
import Combine

@MainActor
class LeaderboardViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntryModel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var selectedDimension: LeaderboardDimension = .volume
    @Published var selectedPeriod: LeaderboardPeriod = .month
    @Published var selectedScope: LeaderboardScope = .friends

    /// Crew ID for crew-scoped leaderboards
    var crewId: String?

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live, crewId: String? = nil) {
        self.dependencies = dependencies
        self.crewId = crewId
    }

    // MARK: - Load Leaderboard

    func loadLeaderboard() async {
        isLoading = true
        errorMessage = nil

        do {
            let response: LeaderboardAPIResponse
            switch selectedScope {
            case .friends:
                response = try await dependencies.apiService.fetchFriendsLeaderboard(
                    dimension: selectedDimension.rawValue,
                    period: selectedPeriod.rawValue
                )
            case .crew:
                guard let crewId = crewId else {
                    errorMessage = "No crew selected"
                    isLoading = false
                    return
                }
                response = try await dependencies.apiService.fetchCrewLeaderboard(
                    crewId: crewId,
                    dimension: selectedDimension.rawValue,
                    period: selectedPeriod.rawValue
                )
            }
            entries = response.entries
        } catch {
            errorMessage = "Could not load leaderboard: \(error.localizedDescription)"
            print("[LeaderboardViewModel] loadLeaderboard failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Dimension / Period changes

    func changeDimension(_ dimension: LeaderboardDimension) async {
        selectedDimension = dimension
        await loadLeaderboard()
    }

    func changePeriod(_ period: LeaderboardPeriod) async {
        selectedPeriod = period
        await loadLeaderboard()
    }

    func changeScope(_ scope: LeaderboardScope) async {
        selectedScope = scope
        await loadLeaderboard()
    }

    // MARK: - Formatting

    func formattedValue(_ entry: LeaderboardEntryModel) -> String {
        switch selectedDimension {
        case .volume:
            if entry.value >= 1000 {
                return String(format: "%.1fk kg", entry.value / 1000)
            }
            return String(format: "%.0f kg", entry.value)
        case .consistency:
            let weeks = Int(entry.value)
            return "\(weeks) \(weeks == 1 ? "week" : "weeks")"
        case .prs:
            return "\(Int(entry.value)) PRs"
        case .workouts:
            return "\(Int(entry.value))"
        }
    }
}
