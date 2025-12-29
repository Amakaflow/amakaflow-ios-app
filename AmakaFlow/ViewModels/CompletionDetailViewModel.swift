//
//  CompletionDetailViewModel.swift
//  AmakaFlow
//
//  ViewModel for workout completion detail view
//

import Foundation
import Combine

@MainActor
class CompletionDetailViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var detail: WorkoutCompletionDetail?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showStravaToast: Bool = false
    @Published var stravaToastMessage: String = ""

    // MARK: - Properties

    let completionId: String
    private let apiService = APIService.shared

    /// User's max heart rate for zone calculations (default: 190)
    var userMaxHR: Int = 190

    // MARK: - Computed Properties

    /// HR zones calculated from the detail data
    var hrZones: [HRZone] {
        detail?.calculateHRZones(maxHR: userMaxHR) ?? []
    }

    /// Whether the detail has loaded
    var isLoaded: Bool {
        detail != nil && !isLoading
    }

    /// Whether there's HR chart data to display
    var hasChartData: Bool {
        detail?.hasHeartRateSamples ?? false
    }

    /// Whether there's HR zone data to display (needs samples)
    var hasZoneData: Bool {
        hasChartData
    }

    /// Whether this can be synced to Strava
    var canSyncToStrava: Bool {
        guard let detail = detail else { return false }
        return !detail.syncedToStrava
    }

    /// Strava button text
    var stravaButtonText: String {
        guard let detail = detail else { return "Sync to Strava" }
        return detail.syncedToStrava ? "View on Strava" : "Sync to Strava"
    }

    // MARK: - Initialization

    init(completionId: String) {
        self.completionId = completionId
    }

    // MARK: - Data Loading

    /// Load the full completion detail from API
    func loadDetail() async {
        isLoading = true
        errorMessage = nil

        // Check if paired
        if !PairingService.shared.isPaired {
            loadMockData()
            isLoading = false
            return
        }

        do {
            detail = try await apiService.fetchCompletionDetail(id: completionId)
        } catch let error as APIError {
            handleAPIError(error)
        } catch {
            errorMessage = "Failed to load details: \(error.localizedDescription)"
            loadMockData()
        }

        isLoading = false
    }

    /// Refresh the detail data
    func refresh() async {
        await loadDetail()
    }

    // MARK: - Strava Actions

    /// Sync this workout to Strava
    func syncToStrava() async {
        guard canSyncToStrava else {
            // Already synced, open in Strava
            openInStrava()
            return
        }

        // TODO: Implement actual Strava sync (separate issue)
        stravaToastMessage = "Strava sync coming soon!"
        showStravaToast = true

        // Hide toast after delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        showStravaToast = false
    }

    /// Open the activity in Strava app/web
    func openInStrava() {
        guard let detail = detail,
              detail.syncedToStrava,
              let activityId = detail.stravaActivityId else {
            return
        }

        // Strava URL scheme: strava://activities/{id}
        // Fallback to web: https://www.strava.com/activities/{id}
        let stravaURL = URL(string: "strava://activities/\(activityId)")
        let webURL = URL(string: "https://www.strava.com/activities/\(activityId)")

        // Try opening in Strava app first
        #if os(iOS)
        if let stravaURL = stravaURL {
            Task { @MainActor in
                if await UIApplication.shared.canOpenURL(stravaURL) {
                    await UIApplication.shared.open(stravaURL)
                } else if let webURL = webURL {
                    await UIApplication.shared.open(webURL)
                }
            }
        }
        #endif
    }

    // MARK: - Error Handling

    private func handleAPIError(_ error: APIError) {
        switch error {
        case .unauthorized:
            errorMessage = "Session expired. Please reconnect."
        case .networkError:
            errorMessage = "Network error. Please check your connection."
        case .notFound:
            errorMessage = "Workout not found."
        default:
            errorMessage = error.localizedDescription
        }
        loadMockData()
    }

    // MARK: - Mock Data

    private func loadMockData() {
        detail = WorkoutCompletionDetail.sample
    }
}

// MARK: - API Service Extension

extension APIService {
    /// Fetch full workout completion detail from backend
    /// - Parameter id: The completion ID to fetch
    /// - Returns: WorkoutCompletionDetail with full HR samples
    /// - Throws: APIError if request fails
    func fetchCompletionDetail(id: String) async throws -> WorkoutCompletionDetail {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let baseURL = AppEnvironment.current.mapperAPIURL
        let url = URL(string: "\(baseURL)/workouts/completions/\(id)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = PairingService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WorkoutCompletionDetail.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}
