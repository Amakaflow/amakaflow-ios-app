//
//  SuggestWorkoutViewModel.swift
//  AmakaFlow
//
//  ViewModel for the "Suggest Workout" feature (AMA-1265).
//  Calls POST /coach/suggest-workout and manages loading/success/error states.
//

import Foundation
import Combine
import os

// MARK: - Suggest Workout Request/Response Models

// AMA-2086: use the generated BFF contract at the API/ViewModel boundary.
typealias SuggestWorkoutRequest = Components.Schemas.SuggestWorkoutRequest
typealias SuggestWorkoutResponse = Components.Schemas.SuggestWorkoutResponse
typealias WarmUpCooldown = Components.Schemas.SuggestWarmUpCooldown

extension Components.Schemas.SuggestWorkoutRequest {
    init(durationMinutes: Int?, focusMuscleGroups: [String]?, notes: String?) {
        self.init(
            durationMinutes: durationMinutes,
            excludeExercises: nil,
            focusMuscleGroups: focusMuscleGroups,
            notes: notes
        )
    }
}

extension Components.Schemas.SuggestWorkoutResponse {
    init(
        blocks: [WorkoutInterval],
        warmUp: Components.Schemas.SuggestWarmUpCooldown?,
        cooldown: Components.Schemas.SuggestWarmUpCooldown?,
        name: String?,
        sport: WorkoutSport?,
        durationSeconds: Int?,
        description: String?
    ) {
        self.init(
            blocks: blocks.map(Components.Schemas.SuggestWorkoutInterval.init(workoutInterval:)),
            cooldown: cooldown,
            description: description,
            durationSeconds: durationSeconds,
            name: name,
            sport: sport?.rawValue,
            suggestionId: nil,
            warmUp: warmUp
        )
    }
}

extension Components.Schemas.SuggestWorkoutInterval {
    private static let logger = Logger(subsystem: "com.amakaflow.app", category: "suggest-workout")
    private static let repeatPayloadPrefix = "__amakaflow_repeat_v1:"

    init(workoutInterval: WorkoutInterval) {
        switch workoutInterval {
        case .warmup(let seconds, let target):
            self.init(kind: "warmup", seconds: seconds, target: target)
        case .cooldown(let seconds, let target):
            self.init(kind: "cooldown", seconds: seconds, target: target)
        case .time(let seconds, let target):
            self.init(kind: "time", seconds: seconds, target: target)
        case .reps(let sets, let reps, let name, let load, let restSec, let followAlongUrl):
            self.init(followAlongUrl: followAlongUrl, kind: "reps", load: load, name: name, reps: reps, restSec: restSec, sets: sets)
        case .distance(let meters, let target):
            self.init(kind: "distance", meters: meters, target: target)
        case .repeat(let reps, let intervals):
            self.init(
                kind: "repeat",
                reps: reps,
                target: Self.encodeRepeatChildren(
                    intervals.map(Components.Schemas.SuggestWorkoutInterval.init(workoutInterval:))
                )
            )
        case .rest(let seconds):
            self.init(kind: "rest", seconds: seconds)
        }
    }

    var workoutInterval: WorkoutInterval? {
        switch kind {
        case "warmup":
            guard let seconds else { return nil }
            return .warmup(seconds: seconds, target: target)
        case "cooldown":
            guard let seconds else { return nil }
            return .cooldown(seconds: seconds, target: target)
        case "time":
            guard let seconds else { return nil }
            return .time(seconds: seconds, target: target)
        case "reps":
            guard let reps, let name else { return nil }
            return .reps(sets: sets, reps: reps, name: name, load: load, restSec: restSec, followAlongUrl: followAlongUrl)
        case "distance":
            guard let meters else { return nil }
            return .distance(meters: meters, target: target)
        case "repeat":
            guard let reps else { return nil }
            return .repeat(reps: reps, intervals: Self.decodeRepeatChildren(from: target))
        case "rest":
            return .rest(seconds: seconds)
        default:
            return nil
        }
    }

    private static func encodeRepeatChildren(_ intervals: [Components.Schemas.SuggestWorkoutInterval]) -> String? {
        guard !intervals.isEmpty, let data = try? JSONEncoder().encode(intervals) else { return nil }
        return repeatPayloadPrefix + data.base64EncodedString()
    }

    private static func decodeRepeatChildren(from target: String?) -> [WorkoutInterval] {
        guard let target, target.hasPrefix(repeatPayloadPrefix) else { return [] }

        let encodedPayload = String(target.dropFirst(repeatPayloadPrefix.count))
        guard let data = Data(base64Encoded: encodedPayload) else {
            logger.warning("Failed to decode repeat children target=\(target, privacy: .public) error=invalid-base64")
            return []
        }

        do {
            let intervals = try JSONDecoder().decode([Components.Schemas.SuggestWorkoutInterval].self, from: data)
            return intervals.compactMap(\.workoutInterval)
        } catch {
            logger.warning("Failed to decode repeat children target=\(target, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }
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
    case empty
    /// AMA-1803 P1: carries the typed CTAError so the error UI can
    /// surface error_code, render Retry only when the failure is
    /// transient, and produce a Sentry breadcrumb correlated to
    /// AMA-1805's server-side capture by request_id.
    case error(CTAError)

    static func == (lhs: SuggestWorkoutState, rhs: SuggestWorkoutState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.needsOnboarding, .needsOnboarding): return true
        case (.loading, .loading): return true
        case (.empty, .empty): return true
        case (.success(let a), .success(let b)): return a.id == b.id
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

enum SuggestReadinessLevel: Equatable {
    case green
    case yellow
    case red
    case unknown

    init(fatigueLevel: FatigueLevel) {
        switch fatigueLevel {
        case .low:
            self = .green
        case .moderate:
            self = .yellow
        case .high, .critical:
            self = .red
        }
    }
}

// MARK: - ViewModel

@MainActor
class SuggestWorkoutViewModel: ObservableObject {
    @Published var state: SuggestWorkoutState = .idle
    @Published var suggestedWorkout: Workout?
    @Published var readinessLevel: SuggestReadinessLevel = .unknown
    @Published var readinessMessage: String?
    @Published var ctaError: CTAError?
    @Published private(set) var didChooseRestToday = false

    private let dependencies: AppDependencies
    private static let profileKey = DefaultsKey.suggestedWorkoutCoachingProfile.rawValue

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
        state = .loading
        suggestedWorkout = nil
        ctaError = nil

        Task {
            await requestSuggestionAfterProfileCheck()
        }
    }

    private func requestSuggestionAfterProfileCheck() async {
        do {
            guard try await dependencies.apiService.getCoachingProfile() != nil else {
                state = .needsOnboarding
                return
            }
            await suggestWorkout()
        } catch {
            let mapped = CTAError.map(error)
            suggestedWorkout = nil
            ctaError = mapped
            state = .error(mapped)
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
        suggestedWorkout = nil
        ctaError = nil
        didChooseRestToday = false

        await fetchReadinessLevel()

        let body = SuggestWorkoutRequest(
            durationMinutes: durationMinutes,
            focusMuscleGroups: focusMuscleGroups,
            notes: notes
        )

        do {
            let decoded = try await dependencies.apiService.suggestWorkout(request: body)
            guard Self.hasSuggestedWorkout(decoded) else {
                suggestedWorkout = nil
                state = .empty
                return
            }

            let workout = buildWorkout(from: decoded)
            suggestedWorkout = workout
            state = .success(workout)
        } catch {
            // AMA-1803 P1: route through CTAError.map so the user UI
            // sees a typed failure (error_code, retryability, request_id)
            // instead of a stringly-typed `localizedDescription`. When
            // the upstream throws an AnnotatedAPIError (AMA-1808), its
            // requestId propagates here for Report-button correlation.
            let mapped = CTAError.map(error)
            suggestedWorkout = nil
            ctaError = mapped
            state = .error(mapped)
        }
    }

    private func fetchReadinessLevel() async {
        do {
            let advice = try await dependencies.apiService.getFatigueAdvice(fatigueScore: nil, loadHistory: nil)
            readinessLevel = SuggestReadinessLevel(fatigueLevel: advice.level)
            readinessMessage = advice.message
        } catch {
            readinessLevel = .unknown
            readinessMessage = nil
        }
    }

    private static func hasSuggestedWorkout(_ response: SuggestWorkoutResponse) -> Bool {
        response.warmUp != nil || response.cooldown != nil || !response.blocks.isEmpty
    }

    // MARK: - Build Workout from Response

    private func buildWorkout(from response: SuggestWorkoutResponse) -> Workout {
        var intervals: [WorkoutInterval] = []

        // Add warm-up if present
        if let warmUp = response.warmUp {
            intervals.append(.warmup(seconds: warmUp.seconds, target: warmUp.target))
        }

        // Add main blocks from the generated DTO shape.
        intervals.append(contentsOf: response.blocks.compactMap(\.workoutInterval))

        // Add cooldown if present
        if let cooldown = response.cooldown {
            intervals.append(.cooldown(seconds: cooldown.seconds, target: cooldown.target))
        }

        return Workout(
            name: response.name ?? "AI Suggested Workout",
            sport: response.sport.flatMap(WorkoutSport.init(rawValue:)) ?? .strength,
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

    func suggestAnother() async {
        await suggestWorkout(notes: "Suggest a different session than the previous suggestion.")
    }

    func restToday() {
        didChooseRestToday = true
        ctaError = nil
        state = .idle
        suggestedWorkout = nil
    }

    func retry() async {
        await suggestWorkout()
    }

    func dismissError() {
        ctaError = nil
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        reporter.report(
            action: "suggest_workout",
            error: ctaError,
            endpoint: "/coach/suggest-workout",
            userId: PairingService.shared.userProfile?.id
        )
    }

    func reset() {
        state = .idle
        suggestedWorkout = nil
        ctaError = nil
    }
}
