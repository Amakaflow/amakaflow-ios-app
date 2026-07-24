//
//  GarminHandoffTelemetry.swift
//  AmakaFlow
//
//  AMA-2317: prove "the app crashed" vs "iOS suspended us during the Garmin
//  handoff". A handoff record is written before the push and cleared when the
//  result is shown; a record still open at next launch means the process died.
//

import Foundation
import Sentry

/// Where a Start → Garmin handoff got to. Persisted so the status survives the
/// app being suspended (or killed) while Garmin Connect is in the foreground.
struct GarminHandoffRecord: Codable, Equatable {
    enum Outcome: String, Codable {
        case queued
        case sent
        case readyOnWatch = "ready_on_watch"
        case failed
    }

    let workoutId: String
    let gymTitle: String
    let startedAt: Date
    var finishedAt: Date?
    var outcome: Outcome?
    var message: String?

    var isInFlight: Bool { finishedAt == nil }
}

extension GarminStartHandoffResult.Kind {
    var telemetryOutcome: GarminHandoffRecord.Outcome {
        switch self {
        case .queued: return .queued
        case .sent: return .sent
        case .readyOnWatch: return .readyOnWatch
        case .failed: return .failed
        }
    }
}

/// UserDefaults-backed store for the most recent Garmin handoff.
///
/// Only one handoff is tracked at a time — Start → Garmin is a single-shot
/// action and the dogfood question is always "what happened to the last one".
struct GarminHandoffStateStore {
    private let defaults: UserDefaults
    private let key = DefaultsKey.garminHandoffState.rawValue

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var record: GarminHandoffRecord? {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(GarminHandoffRecord.self, from: data)
        else {
            return nil
        }
        return decoded
    }

    func begin(workoutId: String, gymTitle: String, now: Date = Date()) {
        write(
            GarminHandoffRecord(
                workoutId: workoutId,
                gymTitle: gymTitle,
                startedAt: now,
                finishedAt: nil,
                outcome: nil,
                message: nil
            )
        )
    }

    func finish(
        workoutId: String,
        outcome: GarminHandoffRecord.Outcome,
        message: String,
        now: Date = Date()
    ) {
        guard var current = record, current.workoutId == workoutId else { return }
        current.finishedAt = now
        current.outcome = outcome
        current.message = message
        write(current)
    }

    /// The finished handoff to re-show when the detail screen reappears (after a
    /// suspend, an app switch to Garmin Connect, or a cold relaunch). Returns the
    /// whole record so callers can tell a success apart from a failure.
    func restorable(workoutId: String, now: Date = Date(), maxAge: TimeInterval = 3600) -> GarminHandoffRecord? {
        guard
            let record,
            record.workoutId == workoutId,
            record.message != nil,
            let finishedAt = record.finishedAt,
            now.timeIntervalSince(finishedAt) <= maxAge
        else {
            return nil
        }
        return record
    }

    /// A record still open at launch means the process died mid-handoff — the
    /// only signal we have that the "crash" report was a real termination.
    func takeInterrupted() -> GarminHandoffRecord? {
        guard let record, record.isInFlight else { return nil }
        clear()
        return record
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func write(_ record: GarminHandoffRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Sentry breadcrumbs for the push → open-Garmin sequence.
@MainActor
enum GarminHandoffTelemetry {
    private static let category = "garmin_handoff"

    static func pushStarted(workoutId: String, prefs: GarminWatchDisplayPrefs, hasConfiguredPrefs: Bool) {
        breadcrumb(
            "push_started",
            data: [
                "workout_id": workoutId,
                "exercise_end": prefs.exerciseEnd.rawValue,
                "rest_mode": prefs.restMode.rawValue,
                "default_rest_sec": prefs.defaultRestSec,
                "prefs_configured": hasConfiguredPrefs
            ]
        )
    }

    static func pushFinished(workoutId: String, outcome: GarminHandoffRecord.Outcome) {
        breadcrumb(
            "push_finished",
            level: outcome == .failed ? .warning : .info,
            data: ["workout_id": workoutId, "outcome": outcome.rawValue]
        )
    }

    static func openAppRequested(workoutId: String) {
        breadcrumb("ciq_open_app_requested", data: ["workout_id": workoutId])
    }

    static func scenePhaseChanged(_ phase: String, duringHandoff: Bool) {
        breadcrumb("scene_phase", data: ["phase": phase, "during_handoff": duringHandoff])
    }

    /// Non-fatal so the dogfood "it crashed" report can be confirmed or ruled
    /// out without a device crash log. Called from app start-up, off the actor.
    nonisolated static func reportInterrupted(_ record: GarminHandoffRecord, now: Date = Date()) {
        SentrySDK.capture(message: "garmin_handoff_interrupted") { scope in
            scope.setLevel(.warning)
            scope.setTag(value: "garmin_handoff", key: "error_category")
            scope.setExtra(value: record.workoutId, key: "workout_id")
            scope.setExtra(value: record.gymTitle, key: "gym_title")
            scope.setExtra(value: now.timeIntervalSince(record.startedAt), key: "seconds_since_start")
        }
    }

    private static func breadcrumb(_ message: String, level: SentryLevel = .info, data: [String: Any]) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
    }
}
