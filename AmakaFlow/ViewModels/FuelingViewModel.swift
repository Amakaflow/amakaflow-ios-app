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

// MARK: - API Response Models

struct FuelingStatusResponse: Codable, Equatable {
    let status: String          // "green" | "yellow" | "red"
    let proteinPct: Double
    let caloriesPct: Double
    let hydrationPct: Double
    let message: String

    enum CodingKeys: String, CodingKey {
        case status
        case proteinPct = "protein_pct"
        case caloriesPct = "calories_pct"
        case hydrationPct = "hydration_pct"
        case message
    }
}

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
            let response = try await getFuelingStatus()
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

    // MARK: - API

    private func getFuelingStatus() async throws -> FuelingStatusResponse {
        let baseURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(baseURL)/nutrition/fueling-status") else {
            throw APIError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        #if DEBUG
        if let testAuthSecret = TestAuthStore.shared.authSecret,
           let testUserId = TestAuthStore.shared.userId,
           !testAuthSecret.isEmpty {
            urlRequest.setValue(testAuthSecret, forHTTPHeaderField: "X-Test-Auth")
            urlRequest.setValue(testUserId, forHTTPHeaderField: "X-Test-User-Id")
        } else if let token = PairingService.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #else
        if let token = PairingService.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #endif

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            print("[FuelingViewModel] API error \(httpResponse.statusCode): \(body)")
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FuelingStatusResponse.self, from: data)
    }
}
