//
//  AppleScheduledWorkoutLinkStore.swift
//  AmakaFlow
//
//  AMA-2388: map WorkoutKit planID → Library workoutID so Open workout /
//  enrichment seed never route a plan UUID into `.unifiedWorkout`.
//

import Foundation

struct AppleScheduledWorkoutLink: Codable, Hashable, Sendable {
    var planID: String
    var workoutID: String
    var title: String
    var updatedAt: Date
}

protocol AppleScheduledWorkoutLinkStoring: Sendable {
    func load() -> [AppleScheduledWorkoutLink]
    func record(planID: String, workoutID: String, title: String)
    func workoutID(forPlanID planID: String) -> String?
    func resolve(
        planID: String,
        title: String,
        library: [(id: String, title: String)]
    ) -> String?
    func remove(planID: String)
    func clear()
}

/// UserDefaults-backed planID → workoutID index (Garmin queue store pattern).
final class AppleScheduledWorkoutLinkStore: AppleScheduledWorkoutLinkStoring, @unchecked Sendable {
    static let shared = AppleScheduledWorkoutLinkStore()
    static let defaultsKey = "ama2388_apple_scheduled_workout_links"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [AppleScheduledWorkoutLink] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked().sorted { $0.updatedAt > $1.updatedAt }
    }

    func record(planID: String, workoutID: String, title: String) {
        lock.lock()
        defer { lock.unlock() }
        var items = loadUnlocked()
        items.removeAll { $0.planID == planID }
        items.insert(
            AppleScheduledWorkoutLink(
                planID: planID,
                workoutID: workoutID,
                title: title,
                updatedAt: Date()
            ),
            at: 0
        )
        if items.count > 80 {
            items = Array(items.prefix(80))
        }
        saveUnlocked(items)
    }

    func workoutID(forPlanID planID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked().first { $0.planID == planID }?.workoutID
    }

    /// Prefer exact planID hit; else title-match against Library (backfill).
    func resolve(
        planID: String,
        title: String,
        library: [(id: String, title: String)]
    ) -> String? {
        if let hit = workoutID(forPlanID: planID) { return hit }
        let matches = library.filter {
            WatchWorkoutTitlePolicy.isSameScheduledTitle($0.title, title)
        }
        guard matches.count == 1, let only = matches.first else { return nil }
        record(planID: planID, workoutID: only.id, title: title)
        return only.id
    }

    func remove(planID: String) {
        lock.lock()
        defer { lock.unlock() }
        var items = loadUnlocked()
        items.removeAll { $0.planID == planID }
        saveUnlocked(items)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func loadUnlocked() -> [AppleScheduledWorkoutLink] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([AppleScheduledWorkoutLink].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveUnlocked(_ items: [AppleScheduledWorkoutLink]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
