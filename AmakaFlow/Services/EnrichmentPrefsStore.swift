//
//  EnrichmentPrefsStore.swift
//  AmakaFlow
//
//  AMA-2408 F3 — one per-workout store behind pre-send sheet, Watch Item, and
//  replace flow. Keyed by workout id; last-saved wins over globals on reopen.
//

import Foundation

protocol EnrichmentPrefsStoring: Sendable {
    func load(workoutID: String) -> EnrichmentState.Persisted?
    /// Dedicated AMA-2408 key only — nil when the workout has never been saved
    /// under the new store (Watch Item bridge may still have a draft).
    func loadDedicated(workoutID: String) -> EnrichmentState.Persisted?
    func save(workoutID: String, prefs: EnrichmentState.Persisted)
    func clear(workoutID: String)
}

/// UserDefaults-backed enrichment decision store. Shares the same workout-id
/// key space idea as `WatchItemReadinessStore` so every door reads/writes one
/// logical last-saved pick set.
final class EnrichmentPrefsStore: EnrichmentPrefsStoring, @unchecked Sendable {
    static let shared = EnrichmentPrefsStore()
    static let keyPrefix = "ama2408_enrichment_prefs_"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let readinessStore: any WatchItemReadinessStoring

    init(
        defaults: UserDefaults = .standard,
        readinessStore: any WatchItemReadinessStoring = WatchItemReadinessStore.shared
    ) {
        self.defaults = defaults
        self.readinessStore = readinessStore
    }

    func loadDedicated(workoutID: String) -> EnrichmentState.Persisted? {
        guard !workoutID.isEmpty else { return nil }
        lock.lock()
        let data = defaults.data(forKey: Self.keyPrefix + workoutID)
        lock.unlock()
        guard let data else { return nil }
        return try? JSONDecoder().decode(EnrichmentState.Persisted.self, from: data)
    }

    func load(workoutID: String) -> EnrichmentState.Persisted? {
        guard !workoutID.isEmpty else { return nil }
        if let dedicated = loadDedicated(workoutID: workoutID) {
            return dedicated
        }
        // Bridge: Watch Item draft/delivered already keyed by workout id —
        // prefer draft, then delivered, so reopen keeps last picks.
        if let draft = readinessStore.loadDraft(workoutID: workoutID) {
            return EnrichmentState.Persisted.from(
                readiness: draft.readiness,
                config: draft.config
            )
        }
        if let delivered = readinessStore.loadDelivered(workoutID: workoutID) {
            return EnrichmentState.Persisted.from(
                readiness: delivered.readiness,
                config: delivered.config
            )
        }
        return nil
    }

    func save(workoutID: String, prefs: EnrichmentState.Persisted) {
        guard !workoutID.isEmpty else { return }
        lock.lock()
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: Self.keyPrefix + workoutID)
        }
        lock.unlock()
    }

    func clear(workoutID: String) {
        guard !workoutID.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.keyPrefix + workoutID)
    }
}
