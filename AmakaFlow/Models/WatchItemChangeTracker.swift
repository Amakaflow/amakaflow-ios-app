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
    /// AMA-2423 — between-station recovery on multi-station blocks. Sibling of
    /// `rest`, never both on one block (the sheet only renders it when the
    /// delivered plan actually has stations).
    case transition
    case cooldown
}

struct WatchItemReadinessState: Equatable, Codable, Sendable {
    var mobilityEnabled: Bool
    var warmupsEnabled: Bool
    var restEnabled: Bool
    var cooldownEnabled: Bool
    /// AMA-2423 — additive; snapshots saved before this key decode as `false`.
    var transitionEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case mobilityEnabled, warmupsEnabled, restEnabled, cooldownEnabled, transitionEnabled
    }

    init(
        mobilityEnabled: Bool,
        warmupsEnabled: Bool,
        restEnabled: Bool,
        cooldownEnabled: Bool,
        transitionEnabled: Bool = false
    ) {
        self.mobilityEnabled = mobilityEnabled
        self.warmupsEnabled = warmupsEnabled
        self.restEnabled = restEnabled
        self.cooldownEnabled = cooldownEnabled
        self.transitionEnabled = transitionEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mobilityEnabled = try container.decode(Bool.self, forKey: .mobilityEnabled)
        warmupsEnabled = try container.decode(Bool.self, forKey: .warmupsEnabled)
        restEnabled = try container.decode(Bool.self, forKey: .restEnabled)
        cooldownEnabled = try container.decode(Bool.self, forKey: .cooldownEnabled)
        transitionEnabled = try container.decodeIfPresent(Bool.self, forKey: .transitionEnabled) ?? false
    }

    func isEnabled(_ row: WatchItemReadinessRow) -> Bool {
        switch row {
        case .mobility: return mobilityEnabled
        case .warmups: return warmupsEnabled
        case .rest: return restEnabled
        case .transition: return transitionEnabled
        case .cooldown: return cooldownEnabled
        }
    }

    mutating func setEnabled(_ row: WatchItemReadinessRow, _ enabled: Bool) {
        switch row {
        case .mobility: mobilityEnabled = enabled
        case .warmups: warmupsEnabled = enabled
        case .rest: restEnabled = enabled
        case .transition: transitionEnabled = enabled
        case .cooldown: cooldownEnabled = enabled
        }
    }
}

/// Local readiness configurator state (same shapes as AMA-2378 enhance sheet).
struct WatchItemConfigState: Equatable, Codable, Sendable {
    var mobilityActivities: [EnrichmentActivityPref]
    var cooldownActivities: [EnrichmentActivityPref]
    var perExerciseRamps: [PerExerciseRamp]
    var restOpen: Bool
    var restSec: Int
    /// AMA-2423 — Transitions config, parallel to `restOpen`/`restSec`. Carried
    /// here so the Watch Item surface round-trips it through
    /// `EnrichmentState.Persisted` instead of resetting the workout's saved
    /// Transitions to the defaults on every toggle.
    var transitionOpen: Bool
    var transitionSec: Int

    enum CodingKeys: String, CodingKey {
        case mobilityActivities, cooldownActivities, perExerciseRamps
        case restOpen, restSec, transitionOpen, transitionSec
    }

    init(
        mobilityActivities: [EnrichmentActivityPref],
        cooldownActivities: [EnrichmentActivityPref],
        perExerciseRamps: [PerExerciseRamp],
        restOpen: Bool,
        restSec: Int,
        transitionOpen: Bool = false,
        transitionSec: Int = 60
    ) {
        self.mobilityActivities = mobilityActivities
        self.cooldownActivities = cooldownActivities
        self.perExerciseRamps = perExerciseRamps
        self.restOpen = restOpen
        self.restSec = restSec
        self.transitionOpen = transitionOpen
        self.transitionSec = transitionSec
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mobilityActivities = try container.decode([EnrichmentActivityPref].self, forKey: .mobilityActivities)
        cooldownActivities = try container.decode([EnrichmentActivityPref].self, forKey: .cooldownActivities)
        perExerciseRamps = try container.decode([PerExerciseRamp].self, forKey: .perExerciseRamps)
        restOpen = try container.decode(Bool.self, forKey: .restOpen)
        restSec = try container.decode(Int.self, forKey: .restSec)
        transitionOpen = try container.decodeIfPresent(Bool.self, forKey: .transitionOpen) ?? false
        transitionSec = try container.decodeIfPresent(Int.self, forKey: .transitionSec) ?? 60
    }
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

    /// AMA-2388: seed draft from the shared store while keeping delivered baseline.
    init(
        baseline: WatchItemReadinessState,
        config: WatchItemConfigState,
        draft: WatchItemReadinessState,
        draftConfig: WatchItemConfigState
    ) {
        self.baseline = baseline
        self.draft = draft
        self.baselineConfig = config
        self.draftConfig = draftConfig
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
        case .transition:
            return draftConfig.transitionOpen != baselineConfig.transitionOpen
                || draftConfig.transitionSec != baselineConfig.transitionSec
        case .cooldown:
            return draftConfig.cooldownActivities != baselineConfig.cooldownActivities
        }
    }
}
