//
//  WorkoutCanonicalNaming.swift
//  AmakaFlow
//
//  Canonical workout type contracts and client-side ownership state.
//

import Foundation

enum CanonicalSource: String, Codable, Equatable, Sendable {
    case auto
    case userPick = "user_pick"
    case preset
}

struct WorkoutTypeItem: Codable, Equatable, Sendable {
    let id: String
    let category: String
    let format: String
    let focus: [String]
    let displayName: String
    let aliases: [String]
    let aiPreset: Bool
    let equipment: [String]
    let platformTags: [String: String]
}

struct WorkoutTypeCandidate: Codable, Equatable, Sendable {
    let canonicalId: String
    let displayName: String
    let confidence: Double
}

struct WorkoutTypeMatchResponse: Codable, Equatable, Sendable {
    let canonicalId: String?
    let displayName: String?
    let confidence: Double
    let method: String
    let normalizedTitle: String
    let candidates: [WorkoutTypeCandidate]
}

struct CanonicalSaveValues: Equatable, Sendable {
    let canonicalId: String?
    let source: CanonicalSource?
}

struct CanonicalMatchState: Equatable, Sendable {
    private(set) var canonicalId: String?
    private(set) var source: CanonicalSource?
    private(set) var chipDisplayName: String?
    private(set) var clearSuppressionNormalizedTitle: String?

    var clearSuppressionKey: String? {
        clearSuppressionNormalizedTitle
    }

    init(
        canonicalId: String? = nil,
        source: CanonicalSource? = nil,
        chip: String? = nil,
        clearSuppressionNormalizedTitle: String? = nil
    ) {
        self.canonicalId = canonicalId
        self.source = source
        self.chipDisplayName = chip
        self.clearSuppressionNormalizedTitle = clearSuppressionNormalizedTitle
    }

    var canAttemptAutoMatch: Bool {
        source == nil || source == .auto
    }

    mutating func applyAutoMatchIfEligible(_ response: WorkoutTypeMatchResponse) {
        guard canAttemptAutoMatch,
              !isClearSuppressed(serverNormalizedTitle: response.normalizedTitle),
              let canonicalId = response.canonicalId,
              let displayName = response.displayName else {
            return
        }
        self.canonicalId = canonicalId
        source = .auto
        chipDisplayName = displayName
    }

    mutating func applyUserPick(canonicalId: String, displayName: String) {
        applyOwned(canonicalId: canonicalId, displayName: displayName, source: .userPick)
    }

    mutating func applyPreset(canonicalId: String, displayName: String) {
        applyOwned(canonicalId: canonicalId, displayName: displayName, source: .preset)
    }

    mutating func clear(serverNormalizedTitle: String?) {
        canonicalId = nil
        source = nil
        chipDisplayName = nil
        clearSuppressionNormalizedTitle = serverNormalizedTitle
    }

    func isClearSuppressed(serverNormalizedTitle: String) -> Bool {
        clearSuppressionNormalizedTitle == serverNormalizedTitle
    }

    /// A failed or offline match never changes state, so the save snapshot always
    /// preserves the last value shown by the eventual chip.
    func valuesForSave(onlineMatchFailedOrOffline: Bool = false) -> CanonicalSaveValues {
        CanonicalSaveValues(canonicalId: canonicalId, source: source)
    }

    private mutating func applyOwned(
        canonicalId: String,
        displayName: String,
        source: CanonicalSource
    ) {
        self.canonicalId = canonicalId
        self.source = source
        chipDisplayName = displayName
        clearSuppressionNormalizedTitle = nil
    }
}

struct WorkoutTypeMatchController {
    private let apiService: any APIServiceProviding
    private(set) var state: CanonicalMatchState
    private(set) var lastMatchSoftFailed = false
    private var titleAwaitingMatch: String?
    private var currentTitleForSaveMatch: String?
    private var latestServerNormalizedTitle: String?

    var canonicalId: String? { state.canonicalId }
    var canonicalSource: CanonicalSource? { state.source }
    var chipDisplayName: String? { state.chipDisplayName }
    var clearSuppressionNormalizedTitle: String? {
        state.clearSuppressionNormalizedTitle
    }

    init(
        apiService: any APIServiceProviding,
        state: CanonicalMatchState = CanonicalMatchState()
    ) {
        self.apiService = apiService
        self.state = state
    }

    mutating func onTitleIdle(title: String) async {
        currentTitleForSaveMatch = title
        titleAwaitingMatch = title
        await attemptPendingAutoMatch()
    }

    mutating func onSave(online: Bool) async -> CanonicalSaveValues {
        if online {
            await attemptSaveAutoMatch()
        }
        // Match errors are consumed as advisory failures, so save always receives
        // the exact last-known chip state instead of being rejected.
        return state.valuesForSave(
            onlineMatchFailedOrOffline: !online || lastMatchSoftFailed
        )
    }

    mutating func applyUserPick(canonicalId: String, displayName: String) {
        state.applyUserPick(canonicalId: canonicalId, displayName: displayName)
        clearPendingMatch()
    }

    mutating func applyPreset(canonicalId: String, displayName: String) {
        state.applyPreset(canonicalId: canonicalId, displayName: displayName)
        clearPendingMatch()
    }

    mutating func clear() {
        state.clear(serverNormalizedTitle: latestServerNormalizedTitle)
        titleAwaitingMatch = nil
        lastMatchSoftFailed = false
    }

    mutating func clear(serverNormalizedTitle: String) {
        latestServerNormalizedTitle = serverNormalizedTitle
        clear()
    }

    private mutating func attemptPendingAutoMatch() async {
        guard state.canAttemptAutoMatch,
              let title = titleAwaitingMatch,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        await attemptAutoMatch(title: title)
        if !lastMatchSoftFailed {
            titleAwaitingMatch = nil
        }
    }

    private mutating func attemptSaveAutoMatch() async {
        guard state.canAttemptAutoMatch,
              state.clearSuppressionNormalizedTitle == nil
                || state.clearSuppressionNormalizedTitle != latestServerNormalizedTitle,
              let title = currentTitleForSaveMatch,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        await attemptAutoMatch(title: title)
        if !lastMatchSoftFailed {
            titleAwaitingMatch = nil
        }
    }

    private mutating func attemptAutoMatch(title: String) async {
        do {
            let response = try await apiService.matchWorkoutType(title: title)
            latestServerNormalizedTitle = response.normalizedTitle
            state.applyAutoMatchIfEligible(response)
            lastMatchSoftFailed = false
        } catch {
            // Taxonomy matching is advisory. Preserve last-known state and allow save.
            lastMatchSoftFailed = true
        }
    }

    private mutating func clearPendingMatch() {
        titleAwaitingMatch = nil
        currentTitleForSaveMatch = nil
        latestServerNormalizedTitle = nil
        lastMatchSoftFailed = false
    }
}
