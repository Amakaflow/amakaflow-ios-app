//
//  OnYourWatchesModels.swift
//  AmakaFlow
//
//  AMA-2375: shared models for the watch workout manager.
//

import Foundation

/// Library pick-mode target after a watch-manager CTA.
enum WatchLibraryPickTarget: String, Hashable, Sendable {
    case appleSchedule
    case garminPush
}

/// High-level Garmin queue row state for the Notion-style list.
enum GarminQueueItemState: String, Hashable, Sendable {
    case onWatch
    case waiting
    case failed

    /// Map existing BFF delivery states (honest — no inventing ON WATCH from push alone).
    static func from(delivery: Components.Schemas.WatchDeliveryState) -> GarminQueueItemState? {
        switch delivery {
        case .confirmedOnDevice, .fetchedByWidget:
            return .onWatch
        case .pushed, .generated:
            return .waiting
        case .failed:
            return .failed
        }
    }
}

struct GarminQueueItem: Identifiable, Hashable, Sendable {
    let id: String
    let workoutID: String
    let title: String
    let state: GarminQueueItemState
    /// Secondary mono line (e.g. "ON WATCH · DOWNLOADED SAT" or failure reason).
    let statusLine: String
    let failureReason: String?
}

struct OnYourWatchesSnapshot: Equatable, Sendable {
    var showsApple: Bool
    var showsGarmin: Bool
    var appleScheduledCount: Int
    var appleMaxAllowed: Int
    var appleNextLabel: String?
    var garminOnWatch: Int
    var garminWaiting: Int
    var garminFailed: Int

    var hasAnyWearable: Bool { showsApple || showsGarmin }

    var appleSlotsFree: Int {
        max(0, appleMaxAllowed - appleScheduledCount)
    }

    var badgeCount: Int {
        var total = 0
        if showsApple { total += appleScheduledCount }
        if showsGarmin { total += garminWaiting + garminFailed }
        return total
    }

    var librarySummaryLine: String {
        OnYourWatchesCopy.librarySummary(
            appleScheduled: showsApple ? appleScheduledCount : nil,
            garminOnWatch: showsGarmin ? garminOnWatch : nil,
            garminFailed: showsGarmin ? garminFailed : nil
        )
    }

    static let empty = OnYourWatchesSnapshot(
        showsApple: false,
        showsGarmin: false,
        appleScheduledCount: 0,
        appleMaxAllowed: 0,
        appleNextLabel: nil,
        garminOnWatch: 0,
        garminWaiting: 0,
        garminFailed: 0
    )
}
