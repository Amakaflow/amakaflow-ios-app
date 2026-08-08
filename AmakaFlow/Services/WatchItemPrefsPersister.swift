//
//  WatchItemPrefsPersister.swift
//  AmakaFlow
//
//  AMA-2388: coalesced PUT of standing workout preferences so Watch Item
//  edits stay shared with the pre-send sheet without read-modify-write races.
//

import Foundation
import os.log

protocol WatchItemPrefsPersisting: Sendable {
    func persist(snapshot: WatchItemReadinessSnapshot)
}

/// Serializes and debounces preference PUTs. Rapid toggle/stepper edits
/// coalesce to a single write of the latest snapshot.
struct WatchItemPrefsAPIPersister: WatchItemPrefsPersisting {
    func persist(snapshot: WatchItemReadinessSnapshot) {
        Task {
            await WatchItemPrefsPersistGate.shared.enqueue(snapshot)
        }
    }
}

actor WatchItemPrefsPersistGate {
    static let shared = WatchItemPrefsPersistGate()

    private var pending: WatchItemReadinessSnapshot?
    private var flushTask: Task<Void, Never>?

    func enqueue(_ snapshot: WatchItemReadinessSnapshot) {
        pending = snapshot
        guard flushTask == nil else { return }
        flushTask = Task { await self.flush() }
    }

    private func flush() async {
        defer { flushTask = nil }
        // Debounce bursty Stepper / toggle edits.
        try? await Task.sleep(nanoseconds: 350_000_000)
        while let snapshot = pending {
            pending = nil
            do {
                try await Self.writeOnMainActor(snapshot)
            } catch {
                Self.logError(error)
            }
            // Coalesce anything that arrived during the PUT.
            if pending != nil {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    @MainActor
    private static func writeOnMainActor(_ snapshot: WatchItemReadinessSnapshot) async throws {
        let api = AppDependencies.current.apiService
        var prefs = try await api.fetchWorkoutPreferences()
        prefs.sessionWarmup.enabled = snapshot.readiness.mobilityEnabled
        prefs.sessionWarmup.activities = snapshot.config.mobilityActivities
        prefs.exerciseWarmupSets.enabled = snapshot.readiness.warmupsEnabled
        prefs.exerciseWarmupSets.perExercise = snapshot.config.perExerciseRamps
        prefs.betweenSetRest.enabled = snapshot.readiness.restEnabled
        try prefs.betweenSetRest.setRest(
            restSec: snapshot.config.restOpen ? nil : snapshot.config.restSec,
            restOpen: snapshot.config.restOpen
        )
        prefs.cooldown.enabled = snapshot.readiness.cooldownEnabled
        prefs.cooldown.activities = snapshot.config.cooldownActivities
        _ = try await api.updateWorkoutPreferences(prefs)
    }

    private static func logError(_ error: Error) {
        Logger(subsystem: "AmakaFlow", category: "WatchItemPrefs").error(
            "Watch item prefs PUT failed: \(error.localizedDescription, privacy: .public)"
        )
    }
}
