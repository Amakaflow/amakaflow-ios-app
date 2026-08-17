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

    @State private var revealed = false

    private var delay: Double? {
        MotionTokens.staggerDelay(index: index)
    }

    func body(content: Content) -> some View {
        if let delay {
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
            content
        }
    }
}

extension View {
    /// Staggered list entrance. `generation` re-arms it when the list content changes.
    func staggeredReveal(index: Int, generation: Int) -> some View {
        modifier(StaggeredReveal(index: index, generation: generation))
    }

    /// Drill-in / drill-out for the picker's browse hierarchy.
    func drillInTransition() -> some View {
        transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
