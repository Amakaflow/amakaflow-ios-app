//
//  CompletionDetailViewModel.swift
//  AmakaFlow
//
//  ViewModel for workout completion detail view
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
class CompletionDetailViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var detail: WorkoutCompletionDetail?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showStravaToast: Bool = false
    @Published var stravaToastMessage: String = ""
    @Published var isSavingToLibrary: Bool = false
    @Published var showSaveToast: Bool = false
    @Published var saveToastMessage: String = ""

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
        return !detail.isSyncedToStrava
    }

    /// Strava button text
    var stravaButtonText: String {
        guard let detail = detail else { return "Sync to Strava" }
        return detail.isSyncedToStrava ? "View on Strava" : "Sync to Strava"
    }

    /// Whether this workout can be saved to the library (voice-added workouts only)
    var canSaveToLibrary: Bool {
        guard let detail = detail else { return false }
        // Can save if:
        // 1. Not already from library (workoutId is nil)
        // 2. Has intervals to save (workout structure exists)
        return detail.workoutId == nil && detail.hasWorkoutSteps
    }

    // MARK: - Initialization

    init(completionId: String) {
        self.completionId = completionId
    }

    // MARK: - Data Loading

    /// Set to true to force mock data for testing (AMA-224)
    #if DEBUG
    static var forceMockData = false
    #endif

    /// Load the full completion detail from API
    func loadDetail() async {
        isLoading = true
        errorMessage = nil

        #if DEBUG
        // Force mock data for testing the full UI (AMA-224)
        if Self.forceMockData {
            loadMockData()
            isLoading = false
            return
        }
        #endif

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
              detail.isSyncedToStrava,
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

    // MARK: - Save to Library

    /// Save this workout to the user's library
    func saveToLibrary() async {
        guard canSaveToLibrary, let detail = detail, let intervals = detail.intervals else {
            return
        }

        isSavingToLibrary = true

        // Create a Workout from the completion detail
        let workout = Workout(
            id: UUID().uuidString,
            name: detail.workoutName,
            sport: inferSportFromIntervals(intervals),
            duration: detail.durationSeconds,
            intervals: intervals,
            description: nil,
            source: .ai,  // Voice-added workouts are AI-generated
            sourceUrl: nil
        )

        do {
            try await apiService.syncWorkout(workout)
            saveToastMessage = "Saved to My Workouts!"
            showSaveToast = true

            // Update the detail to reflect it's now in library
            // (prevents showing the button again)
            self.detail = WorkoutCompletionDetail(
                id: detail.id,
                workoutName: detail.workoutName,
                startedAt: detail.startedAt,
                endedAt: detail.endedAt,
                durationSeconds: detail.durationSeconds,
                avgHeartRate: detail.avgHeartRate,
                maxHeartRate: detail.maxHeartRate,
                minHeartRate: detail.minHeartRate,
                activeCalories: detail.activeCalories,
                totalCalories: detail.totalCalories,
                steps: detail.steps,
                distanceMeters: detail.distanceMeters,
                source: detail.source,
                deviceInfo: detail.deviceInfo,
                heartRateSamples: detail.heartRateSamples,
                syncedToStrava: detail.syncedToStrava,
                stravaActivityId: detail.stravaActivityId,
                workoutId: workout.id,  // Now linked to library
                intervals: detail.intervals
            )
        } catch {
            saveToastMessage = "Failed to save: \(error.localizedDescription)"
            showSaveToast = true
        }

        isSavingToLibrary = false

        // Hide toast after delay
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        showSaveToast = false
    }

    /// Infer sport type from workout intervals
    private func inferSportFromIntervals(_ intervals: [WorkoutInterval]) -> WorkoutSport {
        // Check for strength indicators (reps-based exercises)
        let hasReps = intervals.contains { interval in
            if case .reps = interval { return true }
            return false
        }

        // Check for cardio indicators (distance-based)
        let hasDistance = intervals.contains { interval in
            if case .distance = interval { return true }
            return false
        }

        if hasReps {
            return .strength
        } else if hasDistance {
            return .running
        } else {
            return .cardio  // Default for time-based workouts
        }
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

import os.log

private let detailLogger = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "CompletionDetail")

/// Backend returns completion detail wrapped in { "success": true, "completion": {...} }
private struct CompletionDetailResponse: Codable {
    let success: Bool
    let completion: WorkoutCompletionDetail
}

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

        let responseBody = String(data: data, encoding: .utf8) ?? "empty"
        print("[CompletionDetail] fetchCompletionDetail - Status: \(httpResponse.statusCode)")
        print("[CompletionDetail] Response: \(responseBody.prefix(500))")
        detailLogger.info("fetchCompletionDetail - Status: \(httpResponse.statusCode), Body: \(responseBody)")

        switch httpResponse.statusCode {
        case 200:
            let decoder = APIService.makeDecoder()

            // Try wrapped format first: { "success": true, "completion": {...} }
            do {
                let wrappedResponse = try decoder.decode(CompletionDetailResponse.self, from: data)
                print("[CompletionDetail] Successfully decoded wrapped completion detail")
                return wrappedResponse.completion
            } catch let wrappedError as DecodingError {
                // Log detailed wrapped decode error
                var errorMsg = ""
                switch wrappedError {
                case .typeMismatch(let type, let context):
                    errorMsg = "Type mismatch: expected \(String(describing: type)) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                case .valueNotFound(let type, let context):
                    errorMsg = "Value not found: \(String(describing: type)) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                case .keyNotFound(let key, let context):
                    errorMsg = "Key not found: '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                case .dataCorrupted(let context):
                    errorMsg = "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
                @unknown default:
                    errorMsg = "Unknown: \(wrappedError.localizedDescription)"
                }
                print("[CompletionDetail] Wrapped decode failed: \(errorMsg)")

                // Log to DebugLogService for visibility
                Task { @MainActor in
                    DebugLogService.shared.log(
                        "WRAPPED DECODE: \(errorMsg)",
                        details: String(responseBody.prefix(2000)),
                        metadata: ["Endpoint": "/workouts/completions/\(id)"]
                    )
                }
                throw wrappedError  // Don't try direct decode, the wrapped format is what backend returns
            } catch {
                print("[CompletionDetail] Wrapped decode failed with non-decoding error: \(error)")
                throw error
            }
        case 401:
            throw APIError.unauthorized
        case 404:
            detailLogger.warning("fetchCompletionDetail - 404 Not Found for ID: \(id)")
            throw APIError.notFound
        default:
            detailLogger.error("fetchCompletionDetail - Server error \(httpResponse.statusCode): \(responseBody)")
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}
