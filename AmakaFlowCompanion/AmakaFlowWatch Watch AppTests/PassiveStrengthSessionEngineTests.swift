//
//  PassiveStrengthSessionEngineTests.swift
//  AmakaFlowWatch Watch AppTests
//
//  AMA-2420 — passive free-capture elapsed formatting helpers.
//  AMA-2428 — sport resolution + summary Codable.
//

@testable import AmakaFlowWatch_Watch_App
import Foundation
import Testing

struct PassiveStrengthSessionEngineTests {
    @Test func elapsedFormatsMinutesAndSeconds() {
        #expect(PassiveStrengthSessionEngine.formatElapsed(seconds: 0) == "0:00")
        #expect(PassiveStrengthSessionEngine.formatElapsed(seconds: 65) == "1:05")
        #expect(PassiveStrengthSessionEngine.formatElapsed(seconds: 3_600) == "60:00")
        #expect(PassiveStrengthSessionEngine.formatElapsed(seconds: -5) == "0:00")
    }

    @Test func activeElapsedUsesWallClockSegments() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_065)
        #expect(
            PassiveStrengthSessionEngine.activeElapsedSeconds(
                accumulatedActive: 10,
                runningSince: start,
                now: now
            ) == 75
        )
        #expect(
            PassiveStrengthSessionEngine.activeElapsedSeconds(
                accumulatedActive: 42,
                runningSince: nil,
                now: now
            ) == 42
        )
    }

    @Test @MainActor func engineStartsIdle() {
        let engine = PassiveStrengthSessionEngine()
        #expect(engine.formattedElapsedTime == "0:00")
        #expect(engine.phase == .idle)
        #expect(!engine.isActive)
        #expect(!engine.summaryQueued)
        #expect(!engine.healthCaptureFailed)
        #expect(engine.selectedSport == .strength)
        #expect(engine.sessionDisplayName == "Strength")
    }

    @Test func freeformIDStillMarksPassiveSessions() {
        let workout = FreeformStrengthWorkout.make(uniqueSuffix: "passive")
        #expect(FreeformStrengthWorkout.isFreeformID(workout.id))
        #expect(workout.id.contains("passive"))
    }

    @Test func resolvedSportDefaultsMissingToStrength() {
        #expect(PassiveStrengthSessionEngine.resolvedSport(from: nil) == .strength)
        #expect(PassiveStrengthSessionEngine.resolvedSport(from: "  ") == .strength)
        #expect(PassiveStrengthSessionEngine.resolvedSport(from: "mixed") == .mixed)
        #expect(PassiveStrengthSessionEngine.resolvedSport(from: "ride") == .cycling)
    }

    @Test func passivePickerPutsStrengthAndMixedFirst() {
        let options = WorkoutSport.passiveSessionPickerOptions
        #expect(options.first == .strength)
        #expect(options.dropFirst().first == .mixed)
        #expect(options.contains(.other))
        #expect(options.count == WorkoutSport.allCases.count)
    }

    @Test func summarySportRoundTripsThroughCodable() throws {
        let original = StandaloneWorkoutSummary(
            workoutId: "id-1",
            workoutName: "Mixed",
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            totalCalories: 50,
            averageHeartRate: 120,
            completedSteps: 0,
            totalSteps: 0,
            setLogs: nil,
            sport: WorkoutSport.mixed.rawValue
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StandaloneWorkoutSummary.self, from: data)
        #expect(decoded.sport == "mixed")
        #expect(decoded.workoutName == "Mixed")
    }

    @Test func legacySummaryWithoutSportStillDecodes() throws {
        let json = """
        {
          "workoutId": "legacy",
          "workoutName": "Strength",
          "startDate": "2026-08-12T12:00:00Z",
          "endDate": "2026-08-12T12:40:00Z",
          "durationSeconds": 2400,
          "totalCalories": 100,
          "averageHeartRate": 110,
          "completedSteps": 0,
          "totalSteps": 0
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StandaloneWorkoutSummary.self, from: json)
        #expect(decoded.sport == nil)
        #expect(PassiveStrengthSessionEngine.resolvedSport(from: decoded.sport) == .strength)
    }
}
