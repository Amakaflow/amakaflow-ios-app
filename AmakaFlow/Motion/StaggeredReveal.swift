//
//  StaggeredReveal.swift
//  AmakaFlow
//
//  AMA-2443 slice 6 — 55ms/row list entrance (`screens-exsearch.jsx` header).
//

import SwiftUI

/// Fades and lifts a row into place, offset by its position in the list.
///
/// `generation` is what re-arms the reveal: bump it when the list's *content*
/// changes (a new query, a category drill-in) and the visible rows animate in
/// again. Rows past `MotionTokens.maxStaggeredRows` never animate, which is what
/// keeps a lazily-realized row from playing an entrance mid-scroll.
struct StaggeredReveal: ViewModifier {
    let index: Int
    let generation: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var delay: Double? {
        MotionTokens.staggerDelay(index: index)
    }

    func body(content: Content) -> some View {
        if let delay, !reduceMotion {
            content
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 6)
                .task(id: generation) {
                    revealed = false
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    withAnimation(MotionTokens.easeOutQuart(duration: MotionTokens.base)) {
                        revealed = true
                    }
                }
        } else {
            // Reduce Motion, or past the cap: the row is simply there. No
            // delayed opacity either — a fade-in is still motion to some people,
            // and a list that assembles itself is the thing being opted out of.
            content
        }
    }
}

/// Drill-in / drill-out for the picker's browse hierarchy.
///
/// Under Reduce Motion the slide is dropped and only the cross-fade remains,
/// so the hierarchy change stays legible without travel.
struct DrillInTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.transition(.opacity)
        } else {
            content.transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// Chip landing in the selection tray. Scale is travel, so Reduce Motion fades.
struct ChipLandTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.transition(.opacity)
        } else {
            content.transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }
}

extension View {
    /// Staggered list entrance. `generation` re-arms it when the list content changes.
    func staggeredReveal(index: Int, generation: Int) -> some View {
        modifier(StaggeredReveal(index: index, generation: generation))
    }

    func drillInTransition() -> some View {
        modifier(DrillInTransition())
    }

    func chipLandTransition() -> some View {
        modifier(ChipLandTransition())
    }
}
