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
        /// True when checked offers needed enrich and POST `/workout/enrich` failed
        /// or returned an incomplete summary (AMA-2363).
        var enrichFailed: Bool = false
        /// AMA-2365 — blocks to restore if Apple preview is canceled (pre-enrich baseline).
        var resetBlocksJSON: [String: Any]?
        /// Tombstones that belonged with `resetBlocksJSON` before this apply.
        var resetTombstones: [EnrichmentTombstone]?

        /// Apple Start may compose only when persist/enrich succeeded, or when
        /// the sheet was a clean no-op (`applied == false` with no note).
        var allowsAppleHandoff: Bool {
            if enrichFailed { return false }
            if applied { return true }
            return note == nil
        }

        static func == (lhs: ApplyOutcome, rhs: ApplyOutcome) -> Bool {
            lhs.applied == rhs.applied
                && lhs.note == rhs.note
                && lhs.enrichFailed == rhs.enrichFailed
                && lhs.resetTombstones == rhs.resetTombstones
                && NSDictionary(dictionary: lhs.resetBlocksJSON ?? [:])
                    .isEqual(to: rhs.resetBlocksJSON ?? [:])
        }
    }

    /// Snapshot used to undo an Apple Start enrich when the user cancels preview.
    struct ResetSnapshot: Equatable {
        let workoutId: String
        let title: String
        let blocksJSON: [String: Any]
        let tombstones: [EnrichmentTombstone]

        static func == (lhs: ResetSnapshot, rhs: ResetSnapshot) -> Bool {
            lhs.workoutId == rhs.workoutId
                && lhs.title == rhs.title
                && lhs.tombstones == rhs.tombstones
                && NSDictionary(dictionary: lhs.blocksJSON).isEqual(to: rhs.blocksJSON)
        }
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

        // AMA-2365 — Apple Start plans against a stripped baseline so a prior
        // cancel/re-sync never hides offers behind leftover Jump Rope blocks.
        let softNames = Self.softActivityNames(from: prefs)
        let planningJSON = target == .apple
            ? WorkoutEnrichmentMutations.stripEnrichmentOwned(
                in: blocksJSON,
                softActivityNames: softNames
            )
            : blocksJSON
        let parsed = WorkoutEnrichmentBlocksJSON.parse(planningJSON)
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: parsed.blocks,
            tombstones: EnrichmentTombstone.parseFromWorkoutData(blocksJSON),
            prefs: prefs,
            target: target
        )
        guard plan.hasOffers else { return nil }

        return Prepared(
            workoutId: workoutId,
            title: title,
            plan: plan,
            prefs: prefs,
            tombstones: EnrichmentTombstone.parseFromWorkoutData(blocksJSON),
            blocksJSON: blocksJSON,
            target: target
        )
    }

    /// Enrich, then store the result so the CIQ download builds the enriched FIT.
    /// AMA-2346: also persists reject tombstones when the user unchecks offers
    /// (including "Send as it is") so mobility/rest cannot sneak back in.
    /// AMA-2365: strip enrichment-owned extras first so sync adds once, never stacks.
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

            // Reset leftover enrichment from a prior Start/cancel, then add once.
            let softNames = Self.softActivityNames(from: prepared.prefs)
            let baseline = WorkoutEnrichmentMutations.stripEnrichmentOwned(
                in: prepared.blocksJSON,
                softActivityNames: softNames
            )
            var blocksJSON = baseline
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
                    if let summary = response.enrichmentApplied {
                        if Self.isIncompleteEnrichment(application: application, summary: summary) {
                            enrichNote = "Couldn’t add the warm-up/rest extras — fix and try again."
                            enrichFailed = true
                        } else {
                            blocksJSON = response.blocksJSON
                        }
                    } else {
                        enrichNote = "Couldn’t add the warm-up/rest extras — fix and try again."
                        enrichFailed = true
                    }
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
            return ApplyOutcome(
                applied: true,
                note: enrichNote,
                enrichFailed: enrichFailed,
                resetBlocksJSON: baseline,
                resetTombstones: prepared.tombstones
            )
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

    /// AMA-2365 — restore the pre-enrich baseline after Apple preview Cancel.
    func restore(_ snapshot: ResetSnapshot) async -> Bool {
        do {
            try await apiService.saveWorkoutBlocksJSON(
                workoutId: snapshot.workoutId,
                title: snapshot.title,
                blocksJSON: snapshot.blocksJSON,
                tombstones: snapshot.tombstones
            )
            return true
        } catch {
            logger.error(
                "Enrichment reset failed for \(snapshot.workoutId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    static func softActivityNames(from prefs: WorkoutPreferences) -> Set<String> {
        var names = Set(prefs.sessionWarmup.activities.map(\.name))
        names.formUnion(prefs.cooldown.activities.map(\.name))
        return names
    }

    /// Checked offer must land in added/refreshed/expected-skip; `skipped_no_identity`
    /// after mint is still a failure for Apple handoff (AMA-2363).
    static func isIncompleteEnrichment(
        application: WorkoutEnrichmentPushPlanner.Application,
        summary: EnrichmentAppliedSummary
    ) -> Bool {
        func satisfied(_ kind: String) -> Bool {
            summary.added.contains(kind)
                || summary.refreshed.contains(kind)
                || summary.skippedAlreadyPresent.contains(kind)
                || summary.skippedTombstoned.contains(kind)
        }

        if application.prefs.sessionWarmup.enabled, !satisfied("session_warmup") {
            return true
        }
        if application.prefs.cooldown.enabled, !satisfied("cooldown") {
            return true
        }
        if application.prefs.betweenSetRest.enabled, !satisfied("between_set_rest") {
            return true
        }
        if application.prefs.exerciseWarmupSets.enabled, !satisfied("exercise_warmup_sets") {
            if !summary.skippedNoIdentity.isEmpty { return true }
            // All candidates tombstoned per-exercise is an expected skip.
            if summary.skippedTombstonedExercises.isEmpty { return true }
        }
        return false
    }
}
