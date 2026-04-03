//
//  Phase2ViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for AMA-1133 Phase 2 ViewModels: Calendar, Coach, ActivityFeed, TrainingPreferences
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class Phase2CalendarViewModelTests: XCTestCase {

    var viewModel: CalendarViewModel!
    var mockAPI: MockAPIService!

    override func setUp() async throws {
        mockAPI = MockAPIService()
        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        viewModel = CalendarViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPI = nil
    }

    func testLoadDayStates() async {
        let dayState = DayState(
            date: "2026-03-22",
            readiness: .green,
            plannedWorkouts: [
                PlannedWorkout(id: "w1", name: "Easy Run", sport: "running", estimatedDurationMinutes: 45, scheduledTime: "07:00", priority: .normal)
            ],
            completedWorkouts: [],
            fatigueScore: 30.0,
            notes: nil
        )
        mockAPI.fetchDayStatesResult = .success([dayState])

        let from = Date()
        let to = Calendar.current.date(byAdding: .day, value: 7, to: from)!
        await viewModel.loadDayStates(from: from, to: to)

        XCTAssertTrue(mockAPI.fetchDayStatesCalled)
        XCTAssertEqual(viewModel.dayStates.count, 1)
        XCTAssertEqual(viewModel.dayStates["2026-03-22"]?.readiness, .green)
        XCTAssertFalse(viewModel.isLoadingDayStates)
    }

    func testGenerateWeek() async {
        let plan = ProposedPlan(
            weekStartDate: "2026-03-23",
            days: [
                ProposedDay(date: "2026-03-23", workouts: [], isRestDay: true, rationale: "Recovery after hard week"),
                ProposedDay(date: "2026-03-24", workouts: [
                    PlannedWorkout(id: "w1", name: "Tempo Run", sport: "running", estimatedDurationMinutes: 50, scheduledTime: nil, priority: .key)
                ], isRestDay: false, rationale: "Key session for marathon block")
            ],
            rationale: "Building towards peak week",
            totalLoadScore: 85.0
        )
        mockAPI.generateWeekResult = .success(plan)

        await viewModel.generateWeek()

        XCTAssertTrue(mockAPI.generateWeekCalled)
        XCTAssertNotNil(viewModel.proposedPlan)
        XCTAssertEqual(viewModel.proposedPlan?.days.count, 2)
        XCTAssertEqual(viewModel.proposedPlan?.totalLoadScore, 85.0)
        XCTAssertFalse(viewModel.isGeneratingWeek)
    }

    func testGenerateWeekError() async {
        mockAPI.generateWeekResult = .failure(APIError.serverError(500))

        await viewModel.generateWeek()

        XCTAssertTrue(mockAPI.generateWeekCalled)
        XCTAssertNil(viewModel.proposedPlan)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testDetectConflicts() async {
        let conflict = Conflict(
            id: "c1",
            date: "2026-03-24",
            type: .overload,
            description: "Too many hard sessions in a row",
            severity: .high,
            suggestion: "Move tempo run to Wednesday"
        )
        mockAPI.detectConflictsResult = .success([conflict])

        let from = Date()
        let to = Calendar.current.date(byAdding: .day, value: 7, to: from)!
        await viewModel.detectConflicts(from: from, to: to)

        XCTAssertTrue(mockAPI.detectConflictsCalled)
        XCTAssertEqual(viewModel.conflicts.count, 1)
        XCTAssertEqual(viewModel.conflicts.first?.severity, .high)
    }

    func testReadinessForDate() async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let today = Date()
        let todayStr = formatter.string(from: today)

        let dayState = DayState(
            date: todayStr,
            readiness: .yellow,
            plannedWorkouts: [],
            completedWorkouts: [],
            fatigueScore: nil,
            notes: nil
        )
        mockAPI.fetchDayStatesResult = .success([dayState])

        let end = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        await viewModel.loadDayStates(from: today, to: end)

        let readiness = viewModel.readiness(for: today)
        XCTAssertEqual(readiness, .yellow)
    }
}

// MARK: - Coach ViewModel Tests
// NOTE: Updated for AMA-1410 streaming ViewModel. Full streaming tests are in CoachViewModelStreamingTests.swift.

@MainActor
final class Phase2CoachViewModelTests: XCTestCase {

    var viewModel: CoachViewModel!
    var mockAPI: MockAPIService!
    var mockStreamService: MockChatStreamService!
    var mockPairingService: MockPairingService!

    override func setUp() async throws {
        mockAPI = MockAPIService()
        mockStreamService = MockChatStreamService()
        mockPairingService = MockPairingService()
        mockPairingService.storedToken = "test-token"
        mockPairingService.isPaired = true
        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: mockStreamService
        )
        viewModel = CoachViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPI = nil
        mockStreamService = nil
        mockPairingService = nil
    }

    func testSendMessage() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Great question! Here is my advice..."),
            .messageEnd(sessionId: "s1", tokensUsed: 50, latencyMs: 500)
        ]

        await viewModel.sendMessage("How should I train today?")

        XCTAssertTrue(mockStreamService.streamCalled)
        XCTAssertEqual(viewModel.messages.count, 2) // user + assistant
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].content, "How should I train today?")
        XCTAssertEqual(viewModel.messages[1].role, .assistant)
        XCTAssertEqual(viewModel.messages[1].content, "Great question! Here is my advice...")
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testSendMessageError() async {
        mockStreamService.errorToThrow = APIError.serverError(500)

        await viewModel.sendMessage("Hello")

        // Both user and assistant messages removed when stream errors with no content
        XCTAssertEqual(viewModel.messages.count, 0)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testLoadFatigueAdvice() async {
        let advice = FatigueAdvice(
            level: .moderate,
            message: "You are moderately fatigued",
            recommendations: ["Take it easy", "Sleep more"],
            suggestedRestDays: 1,
            recoveryActivities: ["Yoga", "Walking"]
        )
        mockAPI.getFatigueAdviceResult = .success(advice)

        await viewModel.loadFatigueAdvice()

        XCTAssertTrue(mockAPI.getFatigueAdviceCalled)
        XCTAssertNotNil(viewModel.fatigueAdvice)
        XCTAssertEqual(viewModel.fatigueAdvice?.level, .moderate)
        XCTAssertEqual(viewModel.fatigueAdvice?.recommendations.count, 2)
    }

    func testRateLimitEventSetsRateLimitInfo() async {
        mockStreamService.eventsToYield = [
            .error(type: "rate_limit_exceeded", message: "Limit reached", usage: 50, limit: 50)
        ]

        await viewModel.sendMessage("Hello")

        XCTAssertNotNil(viewModel.rateLimitInfo)
        XCTAssertEqual(viewModel.rateLimitInfo?.limit, 50)
    }
}

// MARK: - Activity Feed ViewModel Tests

@MainActor
final class Phase2ActivityFeedViewModelTests: XCTestCase {

    var viewModel: ActivityFeedViewModel!
    var mockAPI: MockAPIService!

    override func setUp() async throws {
        mockAPI = MockAPIService()
        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        viewModel = ActivityFeedViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPI = nil
    }

    func testLoadActions() async {
        let actions = [
            PendingAction(
                id: "a1",
                type: .workoutSuggestion,
                title: "Add tempo run to Wednesday",
                description: "Based on your goals",
                createdAt: "2026-03-22T10:00:00Z",
                metadata: nil,
                status: .pending
            ),
            PendingAction(
                id: "a2",
                type: .recoveryReminder,
                title: "Take a rest day",
                description: nil,
                createdAt: "2026-03-21T08:00:00Z",
                metadata: nil,
                status: .approved
            )
        ]
        mockAPI.fetchPendingActionsResult = .success(actions)

        await viewModel.loadActions()

        XCTAssertTrue(mockAPI.fetchPendingActionsCalled)
        XCTAssertEqual(viewModel.actions.count, 2)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testApproveAction() async {
        let action = PendingAction(
            id: "a1",
            type: .workoutSuggestion,
            title: "Test",
            description: nil,
            createdAt: nil,
            metadata: nil,
            status: .pending
        )
        mockAPI.fetchPendingActionsResult = .success([action])
        mockAPI.respondToActionResult = .success(ActionResponse(success: true, message: "Approved"))

        await viewModel.approveAction(action)

        XCTAssertTrue(mockAPI.respondToActionCalled)
    }

    func testRejectAction() async {
        let action = PendingAction(
            id: "a1",
            type: .scheduleChange,
            title: "Test",
            description: nil,
            createdAt: nil,
            metadata: nil,
            status: .pending
        )
        mockAPI.fetchPendingActionsResult = .success([action])
        mockAPI.respondToActionResult = .success(ActionResponse(success: true, message: "Rejected"))

        await viewModel.rejectAction(action)

        XCTAssertTrue(mockAPI.respondToActionCalled)
    }

    func testUndoAction() async {
        let action = PendingAction(
            id: "a1",
            type: .general,
            title: "Test",
            description: nil,
            createdAt: nil,
            metadata: nil,
            status: .approved
        )
        mockAPI.fetchPendingActionsResult = .success([action])
        mockAPI.respondToActionResult = .success(ActionResponse(success: true, message: "Undone"))

        await viewModel.undoAction(action)

        XCTAssertTrue(mockAPI.respondToActionCalled)
    }

    func testLoadActionsError() async {
        mockAPI.fetchPendingActionsResult = .failure(APIError.networkError(URLError(.notConnectedToInternet)))

        await viewModel.loadActions()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.actions.isEmpty)
    }
}

// MARK: - Training Preferences ViewModel Tests

@MainActor
final class Phase2TrainingPreferencesViewModelTests: XCTestCase {

    var viewModel: TrainingPreferencesViewModel!
    var mockAPI: MockAPIService!

    override func setUp() async throws {
        mockAPI = MockAPIService()
        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        viewModel = TrainingPreferencesViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPI = nil
    }

    func testLoadPreferences() async {
        let prefs = NotificationPreferences(
            workoutReminders: true,
            coachMessages: false,
            weeklyReport: true,
            conflictAlerts: true,
            recoveryReminders: false,
            reminderMinutesBefore: 60,
            weeklyVolume: 80,
            hardDayCap: 2,
            runDaysPerWeek: 6,
            goalRace: "marathon",
            goalRaceDate: "2026-10-15",
            preferredLongRunDay: 1
        )
        mockAPI.fetchNotificationPreferencesResult = .success(prefs)

        await viewModel.loadPreferences()

        XCTAssertTrue(mockAPI.fetchNotificationPreferencesCalled)
        XCTAssertEqual(viewModel.preferences.weeklyVolume, 80)
        XCTAssertEqual(viewModel.preferences.hardDayCap, 2)
        XCTAssertEqual(viewModel.preferences.goalRace, "marathon")
        XCTAssertFalse(viewModel.preferences.coachMessages)
    }

    func testSavePreferences() async {
        let savedPrefs = NotificationPreferences(
            workoutReminders: true,
            coachMessages: true,
            weeklyReport: false,
            conflictAlerts: true,
            recoveryReminders: true,
            reminderMinutesBefore: 30,
            weeklyVolume: 60,
            hardDayCap: 3,
            runDaysPerWeek: 5
        )
        mockAPI.updateNotificationPreferencesResult = .success(savedPrefs)

        viewModel.preferences.weeklyVolume = 60
        await viewModel.savePreferences()

        XCTAssertTrue(mockAPI.updateNotificationPreferencesCalled)
        XCTAssertTrue(viewModel.saveSuccess)
        XCTAssertFalse(viewModel.isSaving)
    }

    func testSavePreferencesError() async {
        mockAPI.updateNotificationPreferencesResult = .failure(APIError.networkError(URLError(.notConnectedToInternet)))

        await viewModel.savePreferences()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.saveSuccess)
    }
}
