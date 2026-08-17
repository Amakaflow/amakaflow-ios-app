//
//  MotionTokens.swift
//  AmakaFlow
//
//  AMA-2383 — single source for DD Motion durations/curves. No magic numbers
//  in views; every animation in this ticket references MotionTokens.
//  Spec: design-handoff/MOTION.md
//

import SwiftUI

enum MotionTokens {
    // MARK: Durations (seconds)

    static let fast: Double = 0.160
    static let base: Double = 0.280
    static let slow: Double = 0.420

    /// Per-beat reveal stagger in the build engine.
    static let buildStagger: Double = 0.130
    /// Initial delay before the first beat (matches prototype kick).
    static let buildKick: Double = 0.420
    /// Brief pause after last beat before CTA lands.
    static let buildDoneSettle: Double = 0.260
    /// Theatrical scripted builds (local data) must finish within this cap.
    static let theatricalCap: Double = 2.0

    /// Mono detail wipe: 500ms ease-out-quart, delayed 120ms after row enters.
    static let wipeDuration: Double = 0.500
    static let wipeDelay: Double = 0.120
    /// Chip pop after its row.
    static let chipDelay: Double = 0.280
    /// Row container slide duration (prototype 260ms).
    static let rowSlide: Double = 0.260
    /// Number pop spring duration (prototype 320ms).
    static let numberPop: Double = 0.320
    /// CTA color settle after done.
    static let ctaColorSettle: Double = 0.350

    // MARK: List reveal (AMA-2443 slice 6)

    /// Per-row entrance stagger — 55ms/row (`screens-exsearch.jsx` header).
    static let rowStagger: Double = 0.055

    /// Only the rows on screen at open are staggered.
    ///
    /// Two reasons, both load-bearing. Uncapped, row 60 of a search result would
    /// wait 3.3s to appear. And rows past the first screenful are realized lazily
    /// during scrolling, so animating them would fire an entrance mid-scroll on
    /// content the athlete is already looking at. Beyond this index the reveal is
    /// off entirely, not merely instant.
    static let maxStaggeredRows = 8

    /// Entrance delay for the row at `index`, or nil when it should not animate.
    static func staggerDelay(index: Int) -> Double? {
        guard index >= 0, index < maxStaggeredRows else { return nil }
        return Double(index) * rowStagger
    }

    // MARK: Toast

    static let toastIn: Double = 0.320
    static let toastHold: Double = 1.800
    static let toastHoldWithAction: Double = 4.000
    static let toastOut: Double = 0.240
    static let toastInOffsetY: CGFloat = -24
    static let toastOutOffsetY: CGFloat = -18
    /// Top inset under status bar / Dynamic Island (tune on device).
    static let toastTopInset: CGFloat = 54

    // MARK: Animations

    /// ease-out-quart `cubic-bezier(.25, 1, .5, 1)`
    static func easeOutQuart(duration: Double) -> Animation {
        .timingCurve(0.25, 1, 0.5, 1, duration: duration)
    }

    /// General spring — `cubic-bezier(.34, 1.4, .64, 1)` equivalent.
    static var spring: Animation {
        .spring(response: 0.35, dampingFraction: 0.8)
    }

    /// Toast drop-in spring (slightly snappier).
    static var toastSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.72)
    }

    /// Compute per-beat stagger so a scripted build of `beatCount` finishes
    /// within `theatricalCap` (honest-progress: never animate slower than data).
    static func cappedStagger(beatCount: Int) -> Double {
        guard beatCount > 0 else { return buildStagger }
        let budget = max(0.01, theatricalCap - buildKick - buildDoneSettle)
        let capped = budget / Double(beatCount)
        return min(buildStagger, capped)
    }
}
