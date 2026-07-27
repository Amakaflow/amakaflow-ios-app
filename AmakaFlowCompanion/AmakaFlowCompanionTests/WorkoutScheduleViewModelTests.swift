//
//  WorkoutScheduleViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2330: Identity + auth-shape tests for WorkoutKitScheduleManaging seam.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutScheduleRowIDTests: XCTestCase {
    func testCanonicalKeyStableAcrossEqualComponents() {
        var a = DateComponents()
        a.year = 2026; a.month = 7; a.day = 27; a.hour = 10; a.minute = 5
        var b = DateComponents()
        b.year = 2026; b.month = 7; b.day = 27; b.hour = 10; b.minute = 5
        XCTAssertEqual(
            WorkoutScheduleRowID(planID: "p1", date: a),
            WorkoutScheduleRowID(planID: "p1", date: b)
        )
    }

    func testCanonicalKeyDiffersWhenMinuteDiffers() {
        var a = DateComponents()
        a.year = 2026; a.month = 7; a.day = 27; a.hour = 10; a.minute = 5
        var b = DateComponents()
        b.year = 2026; b.month = 7; b.day = 27; b.hour = 10; b.minute = 6
        XCTAssertNotEqual(
            WorkoutScheduleRowID(planID: "p1", date: a),
            WorkoutScheduleRowID(planID: "p1", date: b)
        )
    }

    func testOptionalCalendarIncludedOnlyWhenPresent() {
        var withCal = DateComponents()
        withCal.year = 2026; withCal.month = 7; withCal.day = 27
        withCal.calendar = Calendar(identifier: .gregorian)
        var without = DateComponents()
        without.year = 2026; without.month = 7; without.day = 27
        XCTAssertNotEqual(
            WorkoutScheduleRowID.canonicalDateKey(withCal),
            WorkoutScheduleRowID.canonicalDateKey(without)
        )
    }

    func testDifferentPlanIDsProduceDifferentRowIDs() {
        var a = DateComponents()
        a.year = 2026; a.month = 7; a.day = 27; a.hour = 10; a.minute = 5
        XCTAssertNotEqual(
            WorkoutScheduleRowID(planID: "p1", date: a),
            WorkoutScheduleRowID(planID: "p2", date: a)
        )
    }

    func testOptionalTimeZoneIncludedOnlyWhenPresent() {
        var withTZ = DateComponents()
        withTZ.year = 2026; withTZ.month = 7; withTZ.day = 27
        withTZ.timeZone = TimeZone(identifier: "America/Chicago")
        var without = DateComponents()
        without.year = 2026; without.month = 7; without.day = 27
        XCTAssertNotEqual(
            WorkoutScheduleRowID.canonicalDateKey(withTZ),
            WorkoutScheduleRowID.canonicalDateKey(without)
        )
    }

    func testCanonicalKeyDiffersWhenSecondOrNanosecondDiffers() {
        var a = DateComponents()
        a.year = 2026; a.month = 7; a.day = 27; a.hour = 10; a.minute = 5; a.second = 0
        var b = DateComponents()
        b.year = 2026; b.month = 7; b.day = 27; b.hour = 10; b.minute = 5; b.second = 30
        XCTAssertNotEqual(
            WorkoutScheduleRowID.canonicalDateKey(a),
            WorkoutScheduleRowID.canonicalDateKey(b)
        )
    }

    func testRowIDIsHashable() {
        var a = DateComponents()
        a.year = 2026; a.month = 7; a.day = 27; a.hour = 10; a.minute = 5
        let id = WorkoutScheduleRowID(planID: "p1", date: a)
        var set: Set<WorkoutScheduleRowID> = []
        set.insert(id)
        XCTAssertTrue(set.contains(id))
    }
}

final class MockWorkoutKitSchedulerTests: XCTestCase {
    private func makeRow(planID: String, minute: Int, isComplete: Bool = false) -> WorkoutScheduleRow {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 27
        components.hour = 9; components.minute = minute
        return WorkoutScheduleRow(
            id: WorkoutScheduleRowID(planID: planID, date: components),
            title: "Workout \(planID)",
            dateComponents: components,
            scheduledAt: nil,
            isComplete: isComplete
        )
    }

    func testFetchScheduledRowsReturnsConfiguredRows() async throws {
        let mock = MockWorkoutKitScheduler()
        let row = makeRow(planID: "p1", minute: 0)
        mock.rows = [row]

        let fetched = try await mock.fetchScheduledRows()

        XCTAssertEqual(fetched, [row])
    }

    func testFetchScheduledRowsThrowsWhenFetchErrorConfigured() async {
        let mock = MockWorkoutKitScheduler()
        struct DummyError: Error {}
        mock.fetchError = DummyError()

        do {
            _ = try await mock.fetchScheduledRows()
            XCTFail("Expected fetchScheduledRows to throw")
        } catch {
            // expected
        }
    }

    func testRemoveDeletesMatchingRowAndRecordsCall() async {
        let mock = MockWorkoutKitScheduler()
        let row = makeRow(planID: "p1", minute: 0)
        mock.rows = [row]

        await mock.remove(row: row)

        XCTAssertEqual(mock.removeCallRows, [row])
        XCTAssertTrue(mock.rows.isEmpty)
    }

    func testRemoveIsNoOpWhenIDInNoopSet() async {
        let mock = MockWorkoutKitScheduler()
        let row = makeRow(planID: "p1", minute: 0)
        mock.rows = [row]
        mock.noopRemoveIDs = [row.id]

        await mock.remove(row: row)

        XCTAssertEqual(mock.removeCallRows, [row])
        XCTAssertEqual(mock.rows, [row])
    }

    func testRemoveAllClearsRowsAndIncrementsCallCount() async {
        let mock = MockWorkoutKitScheduler()
        mock.rows = [makeRow(planID: "p1", minute: 0), makeRow(planID: "p2", minute: 1)]

        await mock.removeAll()

        XCTAssertTrue(mock.rows.isEmpty)
        XCTAssertEqual(mock.removeAllCallCount, 1)
    }

    func testAuthorizationStateReflectsConfiguredValue() async {
        let mock = MockWorkoutKitScheduler()
        mock.authState = .denied

        let state = await mock.authorizationState

        XCTAssertEqual(state, .denied)
    }

    func testRequestAuthorizationReturnsConfiguredStateAndCountsCalls() async {
        let mock = MockWorkoutKitScheduler()
        mock.authState = .authorized

        let result = await mock.requestAuthorization()

        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(mock.requestAuthorizationCallCount, 1)
    }

    func testMaxAllowedCountDefaultsTo15ForMockOnly() {
        let mock = MockWorkoutKitScheduler()
        XCTAssertEqual(mock.maxAllowedCount, 15)
    }
}
