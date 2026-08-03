//
//  SuggestWorkoutViewModel.swift
//  AmakaFlow
//
//  ViewModel for the "Suggest Workout" feature (AMA-1265).
//  Calls POST /coach/suggest-workout and manages loading/success/error states.
//

import Combine
import Foundation
import os

// MARK: - Suggest Workout Request/Response Models

// AMA-2086: use the generated BFF contract at the API/ViewModel boundary.
typealias SuggestWorkoutRequest = Components.Schemas.SuggestWorkoutRequest
typealias SuggestWorkoutResponse = Components.Schemas.SuggestWorkoutResponse
typealias WarmUpCooldown = Components.Schemas.SuggestWarmUpCooldown
typealias IncludeContextFlags = Components.Schemas.IncludeContextFlags

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
        case (.success(let lhsWorkout), .success(let rhsWorkout)):
            return lhsWorkout.id == rhsWorkout.id
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
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

struct DraftSnapshot {
    let workout: Workout
    let whyThis: [String]?
    let response: SuggestWorkoutResponse
    let ask: String
    let includeContext: IncludeContextFlags?
    let appliedTweaks: [String]
}

// MARK: - ViewModel

@MainActor
class SuggestWorkoutViewModel: ObservableObject {
    @Published var state: SuggestWorkoutState = .idle
    @Published var suggestedWorkout: Workout?
    @Published private(set) var whyThis: [String]?
    @Published private(set) var appliedTweaks: [String] = []
    @Published private(set) var undoStack: [DraftSnapshot] = []
    @Published private(set) var isApplyingRefine = false
    /// AMA-2373 fix round 2: true while Save/Start is awaiting the real
    /// `POST /workouts/save` before proceeding — see `persistDraftToBackend`.
    @Published private(set) var isPersistingDraft = false
    @Published var readinessLevel: SuggestReadinessLevel = .unknown
    @Published var readinessMessage: String?
    @Published var ctaError: CTAError?
    @Published private(set) var didChooseRestToday = false

    private let dependencies: AppDependencies
    private static let profileKey = DefaultsKey.suggestedWorkoutCoachingProfile.rawValue
    private var lastPromptNotes: String?
    private var lastPromptDurationMinutes: Int?
    private var lastPromptFocus: [String]?
    private var lastPromptIncludeContext: IncludeContextFlags?
    private var lastPromptAsk: String?
    private var latestResponse: SuggestWorkoutResponse?
    private var generationTask: Task<Void, Never>?
    private var generationVersion: UInt64 = 0

    init(dependencies: AppDependencies = .current) {
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
        generationTask?.cancel()
        let generation = beginGeneration()
        lastPromptNotes = nil
        lastPromptDurationMinutes = nil
        lastPromptFocus = nil
        lastPromptIncludeContext = nil
        lastPromptAsk = nil
        clearDraftHistory()
        state = .loading
        suggestedWorkout = nil
        ctaError = nil

        generationTask = Task {
            await requestSuggestionAfterProfileCheck(
                durationMinutes: nil,
                focusMuscleGroups: nil,
                includeContext: nil,
                notes: nil,
                generation: generation
            )
        }
    }

    func requestSuggestionFromPrompt(
        notes: String,
        durationMinutes: Int?,
        focusMuscleGroups: [String]?,
        includeContext: IncludeContextFlags? = nil
    ) {
        generationTask?.cancel()
        let generation = beginGeneration()
        lastPromptNotes = notes
        lastPromptDurationMinutes = durationMinutes
        lastPromptFocus = focusMuscleGroups
        lastPromptIncludeContext = includeContext
        lastPromptAsk = notes
        clearDraftHistory()
        state = .loading
        suggestedWorkout = nil
        ctaError = nil

        generationTask = Task {
            await requestSuggestionAfterProfileCheck(
                durationMinutes: durationMinutes,
                focusMuscleGroups: focusMuscleGroups,
                includeContext: includeContext,
                notes: notes,
                generation: generation
            )
        }
    }

    private func requestSuggestionAfterProfileCheck(
        durationMinutes: Int?,
        focusMuscleGroups: [String]?,
        includeContext: IncludeContextFlags?,
        notes: String?,
        generation: UInt64
    ) async {
        do {
            let profile = try await dependencies.apiService.getCoachingProfile()
            guard isCurrentGeneration(generation) else { return }
            guard profile != nil else {
                state = .needsOnboarding
                return
            }
            await suggestWorkout(
                durationMinutes: durationMinutes,
                focusMuscleGroups: focusMuscleGroups,
                includeContext: includeContext,
                notes: notes,
                generation: generation
            )
        } catch {
            guard isCurrentGeneration(generation), !CTAError.isCancellation(error) else { return }
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
        generationTask?.cancel()
        let generation = beginGeneration()
        generationTask = Task {
            await suggestWorkout(
                durationMinutes: lastPromptDurationMinutes,
                focusMuscleGroups: lastPromptFocus,
                includeContext: lastPromptIncludeContext,
                notes: lastPromptNotes,
                generation: generation
            )
        }
    }

    /// Call the suggest-workout API
    func suggestWorkout(
        durationMinutes: Int? = nil,
        focusMuscleGroups: [String]? = nil,
        includeContext: IncludeContextFlags? = nil,
        notes: String? = nil,
        generation requestedGeneration: UInt64? = nil
    ) async {
        let generation = requestedGeneration ?? beginGeneration()
        guard isCurrentGeneration(generation) else { return }
        state = .loading
        // AMA-2373 fix round 1: a refine keeps the current draft on screen
        // (refine dock shows "applying…") instead of nulling it and forcing
        // the full-screen generating view — that view is for initial generate only.
        if !isApplyingRefine {
            suggestedWorkout = nil
        }
        ctaError = nil
        didChooseRestToday = false

        let readiness = await fetchReadinessLevel()
        guard isCurrentGeneration(generation) else { return }
        readinessLevel = readiness.level
        readinessMessage = readiness.message

        let body = SuggestWorkoutRequest(
            durationMinutes: durationMinutes,
            excludeExercises: nil,
            focusMuscleGroups: focusMuscleGroups,
            includeContext: includeContext,
            notes: notes
        )

        do {
            let decoded = try await dependencies.apiService.suggestWorkout(request: body)
            guard isCurrentGeneration(generation) else { return }
            guard Self.hasSuggestedWorkout(decoded) else {
                suggestedWorkout = nil
                state = .empty
                return
            }

            let workout = buildWorkout(from: decoded)
            latestResponse = decoded
            whyThis = decoded.whyThis
            suggestedWorkout = workout
            state = .success(workout)
        } catch {
            guard isCurrentGeneration(generation), !CTAError.isCancellation(error) else { return }
            // AMA-1803 P1: route through CTAError.map so the user UI
            // sees a typed failure (error_code, retryability, request_id)
            // instead of a stringly-typed `localizedDescription`. When
            // the upstream throws an AnnotatedAPIError (AMA-1808), its
            // requestId propagates here for Report-button correlation.
            let mapped = Self.mapSuggestError(error)
            suggestedWorkout = nil
            ctaError = mapped
            state = .error(mapped)
        }
    }

    private func fetchReadinessLevel() async -> (level: SuggestReadinessLevel, message: String?) {
        do {
            let advice = try await dependencies.apiService.getFatigueAdvice(fatigueScore: nil, loadHistory: nil)
            return (SuggestReadinessLevel(fatigueLevel: advice.level), advice.message)
        } catch {
            return (.unknown, nil)
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
        appliedTweaks = []
        undoStack = []
        // AMA-2373 final-review fix: Create with AI (ask set) reroll composes
        // fresh notes from the ask alone, dropping refine tweaks. The daily
        // coach path (`requestSuggestion()`, no ask) has no ask to compose
        // from, so restore the pre-AMA-2373 variation-note behavior or
        // "suggest another" would resend identical notes and not vary.
        let notes: String?
        if let ask = lastPromptAsk {
            notes = CreateWithAIPromptBuilder.composeNotes(ask: ask)
        } else {
            let variationNote = "Suggest a different session than the previous suggestion."
            notes = lastPromptNotes.map { "\($0)\n\n\(variationNote)" } ?? variationNote
        }
        lastPromptNotes = notes
        await suggestWorkout(
            durationMinutes: lastPromptDurationMinutes,
            focusMuscleGroups: lastPromptFocus,
            includeContext: lastPromptIncludeContext,
            notes: notes
        )
    }

    func applyRefine(tweak: String) async {
        guard
            let workout = suggestedWorkout,
            let response = latestResponse,
            let ask = lastPromptAsk
        else { return }

        let trimmedTweak = tweak.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTweak.isEmpty else { return }

        undoStack.append(
            DraftSnapshot(
                workout: workout,
                whyThis: whyThis,
                response: response,
                ask: ask,
                includeContext: lastPromptIncludeContext,
                appliedTweaks: appliedTweaks
            )
        )
        let composed = CreateWithAIPromptBuilder.compose(
            ask: ask,
            tweaks: appliedTweaks + [trimmedTweak]
        )
        appliedTweaks = composed.includedTweaks
        lastPromptNotes = composed.notes
        let generation = beginGeneration()
        isApplyingRefine = true
        defer {
            if generation == generationVersion {
                isApplyingRefine = false
            }
        }

        await suggestWorkout(
            durationMinutes: lastPromptDurationMinutes,
            focusMuscleGroups: lastPromptFocus,
            includeContext: lastPromptIncludeContext,
            notes: composed.notes,
            generation: generation
        )
    }

    func undoRefine() {
        guard let snapshot = undoStack.popLast() else { return }
        // AMA-2373 final-review fix: cancel any in-flight refine generation
        // (same as cancelGenerate()) so a late-arriving response for the
        // refine we're undoing can't land after and clobber the restored draft.
        generationTask?.cancel()
        generationTask = nil
        _ = beginGeneration()
        isApplyingRefine = false
        suggestedWorkout = snapshot.workout
        whyThis = snapshot.whyThis
        latestResponse = snapshot.response
        lastPromptAsk = snapshot.ask
        lastPromptIncludeContext = snapshot.includeContext
        appliedTweaks = snapshot.appliedTweaks
        lastPromptNotes = CreateWithAIPromptBuilder.composeNotes(
            ask: snapshot.ask,
            tweaks: snapshot.appliedTweaks
        )
        ctaError = nil
        state = .success(snapshot.workout)
    }

    // MARK: - Create with AI draft accessors

    /// The most recent ask text sent to the coach (compose ask + any prior tweaks).
    var currentAsk: String { lastPromptAsk ?? "" }

    /// Context flags attached to the current draft's request, for signal-chip display.
    var currentIncludeContext: IncludeContextFlags? { lastPromptIncludeContext }

    /// Raw warm-up interval from the latest response, for band-summary rendering.
    var draftWarmUp: WorkoutInterval? {
        latestResponse?.warmUp.map { WorkoutInterval.warmup(seconds: $0.seconds, target: $0.target) }
    }

    /// Raw cooldown interval from the latest response, for band-summary rendering.
    var draftCooldown: WorkoutInterval? {
        latestResponse?.cooldown.map { WorkoutInterval.cooldown(seconds: $0.seconds, target: $0.target) }
    }

    /// Main-block intervals (excludes warm-up/cooldown) from the latest response.
    var draftMainBlocks: [WorkoutInterval] {
        latestResponse?.blocks.compactMap(\.workoutInterval) ?? []
    }

    /// AMA-2373 fix round 2: Save/Start must await a real backend id before any
    /// enrichment/push flow looks the workout up by id — `acceptSuggestedWorkout`
    /// alone is local-first (GRDB write + background sync), so a Garmin/Apple
    /// push fired right after it can race the sync and hit a workout Supabase
    /// hasn't seen yet. This mirrors `WorkoutEditorViewModel.save()` /
    /// `SocialImportViewModel.saveToLibrary()`, which both await
    /// `apiService.saveWorkout(...)` and only proceed with the server-returned
    /// (real-id) workout.
    func persistDraftToBackend(_ workout: Workout) async -> Result<Workout, CTAError> {
        isPersistingDraft = true
        defer { isPersistingDraft = false }
        do {
            let saved = try await dependencies.apiService.saveWorkout(.from(workout: workout))
            return .success(saved)
        } catch {
            return .failure(CTAError.map(error))
        }
    }

    func cancelGenerate() {
        generationTask?.cancel()
        generationTask = nil
        _ = beginGeneration()
        isApplyingRefine = false
        ctaError = nil
        state = .idle
    }

    func restToday() {
        didChooseRestToday = true
        ctaError = nil
        state = .idle
        suggestedWorkout = nil
    }

    func retry() async {
        await suggestWorkout(
            durationMinutes: lastPromptDurationMinutes,
            focusMuscleGroups: lastPromptFocus,
            includeContext: lastPromptIncludeContext,
            notes: lastPromptNotes
        )
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
        generationTask?.cancel()
        generationTask = nil
        _ = beginGeneration()
        state = .idle
        suggestedWorkout = nil
        ctaError = nil
        lastPromptNotes = nil
        lastPromptDurationMinutes = nil
        lastPromptFocus = nil
        lastPromptIncludeContext = nil
        lastPromptAsk = nil
        clearDraftHistory()
    }

    private func clearDraftHistory() {
        whyThis = nil
        latestResponse = nil
        appliedTweaks = []
        undoStack = []
        isApplyingRefine = false
    }

    private func beginGeneration() -> UInt64 {
        generationVersion &+= 1
        return generationVersion
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        !Task.isCancelled && generation == generationVersion
    }

    private static func mapSuggestError(_ error: Error) -> CTAError {
        let mapped = CTAError.map(error)
        guard case .http(let status, _, let requestId) = mapped, status == 429 else {
            return mapped
        }
        return .unknown(description: CreateWithAICopy.rateLimited, requestId: requestId)
    }
}
