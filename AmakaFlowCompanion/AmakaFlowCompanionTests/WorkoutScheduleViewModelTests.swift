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
        var c = b
        c.nanosecond = 1
        XCTAssertNotEqual(
            WorkoutScheduleRowID.canonicalDateKey(b),
            WorkoutScheduleRowID.canonicalDateKey(c)
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

@MainActor
final class WorkoutScheduleViewModelTests: XCTestCase {
    private func row(
        id: String,
        title: String,
        minutesAgo: Int,
        complete: Bool = false
    ) -> WorkoutScheduleRow {
        let date = Calendar.current.date(byAdding: .minute, value: -minutesAgo, to: Date())!
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        return WorkoutScheduleRow(
            id: WorkoutScheduleRowID(planID: id, date: comps),
            title: title,
            dateComponents: comps,
            scheduledAt: date,
            isComplete: complete
        )
    }

    func testDeniedAuthShowsBannerNotEmptyState() async {
        let mock = MockWorkoutKitScheduler()
        mock.authState = .denied
        mock.rows = []
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertTrue(vm.authDenied)
        XCTAssertFalse(vm.showEmptyState)
    }

    func testAuthorizedEmptyShowsEmptyState() async {
        let mock = MockWorkoutKitScheduler()
        mock.authState = .authorized
        mock.rows = []
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertFalse(vm.authDenied)
        XCTAssertTrue(vm.showEmptyState)
    }

    func testNotDeterminedRequestsAuthorization() async {
        let mock = MockWorkoutKitScheduler()
        mock.authState = .notDetermined
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertEqual(mock.requestAuthorizationCallCount, 1)
    }

    func testRefreshSortsNewestFirstAndSectionsCompleted() async {
        let mock = MockWorkoutKitScheduler()
        mock.rows = [
            row(id: "old", title: "A", minutesAgo: 120),
            row(id: "new", title: "B", minutesAgo: 5),
            row(id: "done", title: "C", minutesAgo: 1, complete: true)
        ]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertEqual(vm.incompleteRows.map(\.title), ["B", "A"])
        XCTAssertEqual(vm.completedRows.map(\.title), ["C"])
    }

    func testManualRefreshClearsSelectionAndExitsEditing() async {
        let mock = MockWorkoutKitScheduler()
        let r = row(id: "1", title: "Hyrox", minutesAgo: 10)
        mock.rows = [r]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        vm.toggleSelect(r.id)
        await vm.refresh(mode: .manual)
        XCTAssertFalse(vm.isEditing)
        XCTAssertTrue(vm.selectedIDs.isEmpty)
    }

    func testDeleteSelectedPassesExactStoredDateComponents_mockLevel() async {
        // Mock-level passthrough. Live plan+date → remove(_:at:) is code review + dogfood.
        let mock = MockWorkoutKitScheduler()
        let r = row(id: "1", title: "Hyrox", minutesAgo: 3)
        mock.rows = [r]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        vm.toggleSelect(r.id)
        await vm.deleteSelected()
        XCTAssertEqual(mock.removeCallRows.map(\.id), [r.id])
        XCTAssertEqual(mock.removeCallRows.first?.dateComponents, r.dateComponents)
        XCTAssertTrue(vm.incompleteRows.isEmpty)
    }

    func testEmptySelectionDoesNotCallRemove() async {
        let mock = MockWorkoutKitScheduler()
        mock.rows = [row(id: "1", title: "A", minutesAgo: 1)]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        await vm.deleteSelected()
        XCTAssertTrue(mock.removeCallRows.isEmpty)
    }

    func testClearAllCallsRemoveAllOnce() async {
        let mock = MockWorkoutKitScheduler()
        mock.rows = [
            row(id: "1", title: "A", minutesAgo: 1),
            row(id: "2", title: "B", minutesAgo: 2)
        ]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        await vm.clearAll()
        XCTAssertEqual(mock.removeAllCallCount, 1)
    }

    func testSilentNoOpRemoveKeepsStillPresentIDsSelected() async {
        let mock = MockWorkoutKitScheduler()
        let a = row(id: "a", title: "A", minutesAgo: 1)
        let b = row(id: "b", title: "B", minutesAgo: 2)
        let c = row(id: "c", title: "C", minutesAgo: 3)
        mock.rows = [a, b, c]
        mock.noopRemoveIDs = [b.id]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        [a, b, c].forEach { vm.toggleSelect($0.id) }
        await vm.deleteSelected()
        XCTAssertEqual(vm.selectedIDs, [b.id])
        XCTAssertTrue(vm.isEditing)
        XCTAssertTrue(vm.statusMessage?.contains("Removed 2 of 3") == true)
    }

    func testRetryOnlyTargetsIDsStillPresent() async {
        let mock = MockWorkoutKitScheduler()
        let a = row(id: "a", title: "A", minutesAgo: 1)
        let b = row(id: "b", title: "B", minutesAgo: 2)
        mock.rows = [a, b]
        mock.noopRemoveIDs = [b.id]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        vm.toggleSelect(a.id)
        vm.toggleSelect(b.id)
        await vm.deleteSelected()
        mock.noopRemoveIDs = []
        mock.removeCallRows = []
        await vm.deleteSelected()
        XCTAssertEqual(mock.removeCallRows.map(\.id), [b.id])
        XCTAssertTrue(vm.selectedIDs.isEmpty)
    }

    // MARK: - AMA-2330 P1 fixes: re-entrancy (`isMutating`)

    func testIsMutatingIsFalseBeforeAndAfterDeleteSelected() async {
        let mock = MockWorkoutKitScheduler()
        let r = row(id: "1", title: "A", minutesAgo: 1)
        mock.rows = [r]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertFalse(vm.isMutating)
        vm.enterEditing()
        vm.toggleSelect(r.id)
        await vm.deleteSelected()
        XCTAssertFalse(vm.isMutating)
    }

    /// Proves overlapping `deleteSelected()` calls don't double-fire: a gated first
    /// call holds `isMutating`, so a second call made before it finishes is a no-op.
    func testOverlappingDeleteSelectedSecondCallIsGatedByIsMutating() async {
        let mock = MockWorkoutKitScheduler()
        let a = row(id: "a", title: "A", minutesAgo: 1)
        let b = row(id: "b", title: "B", minutesAgo: 2)
        mock.rows = [a, b]
        let gate = RemoveGate()
        mock.removeGate = { await gate.wait() }
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        vm.toggleSelect(a.id)

        async let firstCall: Void = vm.deleteSelected()
        await gate.waitUntilHeld()
        XCTAssertTrue(vm.isMutating, "first call should still be in flight")

        await vm.deleteSelected()
        await gate.release()
        await firstCall

        XCTAssertEqual(mock.removeCallRows.map(\.id), [a.id])
        XCTAssertFalse(vm.isMutating)
    }

    func testOverlappingRefreshAndClearAllSecondCallIsGatedByIsMutating() async {
        let mock = MockWorkoutKitScheduler()
        let a = row(id: "a", title: "A", minutesAgo: 1)
        mock.rows = [a]
        let gate = RemoveGate()
        mock.removeGate = { await gate.wait() }
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        vm.toggleSelect(a.id)

        async let firstDelete: Void = vm.deleteSelected()
        await gate.waitUntilHeld()

        await vm.clearAll()
        await gate.release()
        await firstDelete

        XCTAssertEqual(mock.removeAllCallCount, 0, "clearAll must not run while a delete is in flight")
    }

    // MARK: - AMA-2330 P1 fixes: schedule-cap warning

    func testIsAtScheduleCapTrueWhenRowCountEqualsMax() async {
        let mock = MockWorkoutKitScheduler()
        mock.maxAllowedCount = 2
        mock.rows = [
            row(id: "1", title: "A", minutesAgo: 1),
            row(id: "2", title: "B", minutesAgo: 2, complete: true)
        ]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertTrue(vm.isAtScheduleCap)
    }

    func testIsAtScheduleCapFalseWhenBelowMax() async {
        let mock = MockWorkoutKitScheduler()
        mock.maxAllowedCount = 15
        mock.rows = [row(id: "1", title: "A", minutesAgo: 1)]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertFalse(vm.isAtScheduleCap)
    }

    // MARK: - AMA-2330 P1 fixes: clear-all silent failure

    func testClearAllSurfacesFailureStatusWhenRowsRemain() async {
        let mock = MockWorkoutKitScheduler()
        mock.rows = [row(id: "1", title: "A", minutesAgo: 1)]
        mock.removeAllIsNoOp = true
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        await vm.clearAll()
        XCTAssertFalse(vm.incompleteRows.isEmpty, "sanity: no-op removeAll left the row behind")
        XCTAssertEqual(vm.statusMessage, "Some plans could not be removed — pull to refresh.")
    }

    func testClearAllKeepsSuccessCopyWhenEmptied() async {
        let mock = MockWorkoutKitScheduler()
        mock.rows = [row(id: "1", title: "A", minutesAgo: 1)]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        await vm.clearAll()
        XCTAssertTrue(vm.showEmptyState)
        XCTAssertEqual(vm.statusMessage, "Removed all AmakaFlow plans.")
    }

    func testClearAllPreservesRefreshErrorWhenFetchFailsAfterRemoveAll() async {
        let mock = MockWorkoutKitScheduler()
        mock.rows = [row(id: "1", title: "A", minutesAgo: 1)]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        mock.fetchError = DummyFetchError()
        await vm.clearAll()
        XCTAssertEqual(vm.statusMessage, DummyFetchError().localizedDescription)
        XCTAssertNotEqual(vm.statusMessage, "Some plans could not be removed — pull to refresh.")
    }

    func testRefreshDoesNotTrapOnDuplicateRowIDs() async {
        let mock = MockWorkoutKitScheduler()
        let a = row(id: "dup", title: "First", minutesAgo: 1)
        let b = row(id: "dup", title: "Second", minutesAgo: 1)
        mock.rows = [a, b]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertEqual(vm.incompleteRows.count, 2)
        XCTAssertFalse(vm.authDenied)
    }

    func testSwipeDeleteDoesNotEnterEditingOnSuccess() async {
        let mock = MockWorkoutKitScheduler()
        let a = row(id: "a", title: "A", minutesAgo: 1)
        mock.rows = [a]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertFalse(vm.isEditing)
        await vm.delete(row: a)
        XCTAssertFalse(vm.isEditing)
        XCTAssertTrue(vm.selectedIDs.isEmpty)
        XCTAssertTrue(vm.incompleteRows.isEmpty)
    }

    // MARK: - AMA-2330 P1 fixes: canRetry (not string-sniffed)

    func testCanRetryTrueOnlyWhenSomeRowsStillPresentAfterMutation() async {
        let mock = MockWorkoutKitScheduler()
        let a = row(id: "a", title: "A", minutesAgo: 1)
        let b = row(id: "b", title: "B", minutesAgo: 2)
        mock.rows = [a, b]
        mock.noopRemoveIDs = [b.id]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        vm.toggleSelect(a.id)
        vm.toggleSelect(b.id)
        await vm.deleteSelected()
        XCTAssertTrue(vm.canRetry)
    }

    func testCanRetryFalseAfterFullSuccess() async {
        let mock = MockWorkoutKitScheduler()
        let a = row(id: "a", title: "A", minutesAgo: 1)
        mock.rows = [a]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        vm.toggleSelect(a.id)
        await vm.deleteSelected()
        XCTAssertFalse(vm.canRetry)
    }

    func testCanRetryFalseOnManualRefresh() async {
        let mock = MockWorkoutKitScheduler()
        let a = row(id: "a", title: "A", minutesAgo: 1)
        let b = row(id: "b", title: "B", minutesAgo: 2)
        mock.rows = [a, b]
        mock.noopRemoveIDs = [b.id]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        vm.toggleSelect(a.id)
        vm.toggleSelect(b.id)
        await vm.deleteSelected()
        XCTAssertTrue(vm.canRetry)
        await vm.refresh(mode: .manual)
        XCTAssertFalse(vm.canRetry)
    }

    // MARK: - AMA-2330 P1 fixes: stale rowsByID on authDenied

    func testAuthDeniedClearsRowsByIDPreventingGhostDelete() async {
        let mock = MockWorkoutKitScheduler()
        let stale = row(id: "stale", title: "Stale", minutesAgo: 1)
        mock.rows = [stale]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertFalse(vm.incompleteRows.isEmpty)

        mock.authState = .denied
        await vm.refresh(mode: .manual)
        XCTAssertTrue(vm.authDenied)

        // Simulate a stale reference to the previously-fetched row surviving in the
        // UI (e.g. a delayed swipe action) — with `rowsByID` cleared, this must be
        // a no-op rather than resurrecting a call against a no-longer-authorized session.
        await vm.delete(row: stale)
        XCTAssertTrue(mock.removeCallRows.isEmpty)
    }
}

/// Deterministic hold/release for concurrency-gate tests (no sleep timing).
private actor RemoveGate {
    private var isHeld = false
    private var holdContinuations: [CheckedContinuation<Void, Never>] = []
    private var observerContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        isHeld = true
        let observers = observerContinuations
        observerContinuations = []
        for continuation in observers {
            continuation.resume()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            holdContinuations.append(continuation)
        }
        isHeld = false
    }

    func waitUntilHeld() async {
        if isHeld { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            observerContinuations.append(continuation)
        }
    }

    func release() {
        let holds = holdContinuations
        holdContinuations = []
        for continuation in holds {
            continuation.resume()
        }
    }
}

private struct DummyFetchError: Error, LocalizedError {
    var errorDescription: String? { "fetch blew up" }
}
