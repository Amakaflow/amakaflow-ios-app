//
//  WatchItemViewModel+Preview.swift
//  AmakaFlow
//
//  AMA-2423: delivered-preview projection + recovery chip labels, split from
//  WatchItemViewModel.swift (SwiftLint file_length / type_body_length).
//

import Foundation

extension WatchItemViewModel {
    /// Rebuild the read-only preview from the newly delivered draft while
    /// preserving prior WORK bands (exercise rows the enrichment draft doesn't own).
    static func sectionsReflectingDelivered(
        readiness: WatchItemReadinessState,
        config: WatchItemConfigState,
        priorSections: [PreviewSection]
    ) -> [PreviewSection] {
        var sections: [PreviewSection] = []
        var nextNumber = 1

        func appendNumbered(_ title: String, detail: String? = nil, restChip: String? = nil) -> PreviewStep {
            let step = PreviewStep(
                number: nextNumber,
                title: title,
                detail: detail,
                restChip: restChip
            )
            nextNumber += 1
            return step
        }

        if readiness.mobilityEnabled {
            let names = config.mobilityActivities.map(\.name)
            let labels = names.isEmpty ? ["Mobility"] : names
            sections.append(
                PreviewSection(
                    accent: .mobility,
                    band: "MOBILITY",
                    tag: nil,
                    steps: labels.map { appendNumbered($0) }
                )
            )
        }

        if readiness.warmupsEnabled {
            let enabledRamps = config.perExerciseRamps.filter(\.enabled)
            for ramp in enabledRamps {
                let details = ["~40%", "~60%", "~80%"]
                sections.append(
                    PreviewSection(
                        accent: .work,
                        band: "WARM-UP · \(ramp.exerciseRef.uppercased())",
                        tag: nil,
                        steps: details.map { appendNumbered(PreviewStep.warmupSetTitle, detail: $0) }
                    )
                )
            }
        }

        // Recovery chips must follow the delivered readiness/config — never
        // stale prior chips after Rest is unchecked or timed/open is edited.
        // AMA-2423: Transitions wins where it is on, mirroring the backend's
        // per-block precedence (the two never stack on one band).
        let deliveredRestChip: String?
        if readiness.transitionEnabled {
            deliveredRestChip = transitionChipLabel(
                transitionOpen: config.transitionOpen,
                transitionSec: config.transitionSec
            )
        } else if readiness.restEnabled {
            deliveredRestChip = restChipLabel(restOpen: config.restOpen, restSec: config.restSec)
        } else {
            deliveredRestChip = nil
        }

        let workBands = priorSections.filter {
            $0.accent == .work && !$0.band.uppercased().contains("WARM")
        }
        for band in workBands {
            let lastIndex = band.steps.indices.last
            sections.append(
                PreviewSection(
                    accent: .work,
                    band: band.band,
                    tag: band.tag,
                    steps: band.steps.enumerated().map { index, step in
                        let chip = (index == lastIndex) ? deliveredRestChip : nil
                        return appendNumbered(step.title, detail: step.detail, restChip: chip)
                    },
                    caption: band.caption
                )
            )
        }

        if readiness.cooldownEnabled {
            let names = config.cooldownActivities.map(\.name)
            let labels = names.isEmpty ? ["Cooldown"] : names
            sections.append(
                PreviewSection(
                    accent: .cooldown,
                    band: "COOLDOWN",
                    tag: nil,
                    steps: labels.map { appendNumbered($0) }
                )
            )
        }

        return sections.isEmpty ? priorSections : sections
    }

    /// Matches plan-preview chips (`REST 60S` / `REST · YOU END IT`).
    static func restChipLabel(restOpen: Bool, restSec: Int) -> String {
        if restOpen { return PreviewStep.openRestChip }
        return "REST \(max(restSec, 1))S"
    }

    /// AMA-2423 — Transition counterpart, matching
    /// `WorkoutKitPlanStepSummary+Sections.restChipLabel`.
    static func transitionChipLabel(transitionOpen: Bool, transitionSec: Int) -> String {
        if transitionOpen { return PreviewStep.openTransitionChip }
        return "TRANSITION \(max(transitionSec, 1))S"
    }

    /// True when the delivered plan already carries a station-transition chip.
    static func hasTransitionChip(in sections: [PreviewSection]) -> Bool {
        sections.contains { section in
            section.steps.contains { step in
                guard let chip = step.restChip else { return false }
                return WatchItemRecoveryChip.isTransition(chip)
            }
        }
    }
}
