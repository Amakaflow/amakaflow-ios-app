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
    static func offerTitle(for kind: EnrichmentKind, target: EnrichmentPushTarget) -> String {
        switch kind {
        case .sessionWarmup: return "Add mobility prep"
        case .cooldown: return "Cool-down"
        case .betweenSetRest:
            switch target {
            case .apple: return "Add rest (Open or timed)"
            case .garmin: return "Add rest (Lap or timed)"
            }
        case .exerciseWarmupSets: return "Exercise warm-up sets"
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

    static func restOpenToggleTitle(target: EnrichmentPushTarget) -> String {
        switch target {
        case .apple: return "Open rest (no timer)"
        case .garmin: return "Lap button press (no timer)"
        }
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
