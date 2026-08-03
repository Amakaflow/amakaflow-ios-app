//
//  OnYourWatchesViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2375: overview snapshot math + Garmin status mapping.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class OnYourWatchesViewModelTests: XCTestCase {
    func testLibrarySummaryHidesUnpairedSides() async {
        let scheduler = MockWorkoutKitScheduler()
        scheduler.rows = [
            WorkoutScheduleRow(
                id: WorkoutScheduleRowID(planID: "a", date: DateComponents(year: 2026, month: 8, day: 4, hour: 6)),
                title: "Chest",
                dateComponents: DateComponents(year: 2026, month: 8, day: 4, hour: 6),
                scheduledAt: Date(timeIntervalSince1970: 1_775_000_000),
                isComplete: false
            )
        ]
        let queue = InMemoryGarminWatchQueueStore()
        queue.recordPush(workoutID: "w1", title: "Hyrox")

        let vm = OnYourWatchesViewModel(
            scheduler: scheduler,
            pairingReader: FixedAppleWatchPairingReader(.confirmedPaired),
            garminPairing: { true },
            queueStore: queue,
            statusFetcher: { _ in
                Components.Schemas.WatchDeliveryStatus(
                    state: .confirmedOnDevice,
                    subtitle: "Downloaded",
                    title: "On watch"
                )
            }
        )
        await vm.refresh()
        XCTAssertTrue(vm.snapshot.showsApple)
        XCTAssertTrue(vm.snapshot.showsGarmin)
        XCTAssertEqual(vm.snapshot.appleScheduledCount, 1)
        XCTAssertEqual(vm.snapshot.garminOnWatch, 1)
        XCTAssertTrue(vm.snapshot.librarySummaryLine.contains("APPLE"))
        XCTAssertTrue(vm.snapshot.librarySummaryLine.contains("GARMIN"))
    }

    func testGarminStateMapping() {
        XCTAssertEqual(GarminQueueItemState.from(delivery: .confirmedOnDevice), .onWatch)
        XCTAssertEqual(GarminQueueItemState.from(delivery: .fetchedByWidget), .onWatch)
        XCTAssertEqual(GarminQueueItemState.from(delivery: .pushed), .waiting)
        XCTAssertEqual(GarminQueueItemState.from(delivery: .generated), .waiting)
        XCTAssertEqual(GarminQueueItemState.from(delivery: .failed), .failed)
    }
}

private struct FixedAppleWatchPairingReader: AppleWatchPairingReading {
    let value: AppleWatchPairingRead
    init(_ value: AppleWatchPairingRead) { self.value = value }
    func pairingReadForCopy() -> AppleWatchPairingRead { value }
}

private final class InMemoryGarminWatchQueueStore: GarminWatchQueueStoring, @unchecked Sendable {
    private var items: [GarminWatchQueueEntry] = []
    func load() -> [GarminWatchQueueEntry] { items }
    func recordPush(workoutID: String, title: String) {
        items.removeAll { $0.workoutID == workoutID }
        items.insert(GarminWatchQueueEntry(workoutID: workoutID, title: title, updatedAt: Date()), at: 0)
    }
    func remove(workoutID: String) { items.removeAll { $0.workoutID == workoutID } }
    func clear() { items = [] }
}
