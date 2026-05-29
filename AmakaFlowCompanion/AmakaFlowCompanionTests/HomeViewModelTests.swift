//
//  HomeViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1993: Home first-launch empty state derives from existing workout data.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class HomeViewModelTests: XCTestCase {
    private var calendar: Calendar!
    private let fixedNow = Date(timeIntervalSince1970: 1_779_984_000) // 2026-05-28T16:00:00Z
    private var viewModel: HomeViewModel!

    override func setUp() async throws {
        try await super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = cal
        viewModel = HomeViewModel(calendar: cal, now: { self.fixedNow })
    }

    override func tearDown() async throws {
        viewModel = nil
        calendar = nil
        try await super.tearDown()
    }

    func testLoadingStateWhileWorkoutPlanLoadInFlight() {
        viewModel.update(
            isLoading: true,
            incomingWorkouts: [],
            upcomingWorkouts: [],
            activeBlock: nil
        )

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertNil(viewModel.ctaError)
    }

    func testInitialUnloadedSnapshotStaysLoadingInsteadOfFakeEmpty() {
        viewModel.update(
            isLoading: false,
            hasLoadedWorkouts: false,
            incomingWorkouts: [],
            upcomingWorkouts: [],
            activeBlock: nil
        )

        XCTAssertEqual(viewModel.state, .loading)
    }

    func testEmptyStateWhenNoActivePlanAndNoWorkoutToday() {
        viewModel.update(
            isLoading: false,
            incomingWorkouts: [],
            upcomingWorkouts: [],
            activeBlock: nil
        )

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.ctaError)
    }

    func testContentStateWhenThereIsWorkoutToday() {
        viewModel.update(
            isLoading: false,
            incomingWorkouts: [workout(id: "today-incoming")],
            upcomingWorkouts: [],
            activeBlock: nil
        )

        XCTAssertEqual(viewModel.state, .content)
    }

    func testContentStateWinsWhileBackgroundLoadIsInFlight() {
        viewModel.update(
            isLoading: true,
            hasLoadedWorkouts: true,
            incomingWorkouts: [workout(id: "cached-today")],
            upcomingWorkouts: [],
            activeBlock: nil
        )

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertNil(viewModel.ctaError)
    }

    func testContentStateWinsOverRefreshErrorWhenLocalDataExists() {
        viewModel.update(
            isLoading: false,
            incomingWorkouts: [workout(id: "cached-today")],
            upcomingWorkouts: [],
            activeBlock: nil,
            loadError: .network(code: .timedOut)
        )

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertNil(viewModel.ctaError)
    }

    func testErrorStateWhenRefreshFailsWithoutRenderableContent() {
        viewModel.update(
            isLoading: false,
            incomingWorkouts: [],
            upcomingWorkouts: [],
            activeBlock: nil,
            loadError: .network(code: .timedOut)
        )

        guard case .error(let ctaError) = viewModel.state else {
            XCTFail("Expected error state, got \(viewModel.state)")
            return
        }

        guard case .network(let code, _) = ctaError else {
            XCTFail("Expected network CTAError, got \(ctaError)")
            return
        }
        XCTAssertEqual(code, .timedOut)
        viewModel.update(isLoading: false, incomingWorkouts: [], upcomingWorkouts: [], activeBlock: nil)
    }

    func testContentStateWhenThereIsActivePlanEvenWithoutTodayWorkout() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: fixedNow)!
        let scheduled = ScheduledWorkout(
            workout: workout(id: "planned-tomorrow"),
            scheduledDate: tomorrow,
            scheduledTime: "09:00"
        )

        viewModel.update(
            isLoading: false,
            incomingWorkouts: [],
            upcomingWorkouts: [scheduled],
            activeBlock: nil
        )

        XCTAssertEqual(viewModel.state, .content)
    }

    func testContentStateWhenActiveBlockExists() {
        let block = TrainingBlock(
            name: "Build",
            index: 1,
            total: 4,
            scheduledWorkouts: []
        )

        viewModel.update(
            isLoading: false,
            incomingWorkouts: [],
            upcomingWorkouts: [],
            activeBlock: block
        )

        XCTAssertEqual(viewModel.state, .content)
    }

    func testLoadErrorMatrixMapsToCTAError() {
        assertLoadFailure(URLError(.notConnectedToInternet), label: "network") { ctaError in
            guard case .network(let code, _) = ctaError else { return false }
            return code == .notConnectedToInternet
        }

        assertLoadFailure(APIError.serverErrorWithBody(503, "{\"detail\":\"planner down\"}"), label: "http") { ctaError in
            guard case .http(let status, let body, _) = ctaError else { return false }
            return status == 503 && body?.contains("planner down") == true
        }

        assertLoadFailure(APIError.decodingError(NSError(domain: "HomeViewModelTests", code: 1)), label: "decoding") { ctaError in
            guard case .decoding = ctaError else { return false }
            return true
        }

        assertLoadFailure(APIError.unauthorized, label: "unauthenticated") { ctaError in
            guard case .unauthenticated = ctaError else { return false }
            return true
        }

        assertLoadFailure(
            APIError.serverErrorWithBody(200, "{\"success\":false,\"message\":\"no plan\",\"error_code\":\"NO_PLAN\"}"),
            label: "lying-success"
        ) { ctaError in
            guard case .lyingSuccess(let message, let code, _) = ctaError else { return false }
            return message == "no plan" && code == "NO_PLAN"
        }
    }

    func testEmptyTransitionsToContentWhenPlanOrTodayWorkoutAppears() {
        viewModel.update(
            isLoading: false,
            incomingWorkouts: [],
            upcomingWorkouts: [],
            activeBlock: nil
        )
        XCTAssertEqual(viewModel.state, .empty)

        viewModel.update(
            isLoading: false,
            incomingWorkouts: [workout(id: "accepted-suggestion")],
            upcomingWorkouts: [],
            activeBlock: nil
        )

        XCTAssertEqual(viewModel.state, .content)
    }

    private func assertLoadFailure(_ error: Error, label: String, matcher: (CTAError) -> Bool) {
        viewModel.applyLoadFailure(error)
        defer {
            viewModel.update(
                isLoading: false,
                incomingWorkouts: [],
                upcomingWorkouts: [],
                activeBlock: nil
            )
        }

        guard case .error(let ctaError) = viewModel.state else {
            XCTFail("Expected error state for \(label), got \(viewModel.state)")
            return
        }

        XCTAssertTrue(matcher(ctaError), "Wrong CTAError mapping for \(label): \(ctaError)")
        XCTAssertTrue(viewModel.ctaError.map(matcher) ?? false, "Wrong published CTAError for \(label): \(String(describing: viewModel.ctaError))")
    }

    private func workout(id: String) -> Workout {
        TestFixtures.workout(id: id, name: "Workout \(id)", sport: .strength)
    }
}
