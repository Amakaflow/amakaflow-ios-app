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
        var detail: String
        /// Per-exercise tombstones to clear when `exercise_warmup_sets` is applied.
        var tombstonedExerciseIds: [String]
        /// Candidate exercise ids covered by a warm-up-sets offer (reject → tombstone).
        var candidateExerciseIds: [String]

        var id: String { kind.rawValue }

        var title: String {
            switch kind {
            case .sessionWarmup: return "Add mobility prep"
            case .cooldown: return "Cool-down"
            case .betweenSetRest: return "Between-set rest"
            case .exerciseWarmupSets: return "Exercise warm-up sets"
            }
        }

        init(
            kind: EnrichmentKind,
            isChecked: Bool,
            wasTombstoned: Bool,
            detail: String,
            tombstonedExerciseIds: [String] = [],
            candidateExerciseIds: [String] = []
        ) {
            self.kind = kind
            self.isChecked = isChecked
            self.wasTombstoned = wasTombstoned
            self.detail = detail
            self.tombstonedExerciseIds = tombstonedExerciseIds
            self.candidateExerciseIds = candidateExerciseIds
        }
    }

    struct Plan: Equatable, Sendable {
        var offers: [Offer]

        var hasOffers: Bool { !offers.isEmpty }

        /// Kinds checked when the sheet opens.
        var defaultCheckedKinds: Set<EnrichmentKind> {
            Set(offers.filter(\.isChecked).map(\.kind))
        }

        func offer(_ kind: EnrichmentKind) -> Offer? {
            offers.first { $0.kind == kind }
        }
    }

    /// Offer rows for a workout about to be pushed.
    ///
    /// A kind is offered when it is **missing** (presence by type / by intent) and
    /// the user has it enabled in prefs — a disabled kind is a declared "no",
    /// so it never nags. Tombstoned kinds are offered but start unchecked.
    static func plan(
        blocks: [SocialImportBlock],
        tombstones: [EnrichmentTombstone],
        prefs: WorkoutPreferences
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
                    detail: activitiesDetail(prefs.sessionWarmup.activities),
                    tombstonedExerciseIds: []
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
                    detail: activitiesDetail(prefs.cooldown.activities),
                    tombstonedExerciseIds: []
                )
            )
        }

        if prefs.betweenSetRest.enabled, !hasRestIntent(in: blocks) {
            let tombstoned = WorkoutEnrichmentPresence.isTombstoned(
                .betweenSetRest,
                tombstones: tombstones
            )
            offers.append(
                Offer(
                    kind: .betweenSetRest,
                    isChecked: !tombstoned,
                    wasTombstoned: tombstoned,
                    detail: restDetail(prefs.betweenSetRest),
                    tombstonedExerciseIds: []
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
                        detail: warmupSetsDetail(
                            prefs.exerciseWarmupSets.defaultSets,
                            exerciseCount: candidates.count
                        ),
                        tombstonedExerciseIds: tombstonedIds,
                        candidateExerciseIds: candidateIds
                    )
                )
            }
        }

        return Plan(offers: offers)
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
        var cleared: [EnrichmentTombstone] = []
        var rejected: [EnrichmentTombstone] = []

        // AMA-2346: unchecking an offered kind is an explicit reject — tombstone
        // so a later enrich (or re-push) cannot inject it from stored prefs.
        for offer in plan.offers where !checked.contains(offer.kind) {
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

        for kind in checked {
            // Only a true re-opt-in (offer started unchecked) clears tombstones.
            // A partial warm-up-sets offer stays default-checked and must not
            // resurrect exercises the user explicitly deleted.
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

        return Application(
            prefs: overridden,
            tombstones: remaining,
            clearedTombstones: cleared,
            rejectedTombstones: rejected
        )
    }

    // MARK: - Presence helpers

    /// Rest is "present" when any block or row already declares intent — timed or
    /// open. Delivery end conditions (AMA-2300/2316) are not consulted here.
    static func hasRestIntent(in blocks: [SocialImportBlock]) -> Bool {
        blocks.contains { block in
            if let restSec = block.restSec, restSec > 0 { return true }
            if block.restOpen == true { return true }
            return block.exercises.contains { exercise in
                if let restSeconds = exercise.restSeconds, restSeconds > 0 { return true }
                return exercise.restOpen == true
            }
        }
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

    // MARK: - Copy

    static func activitiesDetail(_ activities: [EnrichmentActivityPref]) -> String {
        guard !activities.isEmpty else { return "No activities set — add them in Settings." }
        return activities.map { activity in
            guard let durationSec = activity.durationSec, durationSec > 0 else {
                return "\(activity.name) · until Lap"
            }
            return "\(activity.name) · \(durationSec)s"
        }
        .joined(separator: ", ")
    }

    static func restDetail(_ prefs: BetweenSetRestPrefs) -> String {
        if prefs.restOpen { return "Rest until Lap between sets" }
        guard let restSec = prefs.restSec, restSec > 0 else {
            return "No rest length set — add one in Settings."
        }
        return "\(restSec)s between sets"
    }

    static func warmupSetsDetail(_ defaults: [WarmupSetDefault], exerciseCount: Int) -> String {
        let reps = defaults.map { "\($0.reps)" }.joined(separator: " · ")
        let noun = exerciseCount == 1 ? "exercise" : "exercises"
        return "\(defaults.count) warm-up sets (\(reps) reps) on \(exerciseCount) \(noun)"
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
