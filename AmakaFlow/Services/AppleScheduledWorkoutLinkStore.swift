//
//  AppleScheduledWorkoutLinkStore.swift
//  AmakaFlow
//
//  AMA-2388: map WorkoutKit planID → Library workoutID so Open workout /
//  enrichment seed never route a plan UUID into `.unifiedWorkout`.
//  AMA-2390: cache scheduled planJSON so Watch Item steps match the preview
//  / Apple Workout app structure (not demo placeholders).
//

import Foundation

struct AppleScheduledWorkoutLink: Codable, Hashable, Sendable {
    var planID: String
    var workoutID: String
    var title: String
    var updatedAt: Date
    /// Mapper plan JSON delivered at schedule time — powers Watch Item steps.
    var planJSON: Data?

    enum CodingKeys: String, CodingKey {
        case planID, workoutID, title, updatedAt, planJSON
    }

    init(
        planID: String,
        workoutID: String,
        title: String,
        updatedAt: Date,
        planJSON: Data? = nil
    ) {
        self.planID = planID
        self.workoutID = workoutID
        self.title = title
        self.updatedAt = updatedAt
        self.planJSON = planJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planID = try container.decode(String.self, forKey: .planID)
        workoutID = try container.decode(String.self, forKey: .workoutID)
        title = try container.decode(String.self, forKey: .title)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        planJSON = try container.decodeIfPresent(Data.self, forKey: .planJSON)
    }
}

protocol AppleScheduledWorkoutLinkStoring: Sendable {
    func load() -> [AppleScheduledWorkoutLink]
    func record(planID: String, workoutID: String, title: String, planJSON: Data?)
    func workoutID(forPlanID planID: String) -> String?
    func planJSON(forPlanID planID: String) -> Data?
    func resolve(
        planID: String,
        title: String,
        library: [(id: String, title: String)]
    ) -> String?
    func remove(planID: String)
    func clear()
}

extension AppleScheduledWorkoutLinkStoring {
    func record(planID: String, workoutID: String, title: String) {
        record(planID: planID, workoutID: workoutID, title: title, planJSON: nil)
    }
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

    func record(planID: String, workoutID: String, title: String, planJSON: Data? = nil) {
        lock.lock()
        defer { lock.unlock() }
        var items = loadUnlocked()
        let priorJSON = items.first { $0.planID == planID }?.planJSON
        items.removeAll { $0.planID == planID }
        items.insert(
            AppleScheduledWorkoutLink(
                planID: planID,
                workoutID: workoutID,
                title: title,
                updatedAt: Date(),
                planJSON: planJSON ?? priorJSON
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
        guard let id = loadUnlocked().first(where: { $0.planID == planID })?.workoutID,
              !id.isEmpty
        else { return nil }
        return id
    }

    func planJSON(forPlanID planID: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked().first { $0.planID == planID }?.planJSON
    }

    /// Prefer exact planID hit; else title-match against Library (backfill).
    /// When `library` is non-empty, reject stale Library bindings but keep
    /// cached planJSON so Watch Item can still render delivered sections.
    func resolve(
        planID: String,
        title: String,
        library: [(id: String, title: String)]
    ) -> String? {
        if let hit = workoutID(forPlanID: planID) {
            if library.isEmpty || library.contains(where: { $0.id == hit }) {
                return hit
            }
            dropLibraryLinkPreservingPlanJSON(planID: planID, title: title)
        }
        let matches = library.filter {
            WatchWorkoutTitlePolicy.isSameScheduledTitle($0.title, title)
        }
        guard matches.count == 1, let only = matches.first else { return nil }
        record(planID: planID, workoutID: only.id, title: title, planJSON: planJSON(forPlanID: planID))
        return only.id
    }

    /// Clears the Library workout binding while retaining planJSON (AMA-2390).
    private func dropLibraryLinkPreservingPlanJSON(planID: String, title: String) {
        lock.lock()
        defer { lock.unlock() }
        var items = loadUnlocked()
        guard let existing = items.first(where: { $0.planID == planID }) else { return }
        items.removeAll { $0.planID == planID }
        if let planJSON = existing.planJSON, !planJSON.isEmpty {
            items.insert(
                AppleScheduledWorkoutLink(
                    planID: planID,
                    workoutID: "",
                    title: title,
                    updatedAt: Date(),
                    planJSON: planJSON
                ),
                at: 0
            )
        }
        saveUnlocked(items)
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
