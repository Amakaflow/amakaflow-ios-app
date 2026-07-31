//
//  WorkoutEnrichmentPushCoordinator.swift
//  AmakaFlow
//
//  AMA-2336 — the networked half of the pre-push enrichment sheet.
//  `WorkoutEnrichmentPushPlanner` decides what to offer; this fetches the inputs
//  and applies the answer. Every failure degrades to "push what we have" so a
//  down mapper never blocks a session.
//

import Foundation
import os

@MainActor
final class WorkoutEnrichmentPushCoordinator {
    /// Everything the sheet needs, gathered before it is presented.
    struct Prepared: Equatable, Identifiable {
        let workoutId: String
        let title: String
        let plan: WorkoutEnrichmentPushPlanner.Plan
        let prefs: WorkoutPreferences
        let tombstones: [EnrichmentTombstone]
        let blocksJSON: [String: Any]
        /// AMA-2362 — drives Open vs Lap copy and Apple restOpen seed.
        let target: EnrichmentPushTarget

        var id: String { workoutId }

        static func == (lhs: Prepared, rhs: Prepared) -> Bool {
            lhs.workoutId == rhs.workoutId
                && lhs.title == rhs.title
                && lhs.plan == rhs.plan
                && lhs.prefs == rhs.prefs
                && lhs.tombstones == rhs.tombstones
                && lhs.target == rhs.target
                && NSDictionary(dictionary: lhs.blocksJSON).isEqual(to: rhs.blocksJSON)
        }
    }

    /// Outcome of applying the sheet. `note` is user-facing when something was
    /// skipped — silence means the enriched structure is stored and ready to push.
    struct ApplyOutcome: Equatable {
        var applied: Bool
        var note: String?
        /// True when checked offers needed enrich and POST `/workout/enrich` failed.
        /// Apple Start must not silently compose the unenriched workout (AMA-2363).
        var enrichFailed: Bool = false
    }

    private let apiService: APIServiceProviding
    private let logger = Logger(subsystem: "com.amakaflow.app", category: "enrichment")

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
    }

    /// Gather prefs + stored blocks and decide whether the sheet has anything to
    /// ask. Returns `nil` when there is nothing to offer or an input is
    /// unavailable — the caller then pushes exactly as it does today.
    func prepare(
        workoutId: String,
        title: String,
        target: EnrichmentPushTarget = .garmin
    ) async -> Prepared? {
        guard !workoutId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let prefs: WorkoutPreferences
        let blocksJSON: [String: Any]
        do {
            async let prefsTask = apiService.fetchWorkoutPreferences()
            async let blocksTask = apiService.fetchWorkoutBlocksJSON(workoutId: workoutId)
            prefs = try await prefsTask
            blocksJSON = try await blocksTask
        } catch {
            // Honest skip: no offers rather than a blocked push.
            logger.info(
                "Enrichment offers unavailable for \(workoutId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        let parsed = WorkoutEnrichmentBlocksJSON.parse(blocksJSON)
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: parsed.blocks,
            tombstones: parsed.tombstones,
            prefs: prefs,
            target: target
        )
        guard plan.hasOffers else { return nil }

        return Prepared(
            workoutId: workoutId,
            title: title,
            plan: plan,
            prefs: prefs,
            tombstones: parsed.tombstones,
            blocksJSON: blocksJSON,
            target: target
        )
    }

    /// Enrich, then store the result so the CIQ download builds the enriched FIT.
    /// AMA-2346: also persists reject tombstones when the user unchecks offers
    /// (including "Send as it is") so mobility/rest cannot sneak back in.
    func apply(
        prepared: Prepared,
        decision: WorkoutEnrichmentPushPlanner.Decision
    ) async -> ApplyOutcome {
        do {
            let application = try WorkoutEnrichmentPushPlanner.application(
                plan: prepared.plan,
                decision: decision,
                prefs: prepared.prefs,
                tombstones: prepared.tombstones
            )
            guard application.needsPersist else {
                return ApplyOutcome(applied: false, note: nil)
            }

            var blocksJSON = prepared.blocksJSON
            var enrichNote: String?
            var enrichFailed = false
            if application.appliesAnything {
                // Warm-up sets need exercise_id — mint before enrich (AMA-2363).
                if application.prefs.exerciseWarmupSets.enabled {
                    blocksJSON = WorkoutEnrichmentMutations.mintMissingExerciseIds(in: blocksJSON)
                }
                // Narrow enrich failure: still persist reject tombstones so unchecked
                // offers cannot reappear on the next push (AMA-2346).
                do {
                    let response = try await apiService.enrichWorkout(
                        EnrichRequest(
                            blocksJSON: blocksJSON,
                            prefs: application.prefs,
                            tombstones: application.tombstones,
                            mode: .push
                        )
                    )
                    blocksJSON = response.blocksJSON
                } catch {
                    logger.error(
                        "Enrich failed, persisting tombstones only for \(prepared.workoutId, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    enrichNote = "Couldn’t add the warm-up/rest extras — fix and try again."
                    enrichFailed = true
                }
            }
            // Enrich is read-only on tombstones — persist the sheet answer ourselves.
            try await apiService.saveWorkoutBlocksJSON(
                workoutId: prepared.workoutId,
                title: prepared.title,
                blocksJSON: blocksJSON,
                tombstones: application.tombstones
            )
            return ApplyOutcome(applied: true, note: enrichNote, enrichFailed: enrichFailed)
        } catch {
            logger.error(
                "Enrichment apply failed for \(prepared.workoutId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return ApplyOutcome(
                applied: false,
                note: "Couldn’t add the warm-up/rest extras — sending your workout as it is."
            )
        }
    }
}
