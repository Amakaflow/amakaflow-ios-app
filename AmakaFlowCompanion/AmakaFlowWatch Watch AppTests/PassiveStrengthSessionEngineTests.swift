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
    @Test @MainActor func elapsedFormatsMinutesAndSeconds() {
        let engine = PassiveStrengthSessionEngine()
        #expect(engine.formattedElapsedTime == "0:00")
        #expect(engine.phase == .idle)
        #expect(!engine.isActive)
    }

    @Test func freeformIDStillMarksPassiveSessions() {
        let workout = FreeformStrengthWorkout.make(uniqueSuffix: "passive")
        #expect(FreeformStrengthWorkout.isFreeformID(workout.id))
        #expect(workout.id.contains("passive"))
    }
}
