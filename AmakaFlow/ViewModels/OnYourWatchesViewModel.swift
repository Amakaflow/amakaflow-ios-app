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
        if OnYourWatchesDemoSupport.isEnabled {
            OnYourWatchesDemoSupport.seedGarminQueueIfNeeded(store: queueStore)
            snapshot = OnYourWatchesDemoSupport.snapshot
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        let applePaired = pairingReader.pairingReadForCopy() != .confirmedUnpaired
        let garminPaired = garminPairing()
        var next = OnYourWatchesSnapshot.empty
        next.showsGarmin = garminPaired
        next.showsApple = applePaired && scheduler != nil

        if next.showsApple, let scheduler {
            next.appleMaxAllowed = scheduler.maxAllowedCount
            let auth = await scheduler.authorizationState
            if auth != .denied {
                do {
                    let rows = try await scheduler.fetchScheduledRows()
                    let incomplete = rows.filter { !$0.isComplete }
                    next.appleScheduledCount = incomplete.count
                    next.appleNextLabel = Self.nextLabel(from: incomplete, calendar: calendar)
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
        }

        if next.showsGarmin {
            let entries = queueStore.load()
            var onWatch = 0
            var waiting = 0
            var failed = 0
            for entry in entries {
                do {
                    let status = try await statusFetcher(entry.workoutID)
                    switch GarminQueueItemState.from(delivery: status.state) {
                    case .onWatch: onWatch += 1
                    case .waiting: waiting += 1
                    case .failed: failed += 1
                    case .none: waiting += 1
                    }
                } catch {
                    // Keep the local entry visible as waiting if status can't be fetched.
                    waiting += 1
                }
            }
            next.garminOnWatch = onWatch
            next.garminWaiting = waiting
            next.garminFailed = failed
        }

        snapshot = next
        if statusMessage == nil {
            statusMessage = nil
        }
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
