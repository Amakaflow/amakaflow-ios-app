//
//  WatchItemChangeTracker.swift
//  AmakaFlow
//
//  AMA-2386: N = distinct readiness rows differing from the delivered baseline.
//  A row counts when its toggle OR its configurator content differs.
//  Reset only after confirmed Replace success.
//

import Foundation

enum WatchItemReadinessRow: String, CaseIterable, Hashable, Sendable {
    case mobility
    case warmups
    case rest
    case cooldown
}

struct WatchItemReadinessState: Equatable, Sendable {
    var mobilityEnabled: Bool
    var warmupsEnabled: Bool
    var restEnabled: Bool
    var cooldownEnabled: Bool

    func isEnabled(_ row: WatchItemReadinessRow) -> Bool {
        switch row {
        case .mobility: return mobilityEnabled
        case .warmups: return warmupsEnabled
        case .rest: return restEnabled
        case .cooldown: return cooldownEnabled
        }
    }

    mutating func setEnabled(_ row: WatchItemReadinessRow, _ enabled: Bool) {
        switch row {
        case .mobility: mobilityEnabled = enabled
        case .warmups: warmupsEnabled = enabled
        case .rest: restEnabled = enabled
        case .cooldown: cooldownEnabled = enabled
        }
    }
}

/// Local readiness configurator state (same shapes as AMA-2378 enhance sheet).
struct WatchItemConfigState: Equatable, Sendable {
    var mobilityActivities: [EnrichmentActivityPref]
    var cooldownActivities: [EnrichmentActivityPref]
    var perExerciseRamps: [PerExerciseRamp]
    var restOpen: Bool
    var restSec: Int
}

struct WatchItemChangeTracker: Equatable, Sendable {
    private(set) var baseline: WatchItemReadinessState
    private(set) var draft: WatchItemReadinessState
    private(set) var baselineConfig: WatchItemConfigState
    private(set) var draftConfig: WatchItemConfigState

    init(baseline: WatchItemReadinessState, config: WatchItemConfigState) {
        self.baseline = baseline
        self.draft = baseline
        self.baselineConfig = config
        self.draftConfig = config
    }

    var changeCount: Int {
        WatchItemReadinessRow.allCases.reduce(0) { count, row in
            count + (isChanged(row) ? 1 : 0)
        }
    }

    var hasChanges: Bool { changeCount > 0 }

    func isChanged(_ row: WatchItemReadinessRow) -> Bool {
        draft.isEnabled(row) != baseline.isEnabled(row) || configDiffers(row)
    }

    mutating func setEnabled(_ row: WatchItemReadinessRow, _ enabled: Bool) {
        draft.setEnabled(row, enabled)
    }

    mutating func updateConfig(_ mutate: (inout WatchItemConfigState) -> Void) {
        mutate(&draftConfig)
    }

    /// Confirmed replace succeeded — new delivered baseline is the draft.
    mutating func markSucceeded() {
        baseline = draft
        baselineConfig = draftConfig
    }

    private func configDiffers(_ row: WatchItemReadinessRow) -> Bool {
        switch row {
        case .mobility:
            return draftConfig.mobilityActivities != baselineConfig.mobilityActivities
        case .warmups:
            return draftConfig.perExerciseRamps != baselineConfig.perExerciseRamps
        case .rest:
            return draftConfig.restOpen != baselineConfig.restOpen
                || draftConfig.restSec != baselineConfig.restSec
        case .cooldown:
            return draftConfig.cooldownActivities != baselineConfig.cooldownActivities
        }
    }
}
