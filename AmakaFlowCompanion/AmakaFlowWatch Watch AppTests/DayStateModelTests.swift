//
//  DayStateModelTests.swift
//  AmakaFlowWatch Watch AppTests
//
//  Tests for DayState models, decoding, and readiness labels (AMA-1150)
//

import Foundation
import Testing
@testable import AmakaFlowWatch_Watch_App

struct DayStateModelTests {

    // MARK: - ReadinessLabel Tests

    @Test func readinessLabelReady() {
        let label = ReadinessLabel.ready
        #expect(label.displayText == "Ready to train")
        #expect(label.rawValue == "ready")
    }

    @Test func readinessLabelModerate() {
        let label = ReadinessLabel.moderate
        #expect(label.displayText == "Take it easy")
        #expect(label.rawValue == "moderate")
    }

    @Test func readinessLabelRest() {
        let label = ReadinessLabel.rest
        #expect(label.displayText == "Rest day")
        #expect(label.rawValue == "rest")
    }

    // MARK: - DayState Coding

    @Test func dayStateDecodingFromJSON() throws {
        let json = """
        {
            "date": "2026-03-21",
            "readiness_score": 82,
            "readiness_label": "ready",
            "sessions": [
                {
                    "id": "s1",
                    "name": "Morning Run",
                    "scheduled_time": "08:30",
                    "sport": "running",
                    "duration_minutes": 45,
                    "is_completed": false,
                    "is_next": true
                },
                {
                    "id": "s2",
                    "name": "Strength",
                    "scheduled_time": "17:00",
                    "sport": "strength",
                    "duration_minutes": 60,
                    "is_completed": false,
                    "is_next": false
                }
            ],
            "conflict_alert": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dayState = try decoder.decode(DayState.self, from: json)

        #expect(dayState.date == "2026-03-21")
        #expect(dayState.readinessScore == 82)
        #expect(dayState.readinessLabel == .ready)
        #expect(dayState.sessions.count == 2)
        #expect(dayState.sessions[0].name == "Morning Run")
        #expect(dayState.sessions[0].isNext == true)
        #expect(dayState.sessions[1].isNext == false)
        #expect(dayState.conflictAlert == nil)
    }

    @Test func dayStateWithConflictAlert() throws {
        let json = """
        {
            "date": "2026-03-21",
            "readiness_score": 45,
            "readiness_label": "moderate",
            "sessions": [],
            "conflict_alert": {
                "message": "Hard session tomorrow but you trained hard today",
                "severity": "warning",
                "suggested_action": "Consider reducing intensity"
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dayState = try decoder.decode(DayState.self, from: json)

        #expect(dayState.readinessLabel == .moderate)
        #expect(dayState.conflictAlert != nil)
        #expect(dayState.conflictAlert?.message == "Hard session tomorrow but you trained hard today")
        #expect(dayState.conflictAlert?.severity == .warning)
        #expect(dayState.conflictAlert?.suggestedAction == "Consider reducing intensity")
    }

    @Test func dayStateEmptySessionsRestDay() throws {
        let json = """
        {
            "date": "2026-03-21",
            "readiness_score": 25,
            "readiness_label": "rest",
            "sessions": [],
            "conflict_alert": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dayState = try decoder.decode(DayState.self, from: json)

        #expect(dayState.readinessLabel == .rest)
        #expect(dayState.sessions.isEmpty)
    }

    // MARK: - PlannedSession Tests

    @Test func plannedSessionIdentifiable() {
        let session = PlannedSession(
            id: "test-id",
            name: "Test Session",
            scheduledTime: "10:00",
            sport: "running",
            durationMinutes: 30,
            isCompleted: false,
            isNext: true
        )

        #expect(session.id == "test-id")
        #expect(session.name == "Test Session")
        #expect(session.isNext == true)
        #expect(session.isCompleted == false)
    }

    @Test func plannedSessionCompleted() {
        let session = PlannedSession(
            id: "done",
            name: "Morning Run",
            scheduledTime: "06:00",
            sport: "running",
            durationMinutes: 45,
            isCompleted: true,
            isNext: false
        )

        #expect(session.isCompleted == true)
        #expect(session.isNext == false)
    }

    // MARK: - ConflictAlert Tests

    @Test func conflictAlertCriticalSeverity() {
        let alert = ConflictAlert(
            message: "Overtraining risk detected",
            severity: .critical,
            suggestedAction: "Take a rest day"
        )

        #expect(alert.severity == .critical)
        #expect(alert.suggestedAction == "Take a rest day")
    }

    // MARK: - CoachResponse Tests

    @Test func coachResponseDecoding() throws {
        let json = """
        {
            "answer": "You are progressing well. Your consistency is great.",
            "question": "How am I doing?"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CoachResponse.self, from: json)
        #expect(response.question == "How am I doing?")
        #expect(response.answer.contains("progressing"))
    }

    // MARK: - QuickCoachQuestion Tests

    @Test func quickCoachQuestionsAllCasesCount() {
        #expect(QuickCoachQuestion.allCases.count == 3)
    }

    @Test func quickCoachQuestionsHaveSystemImages() {
        for question in QuickCoachQuestion.allCases {
            #expect(!question.systemImage.isEmpty)
            #expect(!question.rawValue.isEmpty)
            #expect(question.id == question.rawValue)
        }
    }

    // MARK: - DayState Equality

    @Test func dayStateEquality() {
        let a = DayState(
            date: "2026-03-21",
            readinessScore: 80,
            readinessLabel: .ready,
            sessions: [],
            conflictAlert: nil
        )
        let b = DayState(
            date: "2026-03-21",
            readinessScore: 80,
            readinessLabel: .ready,
            sessions: [],
            conflictAlert: nil
        )
        #expect(a == b)
    }

    @Test func dayStateInequality() {
        let a = DayState(
            date: "2026-03-21",
            readinessScore: 80,
            readinessLabel: .ready,
            sessions: [],
            conflictAlert: nil
        )
        let b = DayState(
            date: "2026-03-21",
            readinessScore: 50,
            readinessLabel: .moderate,
            sessions: [],
            conflictAlert: nil
        )
        #expect(a != b)
    }
}
