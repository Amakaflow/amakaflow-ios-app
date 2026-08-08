//
//  WatchItemReadinessStore.swift
//  AmakaFlow
//
//  AMA-2388: per-workout readiness draft + delivered baseline so Watch Item
//  edits survive dismiss and stay shared with the pre-send sheet seed path.
//

import Foundation

struct WatchItemReadinessSnapshot: Codable, Equatable, Sendable {
    var readiness: WatchItemReadinessState
    var config: WatchItemConfigState
    var snapshotPills: [String]
    var updatedAt: Date
}

protocol WatchItemReadinessStoring: Sendable {
    func loadDraft(workoutID: String) -> WatchItemReadinessSnapshot?
    func loadDelivered(workoutID: String) -> WatchItemReadinessSnapshot?
    func saveDraft(workoutID: String, snapshot: WatchItemReadinessSnapshot)
    func saveDelivered(workoutID: String, snapshot: WatchItemReadinessSnapshot)
    func clear(workoutID: String)
}

/// UserDefaults-backed draft/delivered pairs keyed by Library workoutID.
final class WatchItemReadinessStore: WatchItemReadinessStoring, @unchecked Sendable {
    static let shared = WatchItemReadinessStore()
    static let draftKeyPrefix = "ama2388_watchitem_draft_"
    static let deliveredKeyPrefix = "ama2388_watchitem_delivered_"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadDraft(workoutID: String) -> WatchItemReadinessSnapshot? {
        load(prefix: Self.draftKeyPrefix, workoutID: workoutID)
    }

    func loadDelivered(workoutID: String) -> WatchItemReadinessSnapshot? {
        load(prefix: Self.deliveredKeyPrefix, workoutID: workoutID)
    }

    func saveDraft(workoutID: String, snapshot: WatchItemReadinessSnapshot) {
        save(prefix: Self.draftKeyPrefix, workoutID: workoutID, snapshot: snapshot)
    }

    func saveDelivered(workoutID: String, snapshot: WatchItemReadinessSnapshot) {
        save(prefix: Self.deliveredKeyPrefix, workoutID: workoutID, snapshot: snapshot)
    }

    func clear(workoutID: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.draftKeyPrefix + workoutID)
        defaults.removeObject(forKey: Self.deliveredKeyPrefix + workoutID)
    }

    private func load(prefix: String, workoutID: String) -> WatchItemReadinessSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: prefix + workoutID),
              let decoded = try? JSONDecoder().decode(WatchItemReadinessSnapshot.self, from: data)
        else { return nil }
        return decoded
    }

    private func save(prefix: String, workoutID: String, snapshot: WatchItemReadinessSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: prefix + workoutID)
    }
}
