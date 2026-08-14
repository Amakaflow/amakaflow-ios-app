//
//  PassiveStrengthSummaryTransfer.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2428 — WatchConnectivity + pending-store helpers for passive summaries
//  (keeps PassiveStrengthSessionEngine under type_body_length).
//

import Foundation
import WatchConnectivity

enum PassiveStrengthSummaryTransfer {
    struct Snapshot {
        let sessionID: String
        let selectedSport: WorkoutSport
        let startDate: Date?
        let endDate: Date
        let elapsedSeconds: Int
        let totalCalories: Double
        let activeCalories: Double
        let averageHeartRateSamples: [Double]
    }

    static func makeSummary(from snapshot: Snapshot) -> StandaloneWorkoutSummary? {
        guard let startDate = snapshot.startDate else { return nil }

        let avgHeartRate: Double? = snapshot.averageHeartRateSamples.isEmpty
            ? nil
            : snapshot.averageHeartRateSamples.reduce(0, +) / Double(snapshot.averageHeartRateSamples.count)

        return StandaloneWorkoutSummary(
            workoutId: snapshot.sessionID,
            workoutName: snapshot.selectedSport.displayName,
            startDate: startDate,
            endDate: snapshot.endDate,
            durationSeconds: max(0, snapshot.elapsedSeconds),
            totalCalories: snapshot.totalCalories > 0 ? snapshot.totalCalories : snapshot.activeCalories,
            averageHeartRate: avgHeartRate,
            completedSteps: 0,
            totalSteps: 0,
            setLogs: nil,
            sport: snapshot.selectedSport.rawValue
        )
    }

    static func persistPending(_ summary: StandaloneWorkoutSummary) {
        replacePending(summary)
    }

    @discardableResult
    static func transferCurrent(_ summary: StandaloneWorkoutSummary) -> Bool {
        if transfer(summary) {
            removePendingMatching(summary)
            return true
        }
        replacePending(summary)
        print("⌚️ Passive strength summary pending (no WCSession / encode failure)")
        return false
    }

    /// Flush pending summaries. Returns workout IDs transferred this pass.
    @discardableResult
    static func flushPending() -> Set<String> {
        var queue = PassiveStrengthPendingSummaryStore.load()
        guard !queue.isEmpty else { return [] }

        PassiveStrengthPendingSummaryStore.pruneStale(&queue)

        var remaining: [StandaloneWorkoutSummary] = []
        var transferredIDs = Set<String>()
        for summary in queue {
            if transfer(summary) {
                transferredIDs.insert(summary.workoutId)
            } else {
                remaining.append(summary)
            }
        }

        PassiveStrengthPendingSummaryStore.save(remaining)
        return transferredIDs
    }

    static func transfer(_ summary: StandaloneWorkoutSummary) -> Bool {
        guard let session = WatchConnectivityBridge.shared.session else {
            return false
        }
        guard session.activationState == .activated else {
            print("⌚️ WCSession not activated yet — keeping pending summary")
            return false
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summary)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            session.transferUserInfo(["action": "workoutSummary", "summary": dict])
            print("⌚️ Passive strength summary queued (workoutId=\(summary.workoutId) sport=\(summary.sport ?? "nil"))")
            return true
        } catch {
            print("⌚️ Failed to encode passive strength summary: \(error)")
            return false
        }
    }

    private static func replacePending(_ summary: StandaloneWorkoutSummary) {
        var queue = PassiveStrengthPendingSummaryStore.load()
        queue.removeAll { $0.workoutId == summary.workoutId }
        PassiveStrengthPendingSummaryStore.save(queue)
        PassiveStrengthPendingSummaryStore.enqueue(summary)
    }

    private static func removePendingMatching(_ summary: StandaloneWorkoutSummary) {
        var queue = PassiveStrengthPendingSummaryStore.load()
        queue.removeAll {
            $0.workoutId == summary.workoutId && $0.endDate == summary.endDate
        }
        PassiveStrengthPendingSummaryStore.save(queue)
    }
}
