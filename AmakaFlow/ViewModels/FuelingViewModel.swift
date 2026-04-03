//
//  FuelingViewModel.swift
//  AmakaFlow
//
//  ViewModel for fueling status display (AMA-1293).
//  Calls GET /nutrition/fueling-status on chat-api.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Fueling Status Enum

enum FuelingStatus: String {
    case green
    case yellow
    case red
    case unknown

    init(from string: String) {
        self = FuelingStatus(rawValue: string) ?? .unknown
    }

    var color: Color {
        switch self {
        case .green: return Theme.Colors.accentGreen
        case .yellow: return Color(hex: "F59E0B")
        case .red: return Theme.Colors.accentRed
        case .unknown: return Theme.Colors.textSecondary
        }
    }

    var icon: String {
        switch self {
        case .green: return "checkmark.circle.fill"
        case .yellow: return "exclamationmark.triangle.fill"
        case .red: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class FuelingViewModel: ObservableObject {

    // MARK: - Dependencies

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    @Published var fuelingStatus: FuelingStatus = .unknown
    @Published var proteinPct: Double = 0
    @Published var caloriesPct: Double = 0
    @Published var hydrationPct: Double = 0
    @Published var message: String = "Loading..."
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Fetch

    func fetchFuelingStatus() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await dependencies.apiService.getFuelingStatus()
            fuelingStatus = FuelingStatus(from: response.status)
            proteinPct = response.proteinPct
            caloriesPct = response.caloriesPct
            hydrationPct = response.hydrationPct
            message = response.message
        } catch {
            print("[FuelingViewModel] fetch failed: \(error)")
            errorMessage = "Could not load fueling status"
            fuelingStatus = .unknown
            message = "Unavailable"
        }

        isLoading = false
    }

}
