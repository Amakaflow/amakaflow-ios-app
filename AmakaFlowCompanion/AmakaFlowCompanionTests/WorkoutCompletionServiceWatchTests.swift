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

    func testWatchCompletionUsesSummaryWorkoutNameWhenOverrideMissing() async throws {
        let summary = StandaloneWorkoutSummary(
            workoutId: "watch-workout-1",
            workoutName: "Watch Strength Session",
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 1_600),
            durationSeconds: 600,
            totalCalories: 42,
            averageHeartRate: 120,
            completedSteps: 4,
            totalSteps: 4
        )

        let request = WorkoutCompletionService.makeWatchCompletionRequestForTesting(summary: summary)

        XCTAssertEqual(request.workoutId, "watch-workout-1")
        XCTAssertEqual(request.workoutName, "Watch Strength Session")
        XCTAssertEqual(request.source, "apple_watch")
        XCTAssertEqual(request.deviceInfo.platform, "watchos")
        XCTAssertEqual(request.healthMetrics.avgHeartRate, 120)
        XCTAssertEqual(request.healthMetrics.activeCalories, 42)
    }
}
