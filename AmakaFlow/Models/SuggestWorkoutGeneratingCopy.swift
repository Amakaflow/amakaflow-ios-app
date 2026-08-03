//
//  SuggestWorkoutGeneratingCopy.swift
//  AmakaFlow
//
//  AMA-2371: staged-progress copy for the "Generating your workout" screen
//  (spec 2026-08-02 send/enhance flow iOS UI redesign).
//
//  Pure strings so the cycling-step and failure-fine-print copy can be
//  unit-tested without hosting SwiftUI.
//

import Foundation

enum SuggestWorkoutGeneratingCopy {
    /// Cycling step text shown while the coach builds a session. Loops for
    /// as long as generation takes — there is no guarantee it finishes by
    /// the last step, so the view repeats the sequence rather than stalling
    /// on "Building blocks".
    static let steps = [
        "Reading signals",
        "Weighing recovery",
        "Choosing focus",
        "Building blocks"
    ]

    /// Honest failure framing — replaces the old threatening
    /// "No fallback workout will be shown if generation fails."
    static let failureFinePrint = "If it fails you'll see exactly why — we never swap in a canned workout."

    /// `STEP n OF total · USUALLY UNDER 20S` progress label. `step` is
    /// clamped into `1...total` so an out-of-range index can't render
    /// something like "STEP 0 OF 4".
    static func stepProgressLabel(step: Int, total: Int) -> String {
        let clampedTotal = max(total, 1)
        let clampedStep = min(max(step, 1), clampedTotal)
        return "STEP \(clampedStep) OF \(clampedTotal) · USUALLY UNDER 20S"
    }
}
