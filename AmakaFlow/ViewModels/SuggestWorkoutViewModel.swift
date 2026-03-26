//
//  SuggestWorkoutViewModel.swift
//  AmakaFlow
//
//  ViewModel for the "Suggest Workout" feature (AMA-1265).
//  Calls POST /coach/suggest-workout and manages loading/success/error states.
//

import Foundation
import Combine

// MARK: - Suggest Workout Request/Response Models

struct SuggestWorkoutRequest: Codable {
    let durationMinutes: Int?
    let focusMuscleGroups: [String]?
    let notes: String?
}

struct SuggestWorkoutResponse: Codable {
    let blocks: [WorkoutInterval]
    let warmUp: WarmUpCooldown?
    let cooldown: WarmUpCooldown?
    let name: String?
    let sport: WorkoutSport?
    let durationSeconds: Int?
    let description: String?
}

struct WarmUpCooldown: Codable {
    let seconds: Int
    let target: String?
}

// MARK: - Coaching Profile

struct CoachingProfile: Codable {
    let experience: ExperienceLevel
    let goal: TrainingGoal
    let daysPerWeek: Int
}

enum ExperienceLevel: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }
}

enum TrainingGoal: String, Codable, CaseIterable {
    case loseWeight = "lose_weight"
    case buildMuscle = "build_muscle"
    case improveEndurance = "improve_endurance"
    case generalFitness = "general_fitness"
    case athletic = "athletic"

    var displayName: String {
        switch self {
        case .loseWeight: return "Lose Weight"
        case .buildMuscle: return "Build Muscle"
        case .improveEndurance: return "Improve Endurance"
        case .generalFitness: return "General Fitness"
        case .athletic: return "Athletic Performance"
        }
    }
}

// MARK: - View State

enum SuggestWorkoutState: Equatable {
    case idle
    case needsOnboarding
    case loading
    case success(Workout)
    case error(String)

    static func == (lhs: SuggestWorkoutState, rhs: SuggestWorkoutState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.needsOnboarding, .needsOnboarding): return true
        case (.loading, .loading): return true
        case (.success(let a), .success(let b)): return a.id == b.id
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - ViewModel

@MainActor
class SuggestWorkoutViewModel: ObservableObject {
    @Published var state: SuggestWorkoutState = .idle
    @Published var suggestedWorkout: Workout?

    private let dependencies: AppDependencies
    private static let profileKey = "coaching_profile"

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Profile Management

    var hasCoachingProfile: Bool {
        loadProfile() != nil
    }

    func loadProfile() -> CoachingProfile? {
        guard let data = UserDefaults.standard.data(forKey: Self.profileKey) else { return nil }
        return try? JSONDecoder().decode(CoachingProfile.self, from: data)
    }

    func saveProfile(_ profile: CoachingProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.profileKey)
        }
    }

    // MARK: - Suggest Workout

    /// Check profile and request a suggestion
    func requestSuggestion() {
        if !hasCoachingProfile {
            state = .needsOnboarding
            return
        }
        Task {
            await suggestWorkout()
        }
    }

    /// Save profile from onboarding, then suggest
    func completeOnboarding(experience: ExperienceLevel, goal: TrainingGoal, daysPerWeek: Int) {
        let profile = CoachingProfile(experience: experience, goal: goal, daysPerWeek: daysPerWeek)
        saveProfile(profile)
        Task {
            await suggestWorkout()
        }
    }

    /// Call the suggest-workout API
    func suggestWorkout(durationMinutes: Int? = nil, focusMuscleGroups: [String]? = nil, notes: String? = nil) async {
        state = .loading

        let chatURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(chatURL)/api/v1/coach/suggest-workout") else {
            state = .error("Invalid API URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Build auth headers the same way APIService does
        var headers = ["Content-Type": "application/json"]

        #if DEBUG
        if let testAuthSecret = TestAuthStore.shared.authSecret,
           let testUserId = TestAuthStore.shared.userId,
           !testAuthSecret.isEmpty {
            headers["X-Test-Auth"] = testAuthSecret
            headers["X-Test-User-Id"] = testUserId
        } else if let token = PairingService.shared.getToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        #else
        if let token = PairingService.shared.getToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        #endif

        request.allHTTPHeaderFields = headers

        let body = SuggestWorkoutRequest(
            durationMinutes: durationMinutes,
            focusMuscleGroups: focusMuscleGroups,
            notes: notes
        )

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        } catch {
            state = .error("Failed to encode request: \(error.localizedDescription)")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                state = .error("Invalid response from server")
                return
            }

            switch httpResponse.statusCode {
            case 200:
                let decoded = try APIService.makeDecoder().decode(SuggestWorkoutResponse.self, from: data)
                let workout = buildWorkout(from: decoded)
                suggestedWorkout = workout
                state = .success(workout)

            case 401:
                state = .error("Session expired. Please reconnect.")

            case 429:
                let body = String(data: data, encoding: .utf8) ?? ""
                state = .error("Rate limited. Please try again later. \(body)")

            default:
                let body = String(data: data, encoding: .utf8) ?? ""
                state = .error("Server error (\(httpResponse.statusCode)): \(body)")
            }
        } catch {
            state = .error("Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Build Workout from Response

    private func buildWorkout(from response: SuggestWorkoutResponse) -> Workout {
        var intervals: [WorkoutInterval] = []

        // Add warm-up if present
        if let warmUp = response.warmUp {
            intervals.append(.warmup(seconds: warmUp.seconds, target: warmUp.target))
        }

        // Add main blocks
        intervals.append(contentsOf: response.blocks)

        // Add cooldown if present
        if let cooldown = response.cooldown {
            intervals.append(.cooldown(seconds: cooldown.seconds, target: cooldown.target))
        }

        return Workout(
            name: response.name ?? "AI Suggested Workout",
            sport: response.sport ?? .strength,
            duration: response.durationSeconds ?? intervals.reduce(0) { total, interval in
                switch interval {
                case .warmup(let seconds, _), .cooldown(let seconds, _), .time(let seconds, _):
                    return total + seconds
                case .reps(_, _, _, _, let restSec, _):
                    return total + (restSec ?? 60)
                case .rest(let seconds):
                    return total + (seconds ?? 60)
                default:
                    return total + 60
                }
            },
            intervals: intervals,
            description: response.description,
            source: .coach
        )
    }

    // MARK: - Actions

    func reset() {
        state = .idle
        suggestedWorkout = nil
    }
}
