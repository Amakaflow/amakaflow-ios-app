//
//  PassiveStrengthPendingSummaryStore.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 — bounded UserDefaults queue for undelivered passive summaries.
//

import Foundation

enum PassiveStrengthPendingSummaryStore {
    private static let pendingSummariesDefaultsKey = "ama2420_pending_passive_strength_summaries"
    /// Legacy single-blob key — migrated into the queue on first load.
    private static let legacyPendingSummaryDefaultsKey = "ama2420_pending_passive_strength_summary"
    static let maxAge: TimeInterval = 24 * 60 * 60
    static let maxCount = 5

    static func load() -> [StandaloneWorkoutSummary] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = UserDefaults.standard.data(forKey: pendingSummariesDefaultsKey) {
            do {
                return try decoder.decode([StandaloneWorkoutSummary].self, from: data)
            } catch {
                print("⌚️ Failed to load pending passive summaries: \(error)")
            }
        }

        // Migrate legacy single-slot blob.
        if let data = UserDefaults.standard.data(forKey: legacyPendingSummaryDefaultsKey) {
            do {
                let summary = try decoder.decode(StandaloneWorkoutSummary.self, from: data)
                UserDefaults.standard.removeObject(forKey: legacyPendingSummaryDefaultsKey)
                return [summary]
            } catch {
                print("⌚️ Failed to migrate legacy pending passive summary: \(error)")
                UserDefaults.standard.removeObject(forKey: legacyPendingSummaryDefaultsKey)
            }
        }

        return []
    }

    static func save(_ summaries: [StandaloneWorkoutSummary]) {
        UserDefaults.standard.removeObject(forKey: legacyPendingSummaryDefaultsKey)
        guard !summaries.isEmpty else {
            UserDefaults.standard.removeObject(forKey: pendingSummariesDefaultsKey)
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summaries)
            UserDefaults.standard.set(data, forKey: pendingSummariesDefaultsKey)
        } catch {
            print("⌚️ Failed to persist pending passive summaries: \(error)")
        }
    }

    static func enqueue(_ summary: StandaloneWorkoutSummary) {
        var queue = load()
        if queue.contains(where: { $0.workoutId == summary.workoutId && $0.endDate == summary.endDate }) {
            save(queue)
            return
        }
        queue.append(summary)
        if queue.count > maxCount {
            let dropped = queue.removeFirst()
            print("⌚️ Pending passive summary queue full — dropped oldest workoutId=\(dropped.workoutId)")
        }
        save(queue)
    }

    /// Drop stale entries; return the remaining queue (caller transfers + saves).
    static func pruneStale(_ queue: inout [StandaloneWorkoutSummary], now: Date = Date()) {
        queue.removeAll { summary in
            let age = now.timeIntervalSince(summary.endDate)
            if age > maxAge {
                print("⌚️ Dropping stale pending passive summary (age=\(Int(age))s)")
                return true
            }
            return false
        }
    }
}
