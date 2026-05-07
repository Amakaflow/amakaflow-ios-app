//
//  WorkoutCompletionServiceWatchTests.swift
//  AmakaFlowCompanionTests
//
//  Regression coverage for AMA-1751 Watch completion payloads.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutCompletionServiceWatchTests: XCTestCase {

    func testWatchCompletionUsesSummaryWorkoutNameWhenOverrideMissing() {
        let summary = makeSummary(
            workoutId: "watch-workout-1",
            workoutName: "Watch Strength Session",
            totalCalories: 42,
            averageHeartRate: 120
        )

        let request = WorkoutCompletionService.makeWatchCompletionRequestForTesting(summary: summary)

        XCTAssertEqual(request.workoutId, "watch-workout-1")
        XCTAssertEqual(request.workoutName, "Watch Strength Session")
        XCTAssertEqual(request.source, "apple_watch")
        XCTAssertEqual(request.deviceInfo.platform, "watchos")
        XCTAssertEqual(request.healthMetrics.avgHeartRate, 120)
        XCTAssertEqual(request.healthMetrics.activeCalories, 42)
        XCTAssertNil(request.isSimulated)
        XCTAssertNil(request.heartRateSamples)
        XCTAssertNil(request.setLogs)
        XCTAssertNil(request.executionLog)
    }

    func testWatchCompletionUsesOverrideWorkoutNameWhenProvided() {
        let summary = makeSummary(
            workoutId: "watch-workout-2",
            workoutName: "Original Watch Name",
            start: 2_000,
            totalCalories: 55,
            averageHeartRate: 125,
            completedSteps: 5,
            totalSteps: 5
        )

        let request = WorkoutCompletionService.makeWatchCompletionRequestForTesting(
            summary: summary,
            workoutName: "Override Name"
        )

        XCTAssertEqual(request.workoutName, "Override Name")
    }

    func testWatchCompletionPassesWorkoutStructureThrough() {
        let summary = makeSummary(
            workoutId: "watch-workout-3",
            workoutName: "Structured Run",
            start: 3_000,
            totalCalories: 60,
            averageHeartRate: 130,
            completedSteps: 3,
            totalSteps: 3
        )
        let structure: [WorkoutInterval] = [.warmup(seconds: 60, target: "Easy")]

        let request = WorkoutCompletionService.makeWatchCompletionRequestForTesting(
            summary: summary,
            workoutStructure: structure
        )

        XCTAssertEqual(request.workoutStructure, structure)
    }

    private func makeSummary(
        workoutId: String,
        workoutName: String,
        start: TimeInterval = 1_000,
        durationSeconds: Int = 600,
        totalCalories: Double,
        averageHeartRate: Double?,
        completedSteps: Int = 4,
        totalSteps: Int = 4
    ) -> StandaloneWorkoutSummary {
        StandaloneWorkoutSummary(
            workoutId: workoutId,
            workoutName: workoutName,
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: start + TimeInterval(durationSeconds)),
            durationSeconds: durationSeconds,
            totalCalories: totalCalories,
            averageHeartRate: averageHeartRate,
            completedSteps: completedSteps,
            totalSteps: totalSteps
        )
    }
}
