//
//  WorkoutEnrichmentPushCopy.swift
//  AmakaFlow
//
//  AMA-2362 — device-aware enrichment sheet copy + Apple restOpen seeding.
//

import Foundation

/// Device that will receive the enriched workout after the pre-send sheet.
enum EnrichmentPushTarget: String, Equatable, Sendable {
    case apple
    case garmin
}

enum WorkoutEnrichmentPushCopy {
    // MARK: - AMA-2371 Peloton-style toggle rows

    /// Enhance sheet title (redesign 2026-08-02 §Enhance sheet).
    static let sheetTitle = "Make it watch-ready?"

    /// Secondary CTA — always visible, wired to `onSkip`.
    static let sendAsIsCTA = "Send as-is — no changes"

    /// Primary CTA counts checked offers live; `Send` when nothing is checked.
    static func primaryCTA(checkedCount: Int) -> String {
        checkedCount > 0 ? "Add \(checkedCount) & send" : "Send"
    }

    /// Device name used in the sheet intro copy.
    static func deviceName(for target: EnrichmentPushTarget) -> String {
        switch target {
        case .apple: return "Apple Watch"
        case .garmin: return "Garmin"
        }
    }

    static func introText(target: EnrichmentPushTarget) -> String {
        "This workout is missing a few things you usually add before it hits your \(deviceName(for: target))."
    }

    /// Rest config segmented control's non-timed label — Apple `Open rest`, Garmin `Lap button`.
    static func restOpenSegmentLabel(target: EnrichmentPushTarget) -> String {
        switch target {
        case .apple: return "Open rest"
        case .garmin: return "Lap button"
        }
    }

    static let restTimedSegmentLabel = "Timed"

    /// Timed-rest stepper bounds — brief 2026-08-02 §Enhance sheet (15...300, 15s grid).
    static let restSecRange = 15...300
    private static let restSecStep = 15

    /// Clamp + snap a persisted `restSec` to the sheet's supported stepper
    /// range and 15s grid. Historic prefs (pre-AMA-2371 allowed 15...600, or
    /// unaligned values from other clients) must not bypass the new bound —
    /// a saved 600 would otherwise render and be confirmable as-is.
    static func normalizedRestSec(_ restSec: Int?) -> Int {
        let value = restSec ?? 60
        let snapped = ((value + restSecStep / 2) / restSecStep) * restSecStep
        return min(max(snapped, restSecRange.lowerBound), restSecRange.upperBound)
    }

    /// AMA-2423 — Transitions config segmented control, parallel to `restOpenSegmentLabel`.
    static func transitionOpenSegmentLabel(target: EnrichmentPushTarget) -> String {
        switch target {
        case .apple: return "Open transition"
        case .garmin: return "Lap button"
        }
    }

    static let transitionTimedSegmentLabel = "Timed"

    /// Same stepper bounds/grid as Rest (spec — "same stepper range as rest").
    static let transitionSecRange = restSecRange
    private static let transitionSecStep = restSecStep

    /// Clamp + snap a persisted `transitionSec` to the sheet's supported range.
    static func normalizedTransitionSec(_ transitionSec: Int?) -> Int {
        let value = transitionSec ?? 60
        let snapped = ((value + transitionSecStep / 2) / transitionSecStep) * transitionSecStep
        return min(max(snapped, transitionSecRange.lowerBound), transitionSecRange.upperBound)
    }

    /// AMA-2423 — Transitions row title (offer XOR's with `betweenSetRest`).
    static let stationTransitionTitle = "Transitions between stations"

    static func offerTitle(for kind: EnrichmentKind, target: EnrichmentPushTarget) -> String {
        switch kind {
        case .sessionWarmup: return "Mobility prep"
        case .cooldown: return "Cool-down"
        case .betweenSetRest: return "Rest between sets"
        case .exerciseWarmupSets: return "Warm-up sets"
        case .stationTransition: return stationTransitionTitle
        }
    }

    static func activitiesDetail(
        _ activities: [EnrichmentActivityPref],
        target: EnrichmentPushTarget = .garmin
    ) -> String {
        guard !activities.isEmpty else { return "No activities set — add them in Settings." }
        let openLabel = target == .apple ? "until tap" : "until Lap"
        return activities.map { activity in
            guard let durationSec = activity.durationSec, durationSec > 0 else {
                return "\(activity.name) · \(openLabel)"
            }
            return "\(activity.name) · \(durationSec)s"
        }
        .joined(separator: ", ")
    }

    static func restDetail(
        _ prefs: BetweenSetRestPrefs,
        target: EnrichmentPushTarget = .garmin
    ) -> String {
        if prefs.restOpen {
            switch target {
            case .apple: return "Open rest between sets"
            case .garmin: return "Rest until Lap between sets"
            }
        }
        guard let restSec = prefs.restSec, restSec > 0 else {
            return "No rest length set — add one in Settings."
        }
        return "\(restSec)s between sets"
    }

    /// AMA-2423 — Transitions row detail, parallel to `restDetail`.
    static func stationTransitionDetail(
        _ prefs: StationTransitionPrefs,
        target: EnrichmentPushTarget = .garmin
    ) -> String {
        if prefs.transitionOpen {
            switch target {
            case .apple: return "Open transition between stations"
            case .garmin: return "Transition until Lap between stations"
            }
        }
        guard let transitionSec = prefs.transitionSec, transitionSec > 0 else {
            return "No transition length set — add one in Settings."
        }
        return "\(transitionSec)s between stations"
    }

    static func liveRestDetail(
        restOpen: Bool,
        restSec: Int,
        target: EnrichmentPushTarget
    ) -> String {
        if restOpen {
            switch target {
            case .apple: return "Open rest between sets/rounds"
            case .garmin: return "Lap button press between sets/rounds"
            }
        }
        return "Timed \(restSec)s between sets/rounds"
    }

    /// AMA-2423 — live Transitions row detail while the sheet is open, parallel
    /// to `liveRestDetail`. Copy calls out "stations" (moving between machines),
    /// not "sets/rounds" — this is not a sit-down rest.
    static func liveTransitionDetail(
        transitionOpen: Bool,
        transitionSec: Int,
        target: EnrichmentPushTarget
    ) -> String {
        if transitionOpen {
            switch target {
            case .apple: return "Open transition between stations"
            case .garmin: return "Lap button press between stations"
            }
        }
        return "Timed \(transitionSec)s between stations"
    }

    static func warmupSetsDetail(_ defaults: [WarmupSetDefault], exerciseCount: Int) -> String {
        let reps = defaults.map { "\($0.reps)" }.joined(separator: " · ")
        let noun = exerciseCount == 1 ? "exercise" : "exercises"
        return "\(defaults.count) warm-up sets (\(reps) reps) on \(exerciseCount) \(noun)"
    }

    /// Seed the sheet's open-rest toggle.
    /// Apple: Lap-equivalent is Open rest — always ON for this sheet unless
    /// delivery prefs are explicitly ``omit`` (AMA-2363). Timed delivery prefs
    /// must not silently force Timed 60s here.
    static func initialRestOpen(
        standing: BetweenSetRestPrefs,
        target: EnrichmentPushTarget
    ) -> Bool {
        switch target {
        case .garmin:
            return standing.restOpen
        case .apple:
            if AppleWatchDeliveryPrefsStore.hasConfigured,
               AppleWatchDeliveryPrefsStore.current.restMode == .omit {
                return false
            }
            return true
        }
    }

    /// Configured Apple `rest_mode=omit` means no rest steps — do not offer inject.
    static func shouldSkipRestOffer(target: EnrichmentPushTarget) -> Bool {
        guard target == .apple, AppleWatchDeliveryPrefsStore.hasConfigured else { return false }
        return AppleWatchDeliveryPrefsStore.current.restMode == .omit
    }

    /// AMA-2423 — seed the sheet's Transitions open toggle. Apple always seeds
    /// **Open** when the row is checked (spec "Apple seed: Open when enabled")
    /// — the `rest_mode=omit` gate already excludes the whole offer upstream
    /// (`shouldSkipRestOffer`), so no separate omit check is needed here.
    static func initialTransitionOpen(
        standing: StationTransitionPrefs,
        target: EnrichmentPushTarget
    ) -> Bool {
        switch target {
        case .garmin: return standing.transitionOpen
        case .apple: return true
        }
    }

    // MARK: - AMA-2378 v2 — enhance sheet mono summaries + copy-lock
    // Design 2026-08-04 `make-it-watch-ready-v2-design.md` §Surfaces 1–5 +
    // §Validation matrix (copy-lock). Additive: v1 APIs above are untouched.

    /// v2 sheet intro (rows-as-doors) — AMA-2453: derived plan, library unchanged.
    static let sheetIntroV2 = "Tap a row to shape what goes on your watch — your library workout stays as you wrote it."

    /// Footnote under offer rows — watch builds FIT/plan at handoff, not a library edit.
    static let sheetFootnoteV2 = "Your watch builds the file when you download — these choices don’t change your saved workout."

    /// Garmin defer copy when a derived plan cannot ride the push body (AMA-2453).
    static let garminDerivedPlanDeferNote =
        "Watch-ready extras aren’t on Garmin yet — your library workout is unchanged; FIT uses authored structure until delivery accepts a derived plan."

    /// Sequence builder screen header suffix — mobility runs first, cooldown runs last.
    static let mobilityHeaderSuffix = "RUNS BEFORE THE FIRST LIFT"
    static let cooldownHeaderSuffix = "RUNS AFTER THE LAST SET"

    /// Enhance-sheet "Cooldown" row summary suffix — shorter than the sequence
    /// builder's own header suffix (`cooldownHeaderSuffix`); the two are locked
    /// separately because the design uses different phrasing per surface.
    static let cooldownRowSummarySuffix = "AFTER THE LAST SET"

    /// Open-target stepper caption (sequence builder + ramp editor).
    static let openStepperCaption = "NO TARGET — END ON TAP / CROWN"

    /// Per-exercise warm-up pick screen header hint.
    static let warmupPickHint = "NOT EVERY LIFT NEEDS A RAMP"

    /// Per-exercise pick row caption when that exercise's ramp toggle is off.
    static let warmupOffCaption = "STRAIGHT TO WORKING SETS"

    /// Per-exercise warm-up pick screen header meta — `N OF M EXERCISES · <hint>`.
    static func warmupPickHeaderMeta(enabledCount: Int, total: Int) -> String {
        let noun = total == 1 ? "EXERCISE" : "EXERCISES"
        return "\(enabledCount) OF \(total) \(noun) · \(warmupPickHint)"
    }

    /// Ramp editor header meta — `N WARM-UP SETS → THEN YOUR K WORKING SETS`.
    /// `workingSetCount` is `nil` when the ingest draft never declared one —
    /// the header reads "YOUR WORKING SETS" rather than inventing a number.
    static func rampEditorHeaderMeta(setCount: Int, workingSetCount: Int?) -> String {
        let setsLabel = "\(setCount) WARM-UP SET\(setCount == 1 ? "" : "S")"
        guard let workingSetCount, workingSetCount > 0 else {
            return "\(setsLabel) → THEN YOUR WORKING SETS"
        }
        let workingLabel = "YOUR \(workingSetCount) WORKING SET\(workingSetCount == 1 ? "" : "S")"
        return "\(setsLabel) → THEN \(workingLabel)"
    }

    /// Watch preview band caption — an exercise with no ramp, straight to working sets.
    static let noWarmupsYourCall = "NO WARM-UPS — YOUR CALL"

    /// Ramp editor inline honesty note — WorkoutKit has no reps-with-load goal
    /// (AMA-2347); loads never render on the ramp, only intensity `%` notes.
    static let loadsOffRampNote = "Loads stay off the ramp — the watch shows % notes only."

    static func sequenceHeaderSuffix(for kind: EnrichmentSequenceKind) -> String {
        switch kind {
        case .mobility: return mobilityHeaderSuffix
        case .cooldown: return cooldownHeaderSuffix
        }
    }

    // MARK: One-activity goal formatting

    /// `mm:ss` with no unit suffix — the sequence-summary form (`2:00`), distinct
    /// from the sequence-builder stepper's own `2:00 MIN` display.
    static func formatMinSec(_ seconds: Int) -> String {
        let clamped = max(seconds, 0)
        return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
    }

    /// One activity's declared goal, mono caps summary form. Reads `goal` when
    /// present; else falls back to the v1 `durationSec` projection — `nil` →
    /// `OPEN`, otherwise the timed label.
    static func activityGoalLabel(goal: ActivityGoal?, durationSec: Int?) -> String {
        guard let goal else {
            guard let durationSec, durationSec > 0 else { return "OPEN" }
            return formatMinSec(durationSec)
        }
        switch goal.kind {
        case .time: return formatMinSec(goal.value ?? durationSec ?? 0)
        case .distance: return "\(goal.value ?? 0) M"
        case .cals: return "\(goal.value ?? 0) CAL"
        case .open: return "OPEN"
        }
    }

    /// `NAME GOAL` — one sequence step's mono label, e.g. `SKI ERG 500 M`.
    static func activitySummaryLabel(name: String, goal: ActivityGoal?, durationSec: Int?) -> String {
        "\(name.uppercased()) \(activityGoalLabel(goal: goal, durationSec: durationSec))"
    }

    // MARK: Duration estimate math (design §Surface 2 — sequence header `~X MIN`)

    /// Per-activity duration estimate in seconds. Time = literal value;
    /// Distance ≈ value/4 (meters → seconds heuristic); Cals ≈ value×4;
    /// Open ≈ 90s. Matches the design rig's estimate exactly (not a real pace
    /// model — good enough for a rough sequence-length readout).
    static func durationEstimateSeconds(goal: ActivityGoal?, durationSec: Int?) -> Int {
        guard let goal else { return durationSec ?? 90 }
        switch goal.kind {
        case .time: return goal.value ?? durationSec ?? 90
        case .distance: return (goal.value ?? 0) / 4
        case .cals: return (goal.value ?? 0) * 4
        case .open: return 90
        }
    }

    static func sequenceDurationEstimateSeconds(_ activities: [EnrichmentActivity]) -> Int {
        activities.reduce(0) { $0 + durationEstimateSeconds(goal: $1.goal, durationSec: $1.durationSec) }
    }

    /// Rounded, not ceiling — mirrors the design rig's `Math.round(total / 60)`
    /// (a 500m + 2:00 sequence totals 245s, which reads `~4 MIN`, not `~5 MIN`).
    static func sequenceDurationEstimateMinutes(_ activities: [EnrichmentActivity]) -> Int {
        Int((Double(sequenceDurationEstimateSeconds(activities)) / 60).rounded())
    }

    // MARK: Sequence summaries (design §Surface 1 rows-as-doors, §Surfaces 2/5 headers)

    /// AMA-2408 — routes through `EnrichmentRowSummary`. Legacy callers that
    /// ignored OFF still get a non-nil string; prefer `EnrichmentRowSummary.sequence`.
    static func sequenceSummary(_ activities: [EnrichmentActivity], suffix: String? = nil) -> String {
        if let line = EnrichmentRowSummary.sequence(isOn: true, activities: activities) {
            guard let suffix else { return line }
            // Cooldown row suffix is dropped in the scaling ladder (panel 2/3);
            // keep it only for the sequence-builder header path via sequenceHeaderMeta.
            _ = suffix
            return line
        }
        return "NO STEPS ADDED"
    }

    /// `N STEPS · ~X MIN · <suffix>` — the sequence builder screen's own header meta.
    static func sequenceHeaderMeta(_ activities: [EnrichmentActivity], kind: EnrichmentSequenceKind) -> String {
        let stepsLabel = "\(activities.count) STEP\(activities.count == 1 ? "" : "S")"
        let minutes = sequenceDurationEstimateMinutes(activities)
        return "\(stepsLabel) · ~\(minutes) MIN · \(sequenceHeaderSuffix(for: kind))"
    }

    // MARK: Warm-up sets summaries (design §Surface 1 row + §Surface 3 pick screen)

    /// AMA-2408 — positive digest for pick-screen a11y. Never emits "SKIPPED".
    static func warmupExerciseTag(name: String, ramp: PerExerciseRamp?) -> String {
        let upperName = EnrichmentRowSummary.warmupDisplayName(name)
        guard let ramp, ramp.enabled, !ramp.sets.isEmpty else {
            return "\(upperName) · \(warmupOffCaption)"
        }
        return "\(upperName) · RAMP ×\(ramp.sets.count)"
    }

    /// AMA-2408 — routes through `EnrichmentRowSummary` scaling ladder.
    static func warmupSetsSummaryV2(_ exercises: [(name: String, ramp: PerExerciseRamp?)]) -> String {
        let names = exercises.map(\.name)
        let ramps = exercises.compactMap(\.ramp)
        return EnrichmentRowSummary.warmups(
            isOn: true,
            candidateNames: names,
            ramps: ramps
        ) ?? EnrichmentRowSummary.noRampsYet
    }

    /// One ramp set's mono label for the per-exercise pick screen digest
    /// (`8 REPS`, `1:00 MIN`, `15 CAL`, `OPEN · END ON TAP`).
    static func rampSetLabel(_ set: RampSet) -> String {
        switch set.kind {
        case .reps: return "\(set.value ?? 0) REPS"
        case .time: return "\(formatMinSec(set.value ?? 0)) MIN"
        case .cals: return "\(set.value ?? 0) CAL"
        case .open: return "OPEN · END ON TAP"
        }
    }

    /// Per-exercise pick screen ramp digest — `warmupOffCaption` when the ramp
    /// is off, `DEFAULT RAMP` when on with no declared sets, else the
    /// set-by-set digest joined with ` → ` (e.g. `8 REPS → 5 REPS`).
    static func perExerciseRampDigest(_ ramp: PerExerciseRamp?) -> String {
        guard let ramp, ramp.enabled else { return warmupOffCaption }
        guard !ramp.sets.isEmpty else { return "DEFAULT RAMP" }
        return ramp.sets.map(rampSetLabel).joined(separator: " → ")
    }
}

/// Mobility prep vs cooldown share one `SequenceScreen` anatomy — only copy
/// differs (design §Surface 2 / §Surface 5). Distinct from `EnrichmentKind`
/// (which also covers `betweenSetRest` / `exerciseWarmupSets`, not sequences).
/// `Hashable` so the enhance sheet can drive `navigationDestination(item:)`.
enum EnrichmentSequenceKind: String, Hashable, Sendable {
    case mobility, cooldown
}
