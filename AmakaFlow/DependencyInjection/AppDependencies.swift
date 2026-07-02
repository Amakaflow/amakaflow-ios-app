//
//  AppDependencies.swift
//  AmakaFlow
//
//  Dependency container for managing service instances throughout the app.
//  Enables dependency injection for testability and modularity.
//

import Foundation
import Combine
import WatchConnectivity

/// Container for all app dependencies
/// Use `.live` for production and explicit injected doubles for tests.
struct AppDependencies {
    let apiService: APIServiceProviding
    let pairingService: PairingServiceProviding
    let audioService: AudioProviding
    let progressStore: ProgressStoreProviding
    let watchSession: WatchSessionProviding
    let chatStreamService: ChatStreamProviding
    let coachSessionClient: CoachSessionProviding
    let pendingActionsClient: PendingActionsProviding
    let coachTurnTelemetrySink: CoachTurnTelemetryProviding
    let programStreamService: ProgramStreamProviding
    let acceptedSuggestionsRepository: AcceptedSuggestionsRepository
    let workoutEventsRepository: WorkoutEventsRepository
    let syncQueueRepository: SyncQueueRepository
    let syncEngine: SyncEngine

    /// AMA-2234 (E9-3): true when the coach path is wired to local fixtures /
    /// mocks (dev / simulator validation) rather than the live shared
    /// BFF / Channel Gateway / coach core. Drives the coach shell's sticky
    /// `.mock` degrade mode so dev replies are never presented as live.
    let isMockCoachPath: Bool

    init(
        apiService: APIServiceProviding,
        pairingService: PairingServiceProviding,
        audioService: AudioProviding,
        progressStore: ProgressStoreProviding,
        watchSession: WatchSessionProviding,
        chatStreamService: ChatStreamProviding,
        coachSessionClient: CoachSessionProviding = CoachSessionClient(),
        pendingActionsClient: PendingActionsProviding = PendingActionsClient(),
        coachTurnTelemetrySink: CoachTurnTelemetryProviding = CoachTurnDebugTelemetrySink(),
        programStreamService: ProgramStreamProviding = ProgramStreamService(),
        acceptedSuggestionsRepository: AcceptedSuggestionsRepository = AcceptedSuggestionsRepository(),
        workoutEventsRepository: WorkoutEventsRepository = WorkoutEventsRepository(),
        syncQueueRepository: SyncQueueRepository = SyncQueueRepository(),
        syncEngine: SyncEngine = SyncEngine(),
        isMockCoachPath: Bool = false
    ) {
        self.apiService = apiService
        self.pairingService = pairingService
        self.audioService = audioService
        self.progressStore = progressStore
        self.watchSession = watchSession
        self.chatStreamService = chatStreamService
        self.coachSessionClient = coachSessionClient
        self.pendingActionsClient = pendingActionsClient
        self.coachTurnTelemetrySink = coachTurnTelemetrySink
        self.programStreamService = programStreamService
        self.acceptedSuggestionsRepository = acceptedSuggestionsRepository
        self.workoutEventsRepository = workoutEventsRepository
        self.syncQueueRepository = syncQueueRepository
        self.syncEngine = syncEngine
        self.isMockCoachPath = isMockCoachPath
    }

    /// Live dependencies using real service implementations
    @MainActor
    static let live = AppDependencies(
        apiService: APIService.shared,
        pairingService: PairingService.shared,
        audioService: AudioCueManager(),
        progressStore: LiveProgressStore.shared,
        watchSession: LiveWatchSession.shared,
        chatStreamService: ChatStreamService(),
        coachSessionClient: CoachSessionClient(),
        pendingActionsClient: PendingActionsClient(),
        coachTurnTelemetrySink: CoachTurnDebugTelemetrySink(),
        programStreamService: ProgramStreamService(),
        acceptedSuggestionsRepository: AcceptedSuggestionsRepository(),
        workoutEventsRepository: WorkoutEventsRepository(),
        syncQueueRepository: SyncQueueRepository(),
        syncEngine: SyncEngine.shared
    )

    #if DEBUG
    /// Fixture dependencies for E2E testing with JSON fixture data
    /// Uses FixtureAPIService (bundled JSON, canned writes) with real UI services
    /// Watch session uses MockWatchSession to avoid WCSession permission modal (AMA-549)
    @MainActor
    static let fixture = AppDependencies(
        apiService: FixtureAPIService(),
        pairingService: PairingService.shared,
        audioService: AudioCueManager(),
        progressStore: LiveProgressStore.shared,
        watchSession: MockWatchSession(),
        chatStreamService: PendingActionsFixtureChatStreamService(),
        coachSessionClient: MockCoachSessionClient(),
        pendingActionsClient: MockPendingActionsClient(),
        coachTurnTelemetrySink: CoachTurnDebugTelemetrySink(),
        programStreamService: MockProgramStreamService(),
        acceptedSuggestionsRepository: AcceptedSuggestionsRepository(),
        workoutEventsRepository: WorkoutEventsRepository(),
        syncQueueRepository: SyncQueueRepository(),
        syncEngine: SyncEngine(),
        isMockCoachPath: true
    )

    /// Returns the appropriate dependencies based on environment:
    /// - `.fixture` when UITEST_USE_FIXTURES=true
    /// - `.live` otherwise
    /// nonisolated so it can be used as a default parameter value in
    /// @MainActor ViewModel inits without requiring a concurrent call site.
    static var current: AppDependencies {
        if UITestEnvironment.shared.useFixtures {
            return .fixture
        }
        return .live
    }
    #else
    static var current: AppDependencies { .live }
    #endif
}

// MARK: - Mock Implementations

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
