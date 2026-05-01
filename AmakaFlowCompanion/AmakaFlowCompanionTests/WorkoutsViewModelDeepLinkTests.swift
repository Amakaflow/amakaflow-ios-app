//
//  WorkoutsViewModelDeepLinkTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1640: Tests for the deep-link payload helpers added to
//  WorkoutsViewModel — preselectCalendarDate(_:) and selectWorkout(byId:).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutsViewModelDeepLinkTests: XCTestCase {

    var viewModel: WorkoutsViewModel!

    override func setUp() async throws {
        viewModel = WorkoutsViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
    }

    // MARK: - preselectCalendarDate

    func test_preselectCalendarDate_validISO_setsPendingDate() {
        viewModel.preselectCalendarDate("2026-05-10")
        XCTAssertNotNil(viewModel.pendingCalendarDate)

        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents([.year, .month, .day],
                                            from: viewModel.pendingCalendarDate ?? Date(),
                                            to: viewModel.pendingCalendarDate ?? Date())
        // Verify by checking absolute year/month/day in UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = utc.dateComponents([.year, .month, .day], from: viewModel.pendingCalendarDate!)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 5)
        XCTAssertEqual(parts.day, 10)
        _ = comps
    }

    func test_preselectCalendarDate_invalidString_isNoOp() {
        viewModel.preselectCalendarDate("not-a-date")
        XCTAssertNil(viewModel.pendingCalendarDate,
                     "Invalid input must not corrupt prior state")
    }

    func test_preselectCalendarDate_emptyString_isNoOp() {
        viewModel.preselectCalendarDate("")
        XCTAssertNil(viewModel.pendingCalendarDate)
    }

    func test_preselectCalendarDate_overwritesPriorValue() {
        viewModel.preselectCalendarDate("2026-05-10")
        let first = viewModel.pendingCalendarDate
        viewModel.preselectCalendarDate("2026-06-15")
        XCTAssertNotNil(viewModel.pendingCalendarDate)
        XCTAssertNotEqual(viewModel.pendingCalendarDate, first)
    }

    // MARK: - selectWorkout(byId:)

    func test_selectWorkout_idInIncoming_setsPending() {
        let workout = Self.makeWorkout(id: "incoming-1", name: "Test Run")
        viewModel.incomingWorkouts = [workout]

        viewModel.selectWorkout(byId: "incoming-1")
        XCTAssertEqual(viewModel.pendingDeepLinkWorkoutId, "incoming-1")
    }

    func test_selectWorkout_idInUpcoming_setsPending() {
        let workout = Self.makeWorkout(id: "upcoming-1", name: "Test Strength")
        let scheduled = ScheduledWorkout(workout: workout,
                                         scheduledDate: Date(),
                                         scheduledTime: nil,
                                         syncedToApple: false)
        viewModel.upcomingWorkouts = [scheduled]

        viewModel.selectWorkout(byId: "upcoming-1")
        XCTAssertEqual(viewModel.pendingDeepLinkWorkoutId, "upcoming-1")
    }

    func test_selectWorkout_unknownId_isNoOp() {
        viewModel.incomingWorkouts = [Self.makeWorkout(id: "known", name: "Known")]
        viewModel.selectWorkout(byId: "ghost")
        XCTAssertNil(viewModel.pendingDeepLinkWorkoutId,
                     "Unknown id must not set pending — caller can't present a sheet for a workout we don't have.")
    }

    func test_selectWorkout_emptyState_isNoOp() {
        viewModel.selectWorkout(byId: "anything")
        XCTAssertNil(viewModel.pendingDeepLinkWorkoutId)
    }

    // MARK: - Helpers

    private static func makeWorkout(id: String, name: String) -> Workout {
        Workout(
            id: id,
            name: name,
            sport: .strength,
            duration: 600,
            intervals: [.time(seconds: 600, target: nil)],
            description: nil,
            source: .ai
        )
    }
}
