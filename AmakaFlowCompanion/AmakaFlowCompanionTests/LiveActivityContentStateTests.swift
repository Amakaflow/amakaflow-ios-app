//
//  LiveActivityContentStateTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for WorkoutActivityAttributes.ContentState helpers introduced in issue #308:
//  stepDeadline (live countdown), activityStaleDate (staleness dimming).
//

import XCTest
@testable import AmakaFlowCompanion

final class LiveActivityContentStateTests: XCTestCase {

    // MARK: - stepDeadline encode/decode

    func testContentStateRoundTripWithDeadline() throws {
        let deadline = Date(timeIntervalSince1970: 1_700_000_000)
        let state = WorkoutActivityAttributes.ContentState(
            phase: "running",
            stepName: "Burpees",
            stepIndex: 3,
            stepCount: 10,
            remainingSeconds: 45,
            stepType: "timed",
            roundInfo: "Round 2/4",
            stepDeadline: deadline
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(
            decoded.stepDeadline?.timeIntervalSince1970 ?? 0,
            deadline.timeIntervalSince1970,
            accuracy: 1.0
        )
        XCTAssertEqual(decoded.phase, "running")
        XCTAssertEqual(decoded.stepName, "Burpees")
    }

    func testContentStateRoundTripNilDeadline() throws {
        let state = WorkoutActivityAttributes.ContentState(
            phase: "running",
            stepName: "Push-ups",
            stepIndex: 1,
            stepCount: 5,
            remainingSeconds: 0,
            stepType: "reps",
            roundInfo: nil,
            stepDeadline: nil
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: data)
        XCTAssertNil(decoded.stepDeadline)
    }

    // MARK: - activityStaleDate

    func testStaleDateIsDeadlinePlusBufferForTimedRunningStep() {
        let now = Date()
        let deadline = now.addingTimeInterval(45)
        let state = WorkoutActivityAttributes.ContentState(
            phase: "running",
            stepName: "Burpees",
            stepIndex: 1,
            stepCount: 5,
            remainingSeconds: 45,
            stepType: "timed",
            roundInfo: nil,
            stepDeadline: deadline
        )
        let stale = state.activityStaleDate
        XCTAssertNotNil(stale)
        XCTAssertEqual(
            stale?.timeIntervalSince1970 ?? 0,
            deadline.addingTimeInterval(30).timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testStaleDateIsNilWhenPaused() {
        let state = WorkoutActivityAttributes.ContentState(
            phase: "paused",
            stepName: "Burpees",
            stepIndex: 1,
            stepCount: 5,
            remainingSeconds: 30,
            stepType: "timed",
            roundInfo: nil,
            stepDeadline: Date().addingTimeInterval(30)
        )
        XCTAssertNil(state.activityStaleDate)
    }

    func testStaleDateIsNilWhenNoDeadlineSet() {
        let state = WorkoutActivityAttributes.ContentState(
            phase: "running",
            stepName: "Burpees",
            stepIndex: 1,
            stepCount: 5,
            remainingSeconds: 30,
            stepType: "timed",
            roundInfo: nil,
            stepDeadline: nil
        )
        XCTAssertNil(state.activityStaleDate)
    }

    func testStaleDateIsNilForRepsStep() {
        let state = WorkoutActivityAttributes.ContentState(
            phase: "running",
            stepName: "Push-ups",
            stepIndex: 1,
            stepCount: 5,
            remainingSeconds: 0,
            stepType: "reps",
            roundInfo: nil,
            stepDeadline: nil
        )
        XCTAssertNil(state.activityStaleDate)
    }

    // MARK: - isTimedStep / isPaused regression guard

    func testIsTimedStep() {
        let timed = makeState(stepType: "timed")
        let reps = makeState(stepType: "reps")
        XCTAssertTrue(timed.isTimedStep)
        XCTAssertFalse(reps.isTimedStep)
    }

    func testIsPaused() {
        let paused = makeState(phase: "paused")
        let running = makeState(phase: "running")
        XCTAssertTrue(paused.isPaused)
        XCTAssertFalse(running.isPaused)
    }

    func testFormattedTimeMidWorkout() {
        let state = makeState(remainingSeconds: 90)
        XCTAssertEqual(state.formattedTime, "1:30")
    }

    func testFormattedTimeZero() {
        let state = makeState(remainingSeconds: 0)
        XCTAssertEqual(state.formattedTime, "0:00")
    }

    // MARK: - Helpers

    private func makeState(
        phase: String = "running",
        stepType: String = "timed",
        remainingSeconds: Int = 30
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phase: phase,
            stepName: "Test Step",
            stepIndex: 1,
            stepCount: 5,
            remainingSeconds: remainingSeconds,
            stepType: stepType,
            roundInfo: nil,
            stepDeadline: nil
        )
    }
}
