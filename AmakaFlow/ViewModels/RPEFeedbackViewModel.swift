//
//  RPEFeedbackViewModel.swift
//  AmakaFlow
//
//  ViewModel for post-workout RPE feedback (AMA-1266)
//  Calls POST /coach/rpe-feedback on chat-api
//

import Foundation
import Combine

/// RPE difficulty option for quick selection
enum RPEOption: CaseIterable, Identifiable {
    case easy       // RPE 3-4
    case moderate   // RPE 5-6
    case hard       // RPE 7-8
    case crushed    // RPE 9-10

    var id: String { label }

    var emoji: String {
        switch self {
        case .easy: return "\u{1F60A}"
        case .moderate: return "\u{1F4AA}"
        case .hard: return "\u{1F525}"
        case .crushed: return "\u{1F480}"
        }
    }

    var label: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .crushed: return "Crushed"
        }
    }

    var rpeValue: Int {
        switch self {
        case .easy: return 4
        case .moderate: return 6
        case .hard: return 8
        case .crushed: return 10
        }
    }
}

/// Muscle group for soreness reporting
enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest
    case back
    case legs
    case shoulders
    case arms
    case core

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

/// Request body for RPE feedback API
struct RPEFeedbackRequest: Codable {
    let workoutId: String
    let rpe: Int
    let muscleSoreness: [String]?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case rpe
        case muscleSoreness = "muscle_soreness"
        case notes
    }
}

/// Response from RPE feedback API
struct RPEFeedbackResponse: Codable {
    let success: Bool
    let message: String
    let deloadRecommended: Bool?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case deloadRecommended = "deload_recommended"
    }
}

@MainActor
class RPEFeedbackViewModel: ObservableObject {
    // MARK: - State

    @Published var selectedOption: RPEOption?
    @Published var selectedMuscles: Set<MuscleGroup> = []
    @Published var isSubmitting = false
    @Published var isSubmitted = false
    @Published var deloadRecommended = false
    @Published var errorMessage: String?

    // MARK: - Config

    let workoutId: String?
    var onComplete: (() -> Void)?

    // MARK: - Init

    init(workoutId: String?, onComplete: (() -> Void)? = nil) {
        self.workoutId = workoutId
        self.onComplete = onComplete
    }

    // MARK: - Actions

    func selectOption(_ option: RPEOption) {
        selectedOption = option
    }

    func toggleMuscle(_ muscle: MuscleGroup) {
        if selectedMuscles.contains(muscle) {
            selectedMuscles.remove(muscle)
        } else {
            selectedMuscles.insert(muscle)
        }
    }

    func submit() async {
        guard let option = selectedOption else { return }

        isSubmitting = true
        errorMessage = nil

        let request = RPEFeedbackRequest(
            workoutId: workoutId ?? "unknown",
            rpe: option.rpeValue,
            muscleSoreness: selectedMuscles.isEmpty ? nil : selectedMuscles.map { $0.rawValue },
            notes: nil
        )

        do {
            let response = try await postRPEFeedback(request)
            deloadRecommended = response.deloadRecommended ?? false
            isSubmitted = true

            // Auto-dismiss after brief pause
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            onComplete?()
        } catch {
            print("[RPEFeedbackViewModel] submit failed: \(error)")
            errorMessage = "Could not save feedback"
            // Still allow dismissal on error
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            onComplete?()
        }

        isSubmitting = false
    }

    func skip() {
        onComplete?()
    }

    // MARK: - API

    private func postRPEFeedback(_ request: RPEFeedbackRequest) async throws -> RPEFeedbackResponse {
        let baseURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(baseURL)/coach/rpe-feedback") else {
            throw APIError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
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

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            print("[RPEFeedbackViewModel] API error \(httpResponse.statusCode): \(body)")
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RPEFeedbackResponse.self, from: data)
    }
}
