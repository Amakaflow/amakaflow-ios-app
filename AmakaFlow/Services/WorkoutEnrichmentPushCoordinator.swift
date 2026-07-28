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

        var id: String { workoutId }

        static func == (lhs: Prepared, rhs: Prepared) -> Bool {
            lhs.workoutId == rhs.workoutId
                && lhs.title == rhs.title
                && lhs.plan == rhs.plan
                && lhs.prefs == rhs.prefs
                && lhs.tombstones == rhs.tombstones
                && NSDictionary(dictionary: lhs.blocksJSON).isEqual(to: rhs.blocksJSON)
        }
    }

    /// Outcome of applying the sheet. `note` is user-facing when something was
    /// skipped — silence means the enriched structure is stored and ready to push.
    struct ApplyOutcome: Equatable {
        var applied: Bool
        var note: String?
    }

    private let apiService: APIServiceProviding
    private let logger = Logger(subsystem: "com.amakaflow.app", category: "enrichment")

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
    }

    /// Gather prefs + stored blocks and decide whether the sheet has anything to
    /// ask. Returns `nil` when there is nothing to offer or an input is
    /// unavailable — the caller then pushes exactly as it does today.
    func prepare(workoutId: String, title: String) async -> Prepared? {
        guard !workoutId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let prefs: WorkoutPreferences
        let blocksJSON: [String: Any]
        do {
            prefs = try await apiService.fetchWorkoutPreferences()
            blocksJSON = try await apiService.fetchWorkoutBlocksJSON(workoutId: workoutId)
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
            prefs: prefs
        )
        guard plan.hasOffers else { return nil }

        return Prepared(
            workoutId: workoutId,
            title: title,
            plan: plan,
            prefs: prefs,
            tombstones: parsed.tombstones,
            blocksJSON: blocksJSON
        )
    }

    /// Enrich, then store the result so the CIQ download builds the enriched FIT.
    func apply(
        prepared: Prepared,
        decision: WorkoutEnrichmentPushPlanner.Decision
    ) async -> ApplyOutcome {
        guard !decision.checkedKinds.isEmpty else {
            return ApplyOutcome(applied: false, note: nil)
        }

        do {
            let application = try WorkoutEnrichmentPushPlanner.application(
                plan: prepared.plan,
                decision: decision,
                prefs: prepared.prefs,
                tombstones: prepared.tombstones
            )
            let response = try await apiService.enrichWorkout(
                EnrichRequest(
                    blocksJSON: prepared.blocksJSON,
                    prefs: application.prefs,
                    tombstones: application.tombstones,
                    mode: .push
                )
            )
            // Enrich is read-only on tombstones — persist the cleared set ourselves.
            try await apiService.saveWorkoutBlocksJSON(
                workoutId: prepared.workoutId,
                title: prepared.title,
                blocksJSON: response.blocksJSON,
                tombstones: application.tombstones
            )
            return ApplyOutcome(applied: true, note: nil)
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
