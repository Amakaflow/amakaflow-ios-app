//
//  UserDefaultsAcceptedMigration.swift
//  AmakaFlow
//
//  AMA-1792: one-shot migration of legacy UserDefaults-backed accepted
//  suggestions into the GRDB-backed AcceptedSuggestionsRepository +
//  WorkoutEventsRepository. Existing TestFlight users on builds 28-31 have
//  workouts persisted under `amakaflow.acceptedSuggestions.v1`; the new
//  build hydrates Home from the local DB exclusively, so anything still in
//  UserDefaults would silently disappear without this step.
//
//  The migration is idempotent: it is gated by a separate UserDefaults
//  flag so it runs at most once per device. Each migrated row uses a
//  deterministic `client_generated_id` (sha256("legacy:" + workout.id)) so
//  if the network sync runs twice we don't enqueue duplicate
//  /workouts/accept-suggestion writes.
//

import CryptoKit
import Foundation

enum UserDefaultsAcceptedMigration {

    static let legacyKey = "amakaflow.acceptedSuggestions.v1"
    static let migrationFlagKey = "amakaflow.acceptedSuggestions.migratedToGRDB.v1"

    /// Run the migration if the flag has not yet been set. Safe to call on
    /// every app launch — bails out immediately on the second invocation.
    static func runIfNeeded(
        userId: String?,
        defaults: UserDefaults = .standard,
        acceptedRepo: AcceptedSuggestionsRepository,
        eventsRepo: WorkoutEventsRepository,
        now: () -> Date = Date.init,
        logger: (String, String) -> Void = { msg, details in
            Task { @MainActor in
                DebugLogService.shared.log(
                    msg,
                    details: details,
                    metadata: ["source": "UserDefaultsAcceptedMigration"]
                )
            }
        }
    ) {
        guard !defaults.bool(forKey: migrationFlagKey) else { return }
        guard let userId, !userId.isEmpty else {
            // Wait for sign-in. Don't set the flag — we want to retry once
            // we have a real Clerk user id.
            return
        }
        guard let data = defaults.data(forKey: legacyKey) else {
            // Nothing to migrate. Stamp the flag so we don't re-check.
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        let decoder = JSONDecoder()
        let workouts: [Workout]
        do {
            workouts = try decoder.decode([Workout].self, from: data)
        } catch {
            // CR: don't permanently discard the legacy payload on a decode
            // miss — schema drift on one row would otherwise lose every
            // accepted workout for the user. Stash the raw blob under a
            // backup key for offline forensics, leave the legacy key + flag
            // untouched so a future build (or a fixed schema) can retry.
            defaults.set(data, forKey: "\(legacyKey).failed")
            logger(
                "Legacy accepted-suggestions decode failed",
                "error=\(error.localizedDescription) — preserved at \(legacyKey).failed for retry"
            )
            return
        }

        guard !workouts.isEmpty else {
            defaults.removeObject(forKey: legacyKey)
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        // AMA-1815: take only the most-recently-accepted legacy entry.
        // The old UserDefaults store appended on every Accept and never
        // pruned beyond completion, so a long-running TF user could have
        // 5+ entries. Migrating all of them lit up Quick Start with
        // duplicates on Build 39. Honour the new "one current accepted
        // suggestion" semantic by taking the last entry only.
        let toMigrate = Array(workouts.suffix(1))
        let dropped = workouts.count - toMigrate.count

        let timestamp = now()
        let dateString = WorkoutEventsRepository.dayString(timestamp)
        var migrated = 0
        var failed = 0

        for workout in toMigrate {
            let clientId = legacyClientGeneratedId(for: workout.id)

            let suggestion = LocalAcceptedSuggestion(
                id: workout.id,
                userId: userId,
                suggestionId: nil,
                workoutEventId: workout.id,
                status: "accepted",
                clientGeneratedId: clientId,
                serverVersion: 0,
                createdAt: timestamp,
                updatedAt: timestamp,
                deletedAt: nil
            )
            let payload = (try? encodeToJSONString(workout)) ?? "{}"
            let event = LocalWorkoutEvent(
                id: workout.id,
                userId: userId,
                date: dateString,
                startTime: nil,
                endTime: nil,
                status: "planned",
                source: "suggestion_accepted",
                jsonPayload: payload,
                clientGeneratedId: clientId,
                serverVersion: 0,
                createdAt: timestamp,
                updatedAt: timestamp,
                deletedAt: nil
            )

            do {
                // CR pass 2: atomic 2-table write so a failure can't
                // leave a workout_events row without its accepted_suggestions
                // partner (which `hydrateIncoming` would resurrect).
                try acceptedRepo.acceptedWithEvent(suggestion: suggestion, event: event, enqueueSync: true)
                migrated += 1
            } catch {
                failed += 1
                logger(
                    "Legacy accepted-suggestion migration row failed",
                    "workoutId=\(workout.id) error=\(error.localizedDescription)"
                )
            }
        }

        if failed == 0 {
            defaults.removeObject(forKey: legacyKey)
            defaults.set(true, forKey: migrationFlagKey)
        }
        // If at least one row failed we keep the legacy key around so a
        // future launch can retry; the flag stays unset.

        logger(
            "Accepted-suggestion legacy migration complete",
            "userId=\(userId) migrated=\(migrated) failed=\(failed) dropped=\(dropped) total=\(workouts.count)"
        )
    }

    /// Stable client_generated_id for legacy rows: sha256 of `legacy:<workout.id>`
    /// gives the same id on every device for the same workout, so a re-run
    /// (or a parallel sync from another device) won't create duplicates
    /// when the backend de-dupes on client_generated_id.
    static func legacyClientGeneratedId(for workoutId: String) -> String {
        // CR pass 3: UTF-8 encoding of a Swift String never fails; the
        // non-optional initializer skips the SwiftLint warning.
        let digest = SHA256.hash(data: Data("legacy:\(workoutId)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
