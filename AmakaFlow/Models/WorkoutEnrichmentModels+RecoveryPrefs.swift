//
//  WorkoutEnrichmentModels+RecoveryPrefs.swift
//  AmakaFlow
//
//  AMA-2336/2423 — the two recovery prefs sections (`between_set_rest` and
//  `station_transition`). Split from WorkoutEnrichmentModels.swift for
//  SwiftLint file_length; they are siblings that must never stack on one block.
//

import Foundation

/// Rest intent prefs. Invalid states are unrepresentable: `rest_open == true`
/// requires `rest_sec == nil` (spec §2 — contradictory intent is rejected, not dropped).
struct BetweenSetRestPrefs: Equatable, Codable, Sendable {
    var enabled: Bool
    private(set) var restSec: Int?
    private(set) var restOpen: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case restSec = "rest_sec"
        case restOpen = "rest_open"
    }

    init(enabled: Bool = true, restSec: Int? = nil, restOpen: Bool = false) throws {
        let validated = try WorkoutEnrichmentMutations.validatedRest(restSec: restSec, restOpen: restOpen)
        self.enabled = enabled
        self.restSec = validated.restSec
        self.restOpen = validated.restOpen
    }

    private init(enabled: Bool, uncheckedRestSec: Int?, restOpen: Bool) {
        self.enabled = enabled
        self.restSec = uncheckedRestSec
        self.restOpen = restOpen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            enabled: container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            restSec: container.decodeIfPresent(Int.self, forKey: .restSec),
            restOpen: container.decodeIfPresent(Bool.self, forKey: .restOpen) ?? false
        )
    }

    mutating func setRest(restSec: Int?, restOpen: Bool) throws {
        let validated = try WorkoutEnrichmentMutations.validatedRest(restSec: restSec, restOpen: restOpen)
        self.restSec = validated.restSec
        self.restOpen = validated.restOpen
    }

    static let defaults = BetweenSetRestPrefs(enabled: true, uncheckedRestSec: 60, restOpen: false)
}

/// AMA-2423 — station_transition prefs. Parallel to `BetweenSetRestPrefs`:
/// `transitionOpen == true` requires `transitionSec == nil` (same contradictory-
/// intent rejection). Off by default (spec — opt-in watch-ready recovery;
/// supersedes `between_set_rest` on the multi-station blocks it applies to,
/// never stacked with it).
struct StationTransitionPrefs: Equatable, Codable, Sendable {
    var enabled: Bool
    private(set) var transitionSec: Int?
    private(set) var transitionOpen: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case transitionSec = "transition_sec"
        case transitionOpen = "transition_open"
    }

    init(enabled: Bool = false, transitionSec: Int? = nil, transitionOpen: Bool = false) throws {
        let validated = try WorkoutEnrichmentMutations.validatedTransition(
            transitionSec: transitionSec,
            transitionOpen: transitionOpen
        )
        self.enabled = enabled
        self.transitionSec = validated.transitionSec
        self.transitionOpen = validated.transitionOpen
    }

    private init(enabled: Bool, uncheckedTransitionSec: Int?, transitionOpen: Bool) {
        self.enabled = enabled
        self.transitionSec = uncheckedTransitionSec
        self.transitionOpen = transitionOpen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            enabled: container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            transitionSec: container.decodeIfPresent(Int.self, forKey: .transitionSec),
            transitionOpen: container.decodeIfPresent(Bool.self, forKey: .transitionOpen) ?? false
        )
    }

    mutating func setTransition(transitionSec: Int?, transitionOpen: Bool) throws {
        let validated = try WorkoutEnrichmentMutations.validatedTransition(
            transitionSec: transitionSec,
            transitionOpen: transitionOpen
        )
        self.transitionSec = validated.transitionSec
        self.transitionOpen = validated.transitionOpen
    }

    /// Mirrors backend `DEFAULT_PREFS["station_transition"]` — off, no declared sec/open.
    static let defaults = StationTransitionPrefs(enabled: false, uncheckedTransitionSec: nil, transitionOpen: false)
}
