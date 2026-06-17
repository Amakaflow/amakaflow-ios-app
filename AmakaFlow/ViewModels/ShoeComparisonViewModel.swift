//
//  ShoeComparisonViewModel.swift
//  AmakaFlow
//
//  ViewModel for shoe comparison analytics (AMA-1147)
//

import Foundation
import Combine

@MainActor
class ShoeComparisonViewModel: ObservableObject {
    @Published var shoes: [ShoeStats] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var apiErrorDisplay: APIErrorDisplayState?

    private let apiErrorState = APIErrorState()
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .current) {
        self.dependencies = dependencies
    }

    func loadShoes() async {
        isLoading = true
        errorMessage = nil
        apiErrorDisplay = nil
        apiErrorState.clear()

        do {
            shoes = try await dependencies.apiService.fetchShoeComparison()
        } catch {
            apiErrorState.present(error)
            apiErrorDisplay = apiErrorState.current
            errorMessage = apiErrorDisplay?.message ?? "Could not load shoe data"
            print("[ShoeComparisonViewModel] loadShoes failed: \(error)")
        }

        isLoading = false
    }

    var totalDistance: Double {
        shoes.reduce(0) { $0 + $1.totalDistanceKm }
    }

    var totalRuns: Int {
        shoes.reduce(0) { $0 + $1.totalRuns }
    }
}
