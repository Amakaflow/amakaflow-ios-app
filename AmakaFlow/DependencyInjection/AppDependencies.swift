//
//  AppDependencies.swift
//  AmakaFlow
//
//  Dependency container for managing service instances throughout the app.
//  Enables dependency injection for testability and modularity.
//

import Foundation

/// Container for all app dependencies
/// Use `.live` for production and `.mock` for testing
struct AppDependencies {
    let apiService: APIServiceProviding
    let pairingService: PairingServiceProviding

    /// Live dependencies using real service implementations
    @MainActor
    static let live = AppDependencies(
        apiService: APIService.shared,
        pairingService: PairingService.shared
    )

    /// Mock dependencies for unit testing
    @MainActor
    static let mock = AppDependencies(
        apiService: MockAPIService(),
        pairingService: MockPairingService()
    )
}

// MARK: - Mock Implementations

/// Mock API service for testing
class MockAPIService: APIServiceProviding {
    // MARK: - Configurable Results

    var fetchWorkoutsResult: Result<[Workout], Error> = .success([])
    var fetchScheduledWorkoutsResult: Result<[ScheduledWorkout], Error> = .success([])
    var fetchPushedWorkoutsResult: Result<[Workout], Error> = .success([])
    var fetchPendingWorkoutsResult: Result<[Workout], Error> = .success([])
    var syncWorkoutResult: Result<Void, Error> = .success(())
    var getAppleExportResult: Result<String, Error> = .success("{}")
    var parseVoiceWorkoutResult: Result<VoiceWorkoutParseResponse, Error>?
    var transcribeAudioResult: Result<CloudTranscriptionResponse, Error>?
    var syncPersonalDictionaryResult: Result<PersonalDictionaryResponse, Error> = .success(PersonalDictionaryResponse(corrections: [:], customTerms: []))
    var fetchPersonalDictionaryResult: Result<PersonalDictionaryResponse, Error> = .success(PersonalDictionaryResponse(corrections: [:], customTerms: []))
    var logManualWorkoutResult: Result<Void, Error> = .success(())
    var postWorkoutCompletionResult: Result<WorkoutCompletionResponse, Error>?
    var confirmSyncResult: Result<Void, Error> = .success(())
    var reportSyncFailedResult: Result<Void, Error> = .success(())
    var fetchProfileResult: Result<UserProfile, Error>?

    // MARK: - Call Tracking

    var fetchWorkoutsCalled = false
    var fetchScheduledWorkoutsCalled = false
    var fetchPushedWorkoutsCalled = false
    var fetchPendingWorkoutsCalled = false
    var syncWorkoutCalled = false
    var syncedWorkout: Workout?
    var getAppleExportCalled = false
    var parseVoiceWorkoutCalled = false
    var transcribeAudioCalled = false
    var syncPersonalDictionaryCalled = false
    var fetchPersonalDictionaryCalled = false
    var logManualWorkoutCalled = false
    var postWorkoutCompletionCalled = false
    var postedCompletion: WorkoutCompletionRequest?
    var confirmSyncCalled = false
    var confirmedWorkoutId: String?
    var reportSyncFailedCalled = false
    var fetchProfileCalled = false

    // MARK: - Protocol Implementation

    func fetchWorkouts() async throws -> [Workout] {
        fetchWorkoutsCalled = true
        return try fetchWorkoutsResult.get()
    }

    func fetchScheduledWorkouts() async throws -> [ScheduledWorkout] {
        fetchScheduledWorkoutsCalled = true
        return try fetchScheduledWorkoutsResult.get()
    }

    func fetchPushedWorkouts() async throws -> [Workout] {
        fetchPushedWorkoutsCalled = true
        return try fetchPushedWorkoutsResult.get()
    }

    func fetchPendingWorkouts() async throws -> [Workout] {
        fetchPendingWorkoutsCalled = true
        return try fetchPendingWorkoutsResult.get()
    }

    func syncWorkout(_ workout: Workout) async throws {
        syncWorkoutCalled = true
        syncedWorkout = workout
        try syncWorkoutResult.get()
    }

    func getAppleExport(workoutId: String) async throws -> String {
        getAppleExportCalled = true
        return try getAppleExportResult.get()
    }

    func parseVoiceWorkout(transcription: String, sportHint: WorkoutSport?) async throws -> VoiceWorkoutParseResponse {
        parseVoiceWorkoutCalled = true
        guard let result = parseVoiceWorkoutResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func transcribeAudio(
        audioData: String,
        provider: String,
        language: String,
        keywords: [String],
        includeWordTimings: Bool
    ) async throws -> CloudTranscriptionResponse {
        transcribeAudioCalled = true
        guard let result = transcribeAudioResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func syncPersonalDictionary(
        corrections: [String: String],
        customTerms: [String]
    ) async throws -> PersonalDictionaryResponse {
        syncPersonalDictionaryCalled = true
        return try syncPersonalDictionaryResult.get()
    }

    func fetchPersonalDictionary() async throws -> PersonalDictionaryResponse {
        fetchPersonalDictionaryCalled = true
        return try fetchPersonalDictionaryResult.get()
    }

    func logManualWorkout(_ workout: Workout, startedAt: Date, endedAt: Date, durationSeconds: Int) async throws {
        logManualWorkoutCalled = true
        try logManualWorkoutResult.get()
    }

    func postWorkoutCompletion(_ completion: WorkoutCompletionRequest, isRetry: Bool) async throws -> WorkoutCompletionResponse {
        postWorkoutCompletionCalled = true
        postedCompletion = completion
        guard let result = postWorkoutCompletionResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func confirmSync(workoutId: String, deviceType: String, deviceId: String?) async throws {
        confirmSyncCalled = true
        confirmedWorkoutId = workoutId
        try confirmSyncResult.get()
    }

    func reportSyncFailed(workoutId: String, deviceType: String, error: String, deviceId: String?) async throws {
        reportSyncFailedCalled = true
        try reportSyncFailedResult.get()
    }

    func fetchProfile() async throws -> UserProfile {
        fetchProfileCalled = true
        guard let result = fetchProfileResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }
}

/// Mock pairing service for testing
@MainActor
class MockPairingService: PairingServiceProviding {
    // MARK: - Published Properties

    @Published var isPaired: Bool = false
    @Published var userProfile: UserProfile?
    @Published var needsReauth: Bool = false
    var lastTokenRefresh: Date?

    // MARK: - Publishers

    var isPairedPublisher: Published<Bool>.Publisher { $isPaired }
    var userProfilePublisher: Published<UserProfile?>.Publisher { $userProfile }
    var needsReauthPublisher: Published<Bool>.Publisher { $needsReauth }

    // MARK: - Configurable Results

    var pairResult: Result<PairingResponse, Error>?
    var refreshTokenResult: Bool = false
    var storedToken: String?

    // MARK: - Call Tracking

    var markAuthInvalidCalled = false
    var authRestoredCalled = false
    var pairCalled = false
    var pairCode: String?
    var refreshTokenCalled = false
    var getTokenCalled = false
    var unpairCalled = false

    #if DEBUG
    var enableTestModeCalled = false
    var disableTestModeCalled = false
    var isInTestMode: Bool = false
    #endif

    // MARK: - Protocol Implementation

    func markAuthInvalid() {
        markAuthInvalidCalled = true
        needsReauth = true
    }

    func authRestored() {
        authRestoredCalled = true
        needsReauth = false
    }

    func pair(code: String) async throws -> PairingResponse {
        pairCalled = true
        pairCode = code
        guard let result = pairResult else {
            throw PairingError.invalidCode("Mock not configured")
        }
        let response = try result.get()
        isPaired = true
        return response
    }

    func refreshToken() async -> Bool {
        refreshTokenCalled = true
        return refreshTokenResult
    }

    func getToken() -> String? {
        getTokenCalled = true
        return storedToken
    }

    func unpair() {
        unpairCalled = true
        isPaired = false
        userProfile = nil
        storedToken = nil
    }

    #if DEBUG
    func enableTestMode(authSecret: String, userId: String) {
        enableTestModeCalled = true
        isInTestMode = true
        isPaired = true
    }

    func disableTestMode() {
        disableTestModeCalled = true
        isInTestMode = false
        isPaired = false
    }
    #endif
}
