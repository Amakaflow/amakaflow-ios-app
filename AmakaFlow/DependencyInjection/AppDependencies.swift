//
//  AppDependencies.swift
//  AmakaFlow
//
//  Dependency container for managing service instances throughout the app.
//  Enables dependency injection for testability and modularity.
//

import Foundation
import WatchConnectivity

/// Container for all app dependencies
/// Use `.live` for production and `.mock` for testing
struct AppDependencies {
    let apiService: APIServiceProviding
    let pairingService: PairingServiceProviding
    let audioService: AudioProviding
    let progressStore: ProgressStoreProviding
    let watchSession: WatchSessionProviding

    /// Live dependencies using real service implementations
    @MainActor
    static let live = AppDependencies(
        apiService: APIService.shared,
        pairingService: PairingService.shared,
        audioService: AudioCueManager(),
        progressStore: LiveProgressStore.shared,
        watchSession: LiveWatchSession.shared
    )

    /// Mock dependencies for unit testing
    @MainActor
    static let mock = AppDependencies(
        apiService: MockAPIService(),
        pairingService: MockPairingService(),
        audioService: MockAudioService(),
        progressStore: MockProgressStore(),
        watchSession: MockWatchSession()
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

    // MARK: - Initialization

    /// Nonisolated init to allow creation from async test contexts
    nonisolated init() {}

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

/// Mock audio service for testing
class MockAudioService: AudioProviding {
    // MARK: - State

    var isEnabled: Bool = true
    var isSpeaking: Bool = false

    // MARK: - Call Tracking

    var speakCalled = false
    var lastSpokenText: String?
    var lastSpeechPriority: SpeechPriority?
    var stopSpeakingCalled = false
    var announceWorkoutStartCalled = false
    var announceStepCalled = false
    var announceCountdownCalled = false
    var announceWorkoutCompleteCalled = false
    var announcePausedCalled = false
    var announceResumedCalled = false
    var announceRestCalled = false

    // MARK: - Protocol Implementation

    func speak(_ text: String, priority: SpeechPriority) {
        speakCalled = true
        lastSpokenText = text
        lastSpeechPriority = priority
    }

    func stopSpeaking() {
        stopSpeakingCalled = true
        isSpeaking = false
    }

    func announceWorkoutStart(_ workoutName: String) {
        announceWorkoutStartCalled = true
        speak("Starting \(workoutName)", priority: .high)
    }

    func announceStep(_ stepName: String, roundInfo: String?) {
        announceStepCalled = true
        var announcement = stepName
        if let round = roundInfo {
            announcement = "\(round). \(stepName)"
        }
        speak(announcement, priority: .high)
    }

    func announceCountdown(_ seconds: Int) {
        announceCountdownCalled = true
        speak("\(seconds)", priority: .countdown)
    }

    func announceWorkoutComplete() {
        announceWorkoutCompleteCalled = true
        speak("Workout complete. Great job!", priority: .high)
    }

    func announcePaused() {
        announcePausedCalled = true
        speak("Paused", priority: .normal)
    }

    func announceResumed() {
        announceResumedCalled = true
        speak("Resuming", priority: .normal)
    }

    func announceRest(isManual: Bool, seconds: Int) {
        announceRestCalled = true
        if isManual {
            speak("Rest. Tap when ready.", priority: .high)
        } else if seconds > 0 {
            speak("Rest for \(seconds) seconds", priority: .high)
        }
    }
}

/// Mock progress store for testing
class MockProgressStore: ProgressStoreProviding {
    // MARK: - State

    var storedProgress: SavedWorkoutProgress?

    // MARK: - Call Tracking

    var saveCalled = false
    var loadCalled = false
    var clearCalled = false

    // MARK: - Protocol Implementation

    func save(_ progress: SavedWorkoutProgress) {
        saveCalled = true
        storedProgress = progress
    }

    func load() -> SavedWorkoutProgress? {
        loadCalled = true
        return storedProgress
    }

    func clear() {
        clearCalled = true
        storedProgress = nil
    }
}

/// Mock watch session for testing
class MockWatchSession: WatchSessionProviding {
    // MARK: - Configurable State

    var isWatchAppInstalled: Bool = true
    var isReachable: Bool = true
    var isPaired: Bool = true
    var activationState: WCSessionActivationState = .activated
    weak var delegate: WCSessionDelegate?

    // MARK: - Call Tracking

    var activateCalled = false
    var sendMessageCalled = false
    var sentMessages: [[String: Any]] = []
    var lastReplyHandler: (([String: Any]) -> Void)?
    var lastErrorHandler: ((Error) -> Void)?
    var transferUserInfoCalled = false
    var transferredUserInfo: [[String: Any]] = []
    var updateApplicationContextCalled = false
    var lastApplicationContext: [String: Any]?

    // MARK: - Configurable Behavior

    /// Error to trigger in errorHandler when sendMessage is called
    var sendMessageError: Error?

    /// Reply to return when sendMessage is called
    var sendMessageReply: [String: Any]?

    /// Error to throw when updateApplicationContext is called
    var updateContextError: Error?

    // MARK: - Protocol Implementation

    func activate() {
        activateCalled = true
    }

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((Error) -> Void)?
    ) {
        sendMessageCalled = true
        sentMessages.append(message)
        lastReplyHandler = replyHandler
        lastErrorHandler = errorHandler

        // Simulate error if configured
        if let error = sendMessageError {
            errorHandler?(error)
        } else if let reply = sendMessageReply {
            replyHandler?(reply)
        }
    }

    @discardableResult
    func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer? {
        transferUserInfoCalled = true
        transferredUserInfo.append(userInfo)
        return nil  // Mock doesn't create real transfer objects
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        updateApplicationContextCalled = true
        lastApplicationContext = applicationContext
        if let error = updateContextError {
            throw error
        }
    }

    // MARK: - Test Helpers

    /// Simulate receiving a message from watch (calls delegate method)
    func simulateReceivedMessage(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // This would need a real WCSession to work, but for testing we can track the call
        // In a real test, you would call the delegate method directly on the manager
    }

    /// Reset all call tracking state
    func reset() {
        activateCalled = false
        sendMessageCalled = false
        sentMessages.removeAll()
        lastReplyHandler = nil
        lastErrorHandler = nil
        transferUserInfoCalled = false
        transferredUserInfo.removeAll()
        updateApplicationContextCalled = false
        lastApplicationContext = nil
    }
}
