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

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func loadShoes() async {
        isLoading = true
        errorMessage = nil

        do {
            shoes = try await dependencies.apiService.fetchShoeComparison()
        } catch {
            errorMessage = "Could not load shoe data: \(error.localizedDescription)"
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
