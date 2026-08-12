//
//  PassiveStrengthSessionEngineTests.swift
//  AmakaFlowWatch Watch AppTests
//
//  AMA-2420 — passive free-capture elapsed formatting helpers.
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

    @Test @MainActor func engineStartsIdle() {
        let engine = PassiveStrengthSessionEngine()
        #expect(engine.formattedElapsedTime == "0:00")
        #expect(engine.phase == .idle)
        #expect(!engine.isActive)
        #expect(!engine.summaryQueued)
    }

    @Test func freeformIDStillMarksPassiveSessions() {
        let workout = FreeformStrengthWorkout.make(uniqueSuffix: "passive")
        #expect(FreeformStrengthWorkout.isFreeformID(workout.id))
        #expect(workout.id.contains("passive"))
    }
}
