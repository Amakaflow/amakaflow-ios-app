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

    static func offerTitle(for kind: EnrichmentKind, target: EnrichmentPushTarget) -> String {
        switch kind {
        case .sessionWarmup: return "Mobility prep"
        case .cooldown: return "Cool-down"
        case .betweenSetRest: return "Rest between sets"
        case .exerciseWarmupSets: return "Warm-up sets"
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
}
