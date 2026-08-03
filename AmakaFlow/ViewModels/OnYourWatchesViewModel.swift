//
//  OnYourWatchesViewModel.swift
//  AmakaFlow
//
//  AMA-2375: overview counts for Library door + On your watches screen.
//

import Combine
import Foundation

@MainActor
final class OnYourWatchesViewModel: ObservableObject {
    @Published private(set) var snapshot: OnYourWatchesSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    private let scheduler: (any WorkoutKitScheduleManaging)?
    private let pairingReader: any AppleWatchPairingReading
    private let garminPairing: () -> Bool
    private let queueStore: any GarminWatchQueueStoring
    private let statusFetcher: (String) async throws -> Components.Schemas.WatchDeliveryStatus
    private let calendar: Calendar

    init(
        scheduler: (any WorkoutKitScheduleManaging)? = nil,
        pairingReader: (any AppleWatchPairingReading)? = nil,
        garminPairing: (() -> Bool)? = nil,
        queueStore: (any GarminWatchQueueStoring)? = nil,
        statusFetcher: ((String) async throws -> Components.Schemas.WatchDeliveryStatus)? = nil,
        calendar: Calendar = .current
    ) {
        self.scheduler = scheduler ?? Self.defaultScheduler()
        self.pairingReader = pairingReader ?? LiveAppleWatchPairingReader()
        self.garminPairing = garminPairing ?? { GarminCIQPairingStore.shared.hasPairedGarmin }
        self.queueStore = queueStore ?? GarminWatchQueueStore.shared
        self.statusFetcher = statusFetcher ?? { try await APIService.shared.watchDeliveryStatus(workoutId: $0) }
        self.calendar = calendar
    }

    private static func defaultScheduler() -> (any WorkoutKitScheduleManaging)? {
        if #available(iOS 18.0, *) {
            return LiveWorkoutKitScheduler()
        }
        return nil
    }

    func refresh() async {
        guard !isLoading else { return }

        if OnYourWatchesDemoSupport.isEnabled {
            OnYourWatchesDemoSupport.seedGarminQueueIfNeeded(store: queueStore)
            snapshot = OnYourWatchesDemoSupport.snapshot
            statusMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        var next = OnYourWatchesSnapshot.empty
        next.showsGarmin = garminPairing()
        next.showsApple = pairingReader.pairingReadForCopy() != .confirmedUnpaired && scheduler != nil

        let appleError = await Self.fillApple(into: &next, scheduler: scheduler, calendar: calendar)
        await Self.fillGarmin(
            into: &next,
            queueStore: queueStore,
            statusFetcher: statusFetcher
        )
        snapshot = next
        statusMessage = appleError
    }

    private static func fillApple(
        into next: inout OnYourWatchesSnapshot,
        scheduler: (any WorkoutKitScheduleManaging)?,
        calendar: Calendar
    ) async -> String? {
        guard next.showsApple, let scheduler else { return nil }
        next.appleMaxAllowed = scheduler.maxAllowedCount
        let auth = await scheduler.authorizationState
        guard auth != .denied else { return nil }
        do {
            let rows = try await scheduler.fetchScheduledRows()
            let incomplete = rows.filter { !$0.isComplete }
            next.appleScheduledCount = incomplete.count
            next.appleNextLabel = nextLabel(from: incomplete, calendar: calendar)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func fillGarmin(
        into next: inout OnYourWatchesSnapshot,
        queueStore: any GarminWatchQueueStoring,
        statusFetcher: (String) async throws -> Components.Schemas.WatchDeliveryStatus
    ) async {
        guard next.showsGarmin else { return }
        var onWatch = 0
        var waiting = 0
        var failed = 0
        for entry in queueStore.load() {
            do {
                let status = try await statusFetcher(entry.workoutID)
                switch GarminQueueItemState.from(delivery: status.state) {
                case .onWatch: onWatch += 1
                case .waiting, .none: waiting += 1
                case .failed: failed += 1
                }
            } catch {
                waiting += 1
            }
        }
        next.garminOnWatch = onWatch
        next.garminWaiting = waiting
        next.garminFailed = failed
    }

    private static func nextLabel(from rows: [WorkoutScheduleRow], calendar: Calendar) -> String? {
        let upcoming = rows
            .compactMap(\.scheduledAt)
            .filter { $0 >= calendar.startOfDay(for: Date()) }
            .sorted()
        guard let next = upcoming.first else { return nil }
        if calendar.isDateInToday(next) { return "TODAY" }
        if calendar.isDateInTomorrow(next) { return "TOMORROW" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: next).uppercased()
    }
}
