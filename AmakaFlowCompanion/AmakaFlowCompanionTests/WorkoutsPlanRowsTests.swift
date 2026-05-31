//
//  WorkoutsPlanRowsTests.swift
//  AmakaFlowCompanionTests
//
//  Tests the pure row-state helpers used by WorkoutsView so empty rows stay
//  honest and non-interactive.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutsPlanRowsTests: XCTestCase {

    func testIsWeekEmptyReturnsTrueWhenEveryRowHasNoWorkout() {
        let rows = [
            makeEmptyRow(id: "empty-mon"),
            makeEmptyRow(id: "empty-tue"),
            makeEmptyRow(id: "empty-wed")
        ]

        XCTAssertTrue(WorkoutsPlanRows.isWeekEmpty(rows))
    }

    func testIsWeekEmptyReturnsFalseWhenAnyRowHasWorkout() {
        let rows = [
            makeEmptyRow(id: "empty-mon"),
            makeWorkoutRow(id: "workout-tue"),
            makeEmptyRow(id: "empty-wed")
        ]

        XCTAssertFalse(WorkoutsPlanRows.isWeekEmpty(rows))
    }

    func testIsInteractiveFollowsWorkoutPresence() {
        XCTAssertFalse(WorkoutsPlanRows.isInteractive(makeEmptyRow(id: "empty")))
        XCTAssertTrue(WorkoutsPlanRows.isInteractive(makeWorkoutRow(id: "workout")))
    }

    private func makeEmptyRow(id: String) -> PlanRow {
        PlanRow(
            id: id,
            day: "Mon",
            date: "1",
            type: "—",
            title: "No session",
            duration: "—",
            zone: "—",
            source: nil,
            icon: "minus.circle",
            done: false,
            today: false,
            rest: true,
            workout: nil
        )
    }

    private func makeWorkoutRow(id: String) -> PlanRow {
        let workout = TestFixtures.workout(
            id: id,
            name: "Tempo Run",
            sport: .running,
            duration: 1_800,
            source: .coach
        )

        return PlanRow(
            id: id,
            day: "Tue",
            date: "2",
            type: workout.sport.rawValue.capitalized,
            title: workout.name,
            duration: workout.formattedDuration,
            zone: "Z2",
            source: workout.source.rawValue,
            icon: "figure.run",
            done: false,
            today: false,
            rest: false,
            workout: workout
        )
    }
}
