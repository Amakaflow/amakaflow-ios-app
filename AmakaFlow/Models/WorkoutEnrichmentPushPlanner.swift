//
//  WorkoutEnrichmentPushPlanner.swift
//  AmakaFlow
//
//  AMA-2336 — pure offer logic for the pre-push enrichment sheet (spec §5).
//
//  Given blocks + tombstones + prefs, decide what to offer and how each row is
//  checked. No UI, no networking: the sheet renders this, and `application`
//  turns the user's answer into the prefs override + remaining tombstones that
//  POST `/workout/enrich` receives.
//

import Foundation

enum WorkoutEnrichmentPushPlanner {
    // MARK: - Offer

    /// One checkbox row. `wasTombstoned` drives the "you deleted this before" copy
    /// and the tombstone clear on apply.
    struct Offer: Equatable, Identifiable, Sendable {
        var kind: EnrichmentKind
        var isChecked: Bool
        var wasTombstoned: Bool
        var title: String
        var detail: String
        /// Per-exercise tombstones to clear when `exercise_warmup_sets` is applied.
        var tombstonedExerciseIds: [String]
        /// Candidate exercise ids covered by a warm-up-sets offer (reject → tombstone).
        /// Ids-only subset — exercises without a minted `exercise_id` yet are absent.
        var candidateExerciseIds: [String]
        /// AMA-2378 v2 — every candidate's display name, in the same order as
        /// `warmupSetCandidates`. Unlike `candidateExerciseIds` this is not
        /// filtered to exercises with a minted id: the enhance sheet's live
        /// `warmupSetsSummaryV2` row needs a name for every candidate, matched
        /// to a `PerExerciseRamp` by normalized name (id-based matching lands
        /// once ids are minted ahead of the push in a later task).
        var candidateExerciseNames: [String]
        /// AMA-2378 Task 5 — each candidate's declared working-set count
        /// (`nil` when the ingest draft never declared one), same order as
        /// `candidateExerciseNames`. Feeds the ramp editor's "→ THEN YOUR K
        /// WORKING SETS" header meta; unknown stays unknown, never a guess.
        var candidateWorkingSetCounts: [Int?]

        var id: String { kind.rawValue }

        init(
            kind: EnrichmentKind,
            isChecked: Bool,
            wasTombstoned: Bool,
            detail: String,
            title: String? = nil,
            tombstonedExerciseIds: [String] = [],
            candidateExerciseIds: [String] = [],
            candidateExerciseNames: [String] = [],
            candidateWorkingSetCounts: [Int?] = [],
            target: EnrichmentPushTarget = .garmin
        ) {
            self.kind = kind
            self.isChecked = isChecked
            self.wasTombstoned = wasTombstoned
            self.title = title ?? WorkoutEnrichmentPushCopy.offerTitle(for: kind, target: target)
            self.detail = detail
            self.tombstonedExerciseIds = tombstonedExerciseIds
            self.candidateExerciseIds = candidateExerciseIds
            self.candidateExerciseNames = candidateExerciseNames
            self.candidateWorkingSetCounts = candidateWorkingSetCounts
        }
    }

    struct Plan: Equatable, Sendable {
        var offers: [Offer]
        var target: EnrichmentPushTarget

        var hasOffers: Bool { !offers.isEmpty }

        /// Kinds checked when the sheet opens.
        var defaultCheckedKinds: Set<EnrichmentKind> {
            Set(offers.filter(\.isChecked).map(\.kind))
        }

        func offer(_ kind: EnrichmentKind) -> Offer? {
            offers.first { $0.kind == kind }
        }

        init(offers: [Offer], target: EnrichmentPushTarget = .garmin) {
            self.offers = offers
            self.target = target
        }
    }

    /// Offer rows for a workout about to be pushed.
    ///
    /// Soft kinds (mobility / cooldown / warm-up sets) are offered when missing
    /// and enabled in prefs. **Between-set rest** is always offered when missing
    /// so Garmin Lap/timed Rest can be added on this push even if Settings has
    /// the standing offer off (starts unchecked). Tombstoned kinds start unchecked.
    static func plan(
        blocks: [SocialImportBlock],
        tombstones: [EnrichmentTombstone],
        prefs: WorkoutPreferences,
        target: EnrichmentPushTarget = .garmin
    ) -> Plan {
        var offers: [Offer] = []

        if prefs.sessionWarmup.enabled,
           !prefs.sessionWarmup.activities.isEmpty,
           !WorkoutEnrichmentPresence.hasWarmupBlock(in: blocks) {
            let tombstoned = WorkoutEnrichmentPresence.isTombstoned(
                .sessionWarmup,
                tombstones: tombstones
            )
            offers.append(
                Offer(
                    kind: .sessionWarmup,
                    isChecked: !tombstoned,
                    wasTombstoned: tombstoned,
                    detail: WorkoutEnrichmentPushCopy.activitiesDetail(
                        prefs.sessionWarmup.activities,
                        target: target
                    ),
                    target: target
                )
            )
        }

        if prefs.cooldown.enabled,
           !prefs.cooldown.activities.isEmpty,
           !WorkoutEnrichmentPresence.hasCooldownBlock(in: blocks) {
            let tombstoned = WorkoutEnrichmentPresence.isTombstoned(.cooldown, tombstones: tombstones)
            offers.append(
                Offer(
                    kind: .cooldown,
                    isChecked: !tombstoned,
                    wasTombstoned: tombstoned,
                    detail: WorkoutEnrichmentPushCopy.activitiesDetail(
                        prefs.cooldown.activities,
                        target: target
                    ),
                    target: target
                )
            )
        }

        // Always offer Rest when the workout has no rest intent — Garmin FIT
        // needs `rest_open` / `rest_sec` on blocks. Prefs.enabled only controls
        // the default check (off → show unchecked so this push can still opt in).
        // Apple delivery `rest_mode=omit` skips the offer (AMA-2362 / CodeRabbit).
        if !hasBlockRestIntent(in: blocks),
           !WorkoutEnrichmentPushCopy.shouldSkipRestOffer(target: target) {
            let tombstoned = WorkoutEnrichmentPresence.isTombstoned(
                .betweenSetRest,
                tombstones: tombstones
            )
            let prefsWantRest = prefs.betweenSetRest.enabled
            offers.append(
                Offer(
                    kind: .betweenSetRest,
                    isChecked: prefsWantRest && !tombstoned,
                    wasTombstoned: tombstoned,
                    detail: WorkoutEnrichmentPushCopy.restDetail(
                        prefs.betweenSetRest,
                        target: target
                    ),
                    target: target
                )
            )
        }

        if prefs.exerciseWarmupSets.enabled, !prefs.exerciseWarmupSets.defaultSets.isEmpty {
            let candidates = warmupSetCandidates(in: blocks, prefs: prefs.exerciseWarmupSets)
            if !candidates.isEmpty {
                let tombstonedIds = candidates.compactMap { candidate -> String? in
                    guard let exerciseId = candidate.exerciseId,
                          WorkoutEnrichmentPresence.isTombstoned(
                              .exerciseWarmupSets,
                              exerciseId: exerciseId,
                              tombstones: tombstones
                          ) else { return nil }
                    return exerciseId
                }
                // All candidates deleted before → start unchecked. A partial delete
                // still offers (checked) so untouched exercises are not held hostage.
                let allTombstoned = tombstonedIds.count == candidates.count
                let candidateIds = candidates.compactMap(\.exerciseId)
                offers.append(
                    Offer(
                        kind: .exerciseWarmupSets,
                        isChecked: !allTombstoned,
                        wasTombstoned: !tombstonedIds.isEmpty,
                        detail: WorkoutEnrichmentPushCopy.warmupSetsDetail(
                            prefs.exerciseWarmupSets.defaultSets,
                            exerciseCount: candidates.count
                        ),
                    tombstonedExerciseIds: tombstonedIds,
                    candidateExerciseIds: candidateIds,
                    candidateExerciseNames: candidates.map(\.name),
                    candidateWorkingSetCounts: candidates.map(\.sets),
                    target: target
                )
            )
            }
        }

        return Plan(offers: offers, target: target)
    }

    // MARK: - Apply

    /// What the user answered on the sheet.
    struct Decision: Equatable, Sendable {
        var checkedKinds: Set<EnrichmentKind>
        /// Rest override for this push. `nil` keeps the prefs value.
        var restSecOverride: Int?
        var restOpenOverride: Bool?

        init(
            checkedKinds: Set<EnrichmentKind>,
            restSecOverride: Int? = nil,
            restOpenOverride: Bool? = nil
        ) {
            self.checkedKinds = checkedKinds
            self.restSecOverride = restSecOverride
            self.restOpenOverride = restOpenOverride
        }
    }

    /// Enrich inputs for the decision: unchecked kinds are disabled so enrich
    /// cannot inject them, rejected offers are tombstoned, and tombstones for
    /// checked re-opt-in kinds are dropped.
    struct Application: Equatable, Sendable {
        var prefs: WorkoutPreferences
        var tombstones: [EnrichmentTombstone]
        var clearedTombstones: [EnrichmentTombstone]
        var rejectedTombstones: [EnrichmentTombstone]

        var appliesAnything: Bool {
            prefs.sessionWarmup.enabled
                || prefs.cooldown.enabled
                || prefs.betweenSetRest.enabled
                || prefs.exerciseWarmupSets.enabled
        }

        /// True when the sheet answer must be persisted (enrich and/or tombstones).
        var needsPersist: Bool {
            appliesAnything || !rejectedTombstones.isEmpty || !clearedTombstones.isEmpty
        }
    }

    static func application(
        plan: Plan,
        decision: Decision,
        prefs: WorkoutPreferences,
        tombstones: [EnrichmentTombstone]
    ) throws -> Application {
        var overridden = prefs
        let checked = decision.checkedKinds

        overridden.sessionWarmup.enabled = checked.contains(.sessionWarmup)
        overridden.cooldown.enabled = checked.contains(.cooldown)
        overridden.betweenSetRest.enabled = checked.contains(.betweenSetRest)
        overridden.exerciseWarmupSets.enabled = checked.contains(.exerciseWarmupSets)

        if checked.contains(.betweenSetRest),
           decision.restSecOverride != nil || decision.restOpenOverride != nil {
            let restOpen = decision.restOpenOverride ?? prefs.betweenSetRest.restOpen
            let restSec = restOpen ? nil : (decision.restSecOverride ?? prefs.betweenSetRest.restSec)
            try overridden.betweenSetRest.setRest(restSec: restSec, restOpen: restOpen)
        }

        var remaining = tombstones
        let rejected = collectRejectedTombstones(
            plan: plan,
            checked: checked,
            into: &remaining
        )
        let cleared = clearReoptInTombstones(
            plan: plan,
            checked: checked,
            into: &remaining
        )

        return Application(
            prefs: overridden,
            tombstones: remaining,
            clearedTombstones: cleared,
            rejectedTombstones: rejected
        )
    }

    /// AMA-2346/2347 — tombstone only when a **default-checked** offer was turned off.
    private static func collectRejectedTombstones(
        plan: Plan,
        checked: Set<EnrichmentKind>,
        into remaining: inout [EnrichmentTombstone]
    ) -> [EnrichmentTombstone] {
        var rejected: [EnrichmentTombstone] = []
        for offer in plan.offers where !checked.contains(offer.kind) {
            guard offer.isChecked else { continue }
            if offer.kind == .exerciseWarmupSets {
                for exerciseId in offer.candidateExerciseIds {
                    let tomb = EnrichmentTombstone(kind: offer.kind, exerciseId: exerciseId)
                    guard !remaining.contains(tomb) else { continue }
                    remaining.append(tomb)
                    rejected.append(tomb)
                }
            } else if !WorkoutEnrichmentPresence.isTombstoned(offer.kind, tombstones: remaining) {
                let tomb = EnrichmentTombstone(kind: offer.kind)
                remaining.append(tomb)
                rejected.append(tomb)
            }
        }
        return rejected
    }

    /// Clear tombstones only for true re-opt-in (offer started unchecked).
    private static func clearReoptInTombstones(
        plan: Plan,
        checked: Set<EnrichmentKind>,
        into remaining: inout [EnrichmentTombstone]
    ) -> [EnrichmentTombstone] {
        var cleared: [EnrichmentTombstone] = []
        for kind in checked {
            guard let offer = plan.offer(kind), !offer.isChecked else { continue }
            if kind == .exerciseWarmupSets {
                for exerciseId in offer.tombstonedExerciseIds {
                    cleared.append(EnrichmentTombstone(kind: kind, exerciseId: exerciseId))
                    WorkoutEnrichmentMutations.clearTombstone(
                        &remaining,
                        kind: kind,
                        exerciseId: exerciseId
                    )
                }
            } else {
                cleared.append(EnrichmentTombstone(kind: kind))
                WorkoutEnrichmentMutations.clearTombstone(&remaining, kind: kind)
            }
        }
        return cleared
    }

    // MARK: - Presence helpers

    /// Block-level rest intent — mirrors mapper `enrichment._has_rest_intent`.
    ///
    /// Between-set rest enrichment writes **block** `rest_open` / `rest_sec` for
    /// Garmin FIT (AMA-2344). Per-exercise `rest_sec` from ingest or client
    /// defaults is a separate prescription and must not hide the push-sheet offer.
    static func hasBlockRestIntent(in blocks: [SocialImportBlock]) -> Bool {
        blocks.contains { block in
            if block.restOpen == true { return true }
            if block.restOpen == false { return true }
            return block.restSec != nil
        }
    }

    /// Legacy alias — block-level only (exercise rows ignored).
    static func hasRestIntent(in blocks: [SocialImportBlock]) -> Bool {
        hasBlockRestIntent(in: blocks)
    }

    /// Rows that could take warm-up sets: a strength `sets` shape, no rows yet,
    /// and not excluded by name. Exclusion matching is server-side at enrich time;
    /// this preview mirrors it with `ExerciseKeyNormalizer` so counts stay honest.
    static func warmupSetCandidates(
        in blocks: [SocialImportBlock],
        prefs: ExerciseWarmupSetsPrefs
    ) -> [SocialImportExercise] {
        let excluded = Set(prefs.excludeExerciseKeys.map(ExerciseKeyNormalizer.normalize))
        return blocks.flatMap(\.exercises).filter { exercise in
            guard exercise.sets != nil else { return false }
            guard exercise.warmupSets?.isEmpty ?? true else { return false }
            return !excluded.contains(ExerciseKeyNormalizer.normalize(exercise.name))
        }
    }
}

/// Read-only `blocks_json` parse for presence checks.
///
/// Deliberately not `SocialImportDraft.fromIngestJSON`: that path applies
/// `PrescriptionDefaults`, which fills missing rest and would hide the very gap
/// the push sheet is asking about. Nothing here invents values.
enum WorkoutEnrichmentBlocksJSON {
    struct Parsed: Equatable, Sendable {
        var blocks: [SocialImportBlock]
        var tombstones: [EnrichmentTombstone]
    }

    static func parse(_ blocksJSON: [String: Any]) -> Parsed {
        let rawBlocks = (blocksJSON["blocks"] as? [[String: Any]]) ?? []
        let blocks = rawBlocks.map { raw in
            SocialImportBlock(
                label: raw["label"] as? String,
                rounds: raw["rounds"] as? Int ?? 1,
                exercises: ((raw["exercises"] as? [[String: Any]]) ?? []).compactMap(parseExercise),
                type: (raw["type"] as? String) ?? (raw["structure"] as? String),
                restSec: raw["rest_sec"] as? Int,
                structureSource: raw["structure_source"] as? String,
                enrichmentKind: raw["enrichment_kind"] as? String,
                restOpen: raw["rest_open"] as? Bool,
                fieldProvenance: (raw["field_provenance"] as? [String: Any])?
                    .compactMapValues { $0 as? String }
            )
        }
        return Parsed(
            blocks: blocks,
            tombstones: EnrichmentTombstone.parseFromWorkoutData(blocksJSON)
        )
    }

    private static func parseExercise(_ raw: [String: Any]) -> SocialImportExercise? {
        guard let name = (raw["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return SocialImportExercise(
            name: name,
            sets: raw["sets"] as? Int,
            reps: raw["reps"] as? Int,
            seconds: raw["duration_sec"] as? Int,
            distanceMeters: raw["distance_m"] as? Int,
            restSeconds: raw["rest_sec"] as? Int,
            exerciseId: raw["exercise_id"] as? String,
            warmupSets: WarmupSetRow.parseList(raw["warmup_sets"]),
            restOpen: raw["rest_open"] as? Bool,
            structureSource: raw["structure_source"] as? String
        )
    }
}
