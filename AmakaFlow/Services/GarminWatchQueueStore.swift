//
//  GarminWatchQueueStore.swift
//  AmakaFlow
//
//  AMA-2375: local index of Garmin CIQ queue entries (BFF has per-workout status only).
//  Push / Start → Garmin paths should call `recordPush`. Remove drops the local entry.
//

import Foundation

struct GarminWatchQueueEntry: Codable, Hashable, Sendable {
    var workoutID: String
    var title: String
    var updatedAt: Date
}

protocol GarminWatchQueueStoring: Sendable {
    func load() -> [GarminWatchQueueEntry]
    func recordPush(workoutID: String, title: String)
    func remove(workoutID: String)
    func clear()
}

/// UserDefaults-backed queue of workouts the user pushed to Garmin.
final class GarminWatchQueueStore: GarminWatchQueueStoring, @unchecked Sendable {
    static let shared = GarminWatchQueueStore()
    static let defaultsKey = "ama2375_garmin_watch_queue"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [GarminWatchQueueEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([GarminWatchQueueEntry].self, from: data)
        else { return [] }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func recordPush(workoutID: String, title: String) {
        lock.lock()
        defer { lock.unlock() }
        var items = loadUnlocked()
        items.removeAll { $0.workoutID == workoutID }
        // Same display name → one queue slot unless the title is an intentional copy.
        if !WatchWorkoutTitlePolicy.isIntentionalCopy(title) {
            items.removeAll {
                WatchWorkoutTitlePolicy.isSameScheduledTitle($0.title, title)
            }
        }
        items.insert(
            GarminWatchQueueEntry(workoutID: workoutID, title: title, updatedAt: Date()),
            at: 0
        )
        // Cap local history so Library-size libraries don't explode status polls.
        if items.count > 40 {
            items = Array(items.prefix(40))
        }
        saveUnlocked(items)
    }

    func remove(workoutID: String) {
        lock.lock()
        defer { lock.unlock() }
        var items = loadUnlocked()
        items.removeAll { $0.workoutID == workoutID }
        saveUnlocked(items)
    }

    // Note: `load()` takes the lock; callers that already hold it must use `loadUnlocked()`.

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func loadUnlocked() -> [GarminWatchQueueEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([GarminWatchQueueEntry].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveUnlocked(_ items: [GarminWatchQueueEntry]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
