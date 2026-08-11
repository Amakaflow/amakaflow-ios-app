//
//  AppleWatchPreviewReveal.swift
//  AmakaFlow
//
//  AMA-2408 — map BuildReveal beats back onto PreviewSections without collapsing
//  identical warm-up rows (two × "Warm-up set" / "10 REPS").
//

import Foundation

enum AppleWatchPreviewReveal {
    /// Rebuild banded sections from the beats the reveal controller has shown.
    static func sections(
        from sections: [PreviewSection],
        shownBeats: [BuildBeat]
    ) -> [PreviewSection] {
        var out: [PreviewSection] = []
        var currentBand: PreviewSection?
        var currentSteps: [PreviewStep] = []

        func flush() {
            guard let band = currentBand else { return }
            out.append(
                PreviewSection(
                    accent: band.accent,
                    band: band.band,
                    tag: band.tag,
                    steps: currentSteps,
                    caption: band.caption
                )
            )
            currentBand = nil
            currentSteps = []
        }

        for beat in shownBeats {
            switch beat.kind {
            case .band:
                flush()
                if let match = sections.first(where: { $0.band == beat.label }) {
                    currentBand = match
                    currentSteps = []
                }
            case .row:
                if let band = currentBand,
                   let step = nextUnusedStep(
                    in: band.steps,
                    matching: beat,
                    alreadyShown: currentSteps
                   ) {
                    currentSteps.append(step)
                }
            default:
                break
            }
        }
        flush()
        return out
    }

    /// Next unused step for this beat. Identical title+detail ramps must each
    /// consume a distinct step — never rebind `.first(where:)`.
    static func nextUnusedStep(
        in steps: [PreviewStep],
        matching beat: BuildBeat,
        alreadyShown: [PreviewStep]
    ) -> PreviewStep? {
        let detail = beat.detail?.isEmpty == true ? nil : beat.detail
        let usedNumbers = Set(alreadyShown.map(\.number))
        let unused = steps.filter { !usedNumbers.contains($0.number) }
        return unused.first(where: {
            $0.title == beat.name && $0.detail == detail
        }) ?? unused.first(where: { $0.title == beat.name })
    }
}
