//
//  APIIntegrationTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for new API client methods and view models (AMA-1147)
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - Model Decoding Tests

final class PlanningModelTests: XCTestCase {

    func testDayStateDecoding() throws {
        let json = """
        {
            "date": "2026-03-21",
            "readiness": "green",
            "planned_workouts": [],
            "completed_workouts": ["w1"],
            "fatigue_score": 0.35,
            "notes": "Good day"
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let state = try decoder.decode(DayState.self, from: json)

        XCTAssertEqual(state.date, "2026-03-21")
        XCTAssertEqual(state.readiness, .green)
        XCTAssertEqual(state.completedWorkouts, ["w1"])
        XCTAssertEqual(state.fatigueScore, 0.35)
        XCTAssertEqual(state.notes, "Good day")
    }

    func testConflictDecoding() throws {
        let json = """
        {
            "id": "c1",
            "date": "2026-03-22",
            "type": "overload",
            "description": "Too many hard sessions",
            "severity": "high",
            "suggestion": "Move one session to Thursday"
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let conflict = try decoder.decode(Conflict.self, from: json)

        XCTAssertEqual(conflict.id, "c1")
        XCTAssertEqual(conflict.type, .overload)
        XCTAssertEqual(conflict.severity, .high)
        XCTAssertNotNil(conflict.suggestion)
    }

    func testProposedPlanDecoding() throws {
        let json = """
        {
            "week_start_date": "2026-03-23",
            "days": [
                {
                    "date": "2026-03-23",
                    "workouts": [],
                    "is_rest_day": true,
                    "rationale": "Recovery day"
                }
            ],
            "rationale": "Balanced week",
            "total_load_score": 42.5
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let plan = try decoder.decode(ProposedPlan.self, from: json)

        XCTAssertEqual(plan.weekStartDate, "2026-03-23")
        XCTAssertEqual(plan.days.count, 1)
        XCTAssertTrue(plan.days[0].isRestDay)
        XCTAssertEqual(plan.totalLoadScore, 42.5)
    }

    func testReadinessLevelAllCases() {
        XCTAssertNotNil(ReadinessLevel(rawValue: "green"))
        XCTAssertNotNil(ReadinessLevel(rawValue: "yellow"))
        XCTAssertNotNil(ReadinessLevel(rawValue: "red"))
        XCTAssertNotNil(ReadinessLevel(rawValue: "rest"))
        XCTAssertNotNil(ReadinessLevel(rawValue: "unknown"))
        XCTAssertNil(ReadinessLevel(rawValue: "invalid"))
    }
}

// MARK: - Coach Model Tests

final class CoachModelTests: XCTestCase {

    func testCoachResponseDecoding() throws {
        let json = """
        {
            "id": "resp1",
            "message": "Focus on recovery today",
            "suggestions": [
                {"id": "s1", "text": "Light yoga", "type": "recovery"}
            ],
            "action_items": [
                {"id": "a1", "title": "Schedule rest day", "description": "Take tomorrow off"}
            ]
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let response = try decoder.decode(CoachResponse.self, from: json)

        XCTAssertEqual(response.message, "Focus on recovery today")
        XCTAssertEqual(response.suggestions?.count, 1)
        XCTAssertEqual(response.suggestions?.first?.type, .recovery)
        XCTAssertEqual(response.actionItems?.count, 1)
    }

    func testFatigueAdviceDecoding() throws {
        let json = """
        {
            "level": "moderate",
            "message": "Take it easy",
            "recommendations": ["Stretch", "Hydrate"],
            "suggested_rest_days": 2,
            "recovery_activities": ["yoga", "walking"]
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let advice = try decoder.decode(FatigueAdvice.self, from: json)

        XCTAssertEqual(advice.level, .moderate)
        XCTAssertEqual(advice.recommendations.count, 2)
        XCTAssertEqual(advice.suggestedRestDays, 2)
    }

    func testCoachMemoryDecoding() throws {
        let json = """
        {
            "id": "mem1",
            "content": "User prefers morning runs",
            "category": "preference",
            "created_at": "2026-03-20",
            "relevance": 0.95
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let memory = try decoder.decode(CoachMemory.self, from: json)

        XCTAssertEqual(memory.id, "mem1")
        XCTAssertEqual(memory.category, "preference")
        XCTAssertEqual(memory.relevance, 0.95)
    }
}

// MARK: - Action Model Tests

final class ActionModelTests: XCTestCase {

    func testPendingActionDecoding() throws {
        let json = """
        {
            "id": "act1",
            "type": "workout_suggestion",
            "title": "Add interval session",
            "description": "Based on your goals",
            "created_at": "2026-03-21T10:00:00Z",
            "metadata": {"workout_id": "w1", "date": "2026-03-22"},
            "status": "pending"
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let action = try decoder.decode(PendingAction.self, from: json)

        XCTAssertEqual(action.id, "act1")
        XCTAssertEqual(action.type, .workoutSuggestion)
        XCTAssertEqual(action.status, .pending)
        XCTAssertEqual(action.metadata?.workoutId, "w1")
    }

    func testActionResponseDecoding() throws {
        let json = """
        {"success": true, "message": "Action approved"}
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let response = try decoder.decode(ActionResponse.self, from: json)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.message, "Action approved")
    }
}

// MARK: - Analytics Model Tests

final class AnalyticsModelTests: XCTestCase {

    func testShoeStatsDecoding() throws {
        let json = """
        {
            "id": "shoe1",
            "name": "Pegasus 41",
            "brand": "Nike",
            "total_distance_km": 523.4,
            "total_runs": 87,
            "average_pace_min_km": 5.12,
            "retired_at": null,
            "added_at": "2025-06-01"
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let shoe = try decoder.decode(ShoeStats.self, from: json)

        XCTAssertEqual(shoe.name, "Pegasus 41")
        XCTAssertEqual(shoe.brand, "Nike")
        XCTAssertEqual(shoe.totalDistanceKm, 523.4)
        XCTAssertEqual(shoe.totalRuns, 87)
        XCTAssertNil(shoe.retiredAt)
    }

    func testSubscriptionDecoding() throws {
        let json = """
        {
            "plan": "pro",
            "status": "active",
            "current_period_end": "2026-04-21",
            "cancel_at_period_end": false,
            "features": ["coach", "analytics", "planning"]
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let sub = try decoder.decode(Subscription.self, from: json)

        XCTAssertEqual(sub.plan, "pro")
        XCTAssertEqual(sub.status, .active)
        XCTAssertEqual(sub.features?.count, 3)
    }

    func testNotificationPreferencesDecoding() throws {
        let json = """
        {
            "workout_reminders": true,
            "coach_messages": false,
            "weekly_report": true,
            "conflict_alerts": true,
            "recovery_reminders": false,
            "reminder_minutes_before": 60
        }
        """.data(using: .utf8)!

        let decoder = APIService.makeDecoder()
        let prefs = try decoder.decode(NotificationPreferences.self, from: json)

        XCTAssertTrue(prefs.workoutReminders)
        XCTAssertFalse(prefs.coachMessages)
        XCTAssertEqual(prefs.reminderMinutesBefore, 60)
    }

    func testNotificationPreferencesDefaults() {
        let prefs = NotificationPreferences()
        XCTAssertTrue(prefs.workoutReminders)
        XCTAssertTrue(prefs.coachMessages)
        XCTAssertTrue(prefs.weeklyReport)
        XCTAssertEqual(prefs.reminderMinutesBefore, 30)
    }
}

// MARK: - Mock API Service Tests

final class MockAPIServiceNewEndpointsTests: XCTestCase {

    @MainActor
    func testMockFetchDayStates() async throws {
        let mock = MockAPIService()
        let sampleState = DayState(
            date: "2026-03-21",
            readiness: .green,
            plannedWorkouts: [],
            completedWorkouts: [],
            fatigueScore: nil,
            notes: nil
        )
        mock.fetchDayStatesResult = .success([sampleState])

        let states = try await mock.fetchDayStates(from: "2026-03-21", to: "2026-03-27")
        XCTAssertTrue(mock.fetchDayStatesCalled)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].readiness, .green)
    }

    @MainActor
    func testMockSendCoachMessage() async throws {
        let mock = MockAPIService()
        mock.sendCoachMessageResult = .success(
            CoachResponse(id: "1", message: "Rest today", suggestions: nil, actionItems: nil)
        )

        let response = try await mock.sendCoachMessage(message: "How should I train?", context: nil)
        XCTAssertTrue(mock.sendCoachMessageCalled)
        XCTAssertEqual(response.message, "Rest today")
    }

    @MainActor
    func testMockFetchPendingActions() async throws {
        let mock = MockAPIService()
        let action = PendingAction(
            id: "a1",
            type: .workoutSuggestion,
            title: "Add run",
            description: nil,
            createdAt: nil,
            metadata: nil,
            status: .pending
        )
        mock.fetchPendingActionsResult = .success([action])

        let actions = try await mock.fetchPendingActions()
        XCTAssertTrue(mock.fetchPendingActionsCalled)
        XCTAssertEqual(actions.count, 1)
    }

    @MainActor
    func testMockRespondToAction() async throws {
        let mock = MockAPIService()
        let response = try await mock.respondToAction(id: "a1", response: "approve")
        XCTAssertTrue(mock.respondToActionCalled)
        XCTAssertTrue(response.success)
    }

    @MainActor
    func testMockFetchShoeComparison() async throws {
        let mock = MockAPIService()
        let shoe = ShoeStats(
            id: "s1", name: "Vaporfly", brand: "Nike",
            totalDistanceKm: 100, totalRuns: 20,
            averagePaceMinKm: 4.5, retiredAt: nil, addedAt: nil
        )
        mock.fetchShoeComparisonResult = .success([shoe])

        let shoes = try await mock.fetchShoeComparison()
        XCTAssertTrue(mock.fetchShoeComparisonCalled)
        XCTAssertEqual(shoes.count, 1)
        XCTAssertEqual(shoes[0].name, "Vaporfly")
    }

    @MainActor
    func testMockFetchNotificationPreferences() async throws {
        let mock = MockAPIService()
        let prefs = try await mock.fetchNotificationPreferences()
        XCTAssertTrue(mock.fetchNotificationPreferencesCalled)
        XCTAssertTrue(prefs.workoutReminders)
    }
}

// MARK: - ViewModel Tests

final class CalendarViewModelTests: XCTestCase {

    @MainActor
    func testLoadDayStatesPopulatesDict() async {
        let mock = MockAPIService()
        let state = DayState(
            date: "2026-03-21",
            readiness: .yellow,
            plannedWorkouts: [],
            completedWorkouts: [],
            fatigueScore: 0.6,
            notes: nil
        )
        mock.fetchDayStatesResult = .success([state])

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = CalendarViewModel(dependencies: deps)

        await vm.loadDayStates(from: Date(), to: Date())
        XCTAssertFalse(vm.dayStates.isEmpty)
        XCTAssertEqual(vm.dayStates["2026-03-21"]?.readiness, .yellow)
    }

    @MainActor
    func testGenerateWeekSetsProposedPlan() async {
        let mock = MockAPIService()
        let plan = ProposedPlan(
            weekStartDate: "2026-03-23",
            days: [],
            rationale: "Test plan",
            totalLoadScore: 50
        )
        mock.generateWeekResult = .success(plan)

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = CalendarViewModel(dependencies: deps)

        await vm.generateWeek()
        XCTAssertNotNil(vm.proposedPlan)
        XCTAssertEqual(vm.proposedPlan?.rationale, "Test plan")
    }
}

final class CoachViewModelTests: XCTestCase {

    @MainActor
    func testSendMessageAppendsMessages() async {
        let mock = MockAPIService()
        mock.sendCoachMessageResult = .success(
            CoachResponse(id: "1", message: "Coach reply", suggestions: nil, actionItems: nil)
        )

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = CoachViewModel(dependencies: deps)

        await vm.sendMessage("Hello coach")
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].role, .user)
        XCTAssertEqual(vm.messages[0].content, "Hello coach")
        XCTAssertEqual(vm.messages[1].role, .assistant)
        XCTAssertEqual(vm.messages[1].content, "Coach reply")
    }

    @MainActor
    func testSendMessageHandlesError() async {
        let mock = MockAPIService()
        // sendCoachMessageResult is nil, so it throws notImplemented

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = CoachViewModel(dependencies: deps)

        await vm.sendMessage("Hello")
        XCTAssertEqual(vm.messages.count, 0) // User message removed on failure
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testLoadFatigueAdvice() async {
        let mock = MockAPIService()
        mock.getFatigueAdviceResult = .success(
            FatigueAdvice(level: .low, message: "You're fine", recommendations: ["Run"], suggestedRestDays: nil, recoveryActivities: nil)
        )

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = CoachViewModel(dependencies: deps)

        await vm.loadFatigueAdvice()
        XCTAssertNotNil(vm.fatigueAdvice)
        XCTAssertEqual(vm.fatigueAdvice?.level, .low)
    }
}

final class ActivityFeedViewModelTests: XCTestCase {

    @MainActor
    func testLoadActions() async {
        let mock = MockAPIService()
        let action = PendingAction(
            id: "a1", type: .recoveryReminder, title: "Rest day",
            description: "Take a break", createdAt: nil, metadata: nil, status: .pending
        )
        mock.fetchPendingActionsResult = .success([action])

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = ActivityFeedViewModel(dependencies: deps)

        await vm.loadActions()
        XCTAssertEqual(vm.actions.count, 1)
        XCTAssertEqual(vm.actions[0].title, "Rest day")
    }

    @MainActor
    func testApproveAction() async {
        let mock = MockAPIService()
        let action = PendingAction(
            id: "a1", type: .general, title: "Test",
            description: nil, createdAt: nil, metadata: nil, status: .pending
        )
        mock.fetchPendingActionsResult = .success([])

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = ActivityFeedViewModel(dependencies: deps)

        await vm.approveAction(action)
        XCTAssertTrue(mock.respondToActionCalled)
    }
}

final class ShoeComparisonViewModelTests: XCTestCase {

    @MainActor
    func testLoadShoes() async {
        let mock = MockAPIService()
        let shoes = [
            ShoeStats(id: "s1", name: "Shoe A", brand: nil, totalDistanceKm: 100, totalRuns: 10, averagePaceMinKm: nil, retiredAt: nil, addedAt: nil),
            ShoeStats(id: "s2", name: "Shoe B", brand: nil, totalDistanceKm: 200, totalRuns: 20, averagePaceMinKm: nil, retiredAt: nil, addedAt: nil),
        ]
        mock.fetchShoeComparisonResult = .success(shoes)

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = ShoeComparisonViewModel(dependencies: deps)

        await vm.loadShoes()
        XCTAssertEqual(vm.shoes.count, 2)
        XCTAssertEqual(vm.totalDistance, 300)
        XCTAssertEqual(vm.totalRuns, 30)
    }
}

final class TrainingPreferencesViewModelTests: XCTestCase {

    @MainActor
    func testLoadPreferences() async {
        let mock = MockAPIService()
        let prefs = NotificationPreferences(
            workoutReminders: false,
            coachMessages: true,
            weeklyReport: false,
            conflictAlerts: true,
            recoveryReminders: true,
            reminderMinutesBefore: 60
        )
        mock.fetchNotificationPreferencesResult = .success(prefs)

        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = TrainingPreferencesViewModel(dependencies: deps)

        await vm.loadPreferences()
        XCTAssertFalse(vm.preferences.workoutReminders)
        XCTAssertEqual(vm.preferences.reminderMinutesBefore, 60)
    }

    @MainActor
    func testSavePreferences() async {
        let mock = MockAPIService()
        let deps = AppDependencies(
            apiService: mock,
            pairingService: await MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )
        let vm = TrainingPreferencesViewModel(dependencies: deps)

        await vm.savePreferences()
        XCTAssertTrue(mock.updateNotificationPreferencesCalled)
        XCTAssertTrue(vm.saveSuccess)
    }
}
