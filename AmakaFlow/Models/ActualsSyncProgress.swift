//
//  ActualsSyncProgress.swift
//  AmakaFlow
//
//  AMA-2387: honest backfill progress — increments only on real ingest events.
//

import Combine
import Foundation

/// Backfill counter for Today. Display: `PULLING YOUR LAST 30 DAYS… n OF N SESSIONS ▍`
struct ActualsSyncProgress: Equatable {
    var ingested: Int
    var total: Int
    /// True while waiting on the network before the provider reports a total.
    var isAwaitingTotal: Bool = false

    /// Locked format from design-handoff/ACTUALS.md §5 (awaiting = lookback line only).
    var displayString: String {
        if isAwaitingTotal || total == 0 {
            return "\(ActualsCopy.syncPullingSub) ▍"
        }
        return "PULLING YOUR LAST 30 DAYS… \(ingested) OF \(total) SESSIONS ▍"
    }

    var isComplete: Bool {
        !isAwaitingTotal && total > 0 && ingested >= total
    }

    var shouldShowBanner: Bool {
        isAwaitingTotal || (total > 0 && !isComplete)
    }
}

/// Owns sync progress. Never invents counts — `recordIngestedSession` is a no-op
/// unless `beginBackfill(total:)` was called with a real provider total.
@MainActor
final class ActualsSyncProgressStore: ObservableObject {
    @Published private(set) var progress: ActualsSyncProgress?

    /// Avoid MainActor-isolated deinit + TaskLocal teardown crash under XCTest (Swift 6).
    nonisolated deinit {}

    /// Show the 30-day lookback line immediately (before sync-completed returns).
    func beginPulling() {
        progress = ActualsSyncProgress(ingested: 0, total: 0, isAwaitingTotal: true)
    }

    /// Start a backfill only when the provider reports a real session total.
    func beginBackfill(total: Int) {
        guard total > 0 else { return }
        progress = ActualsSyncProgress(ingested: 0, total: total, isAwaitingTotal: false)
    }

    /// Increment on a real ingested session only. Never fabricates a counter.
    func recordIngestedSession() {
        guard var current = progress, !current.isComplete else { return }
        current.ingested = min(current.ingested + 1, current.total)
        progress = current
    }

    func clear() {
        progress = nil
    }
}

// MARK: - Link toast / badge helpers

enum ActualsLinkFeedback {
    /// DD Toast on successful connect (ToastHost / DDToastCenter).
    @MainActor
    static func announceLinked(
        _ provider: ActualsSourceProvider,
        toast: DDToastCenter = .shared
    ) {
        let name = ActualsCopy.sourceDisplayName(provider)
        toast.success(
            "\(name) linked",
            sub: ActualsCopy.syncPullingSub
        )
    }

    /// Full single-line form from ACTUALS.md (for tests / copy lock).
    static func linkedToastLine(for provider: ActualsSourceProvider) -> String {
        "\(ActualsCopy.sourceDisplayName(provider)) linked — pulling your last 30 days…"
    }
}
