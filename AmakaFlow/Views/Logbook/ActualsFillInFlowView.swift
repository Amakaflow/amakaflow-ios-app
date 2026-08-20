//
//  ActualsFillInFlowView.swift
//  AmakaFlow
//
//  AMA-2473: the logbook IS the fill-in. There is no longer a mode door and no
//  Quick confirm screen.
//
//  It used to open `ActualsModeSelectView` — "Quick — as planned / adjust" vs
//  "Set by set — the logbook" — and Quick then asked the athlete to declare
//  the session AGAIN as SETS/REPS steppers after they had already logged it.
//  That was the double step David reported, and the screen where a six-move
//  workout came back as "1 OF 1 CONFIRMED". Entry is the log now, so the
//  second declaration has nothing left to do.
//
//  `startInQuick` goes with it — nothing deep-linked to Quick. So do
//  `dismissOnSave` and `onWriteBackDecoration`: both were fired only by the
//  Quick screen's own machinery and were ALREADY never called on the
//  set-by-set route, so they are inert here rather than a dropped feature.
//  Strava write-back decoration therefore has no home on this flow — that
//  needs re-homing onto the logbook as its own piece of work.
//

import SwiftUI

/// Opens the logbook for a session. Kept as a wrapper because callers pass
/// `onSaved` / `onBack` / unverify + Strava hooks that the logbook itself
/// does not own.
struct ActualsFillInFlowView: View {
    @ObservedObject var viewModel: ActualsFillInViewModel
    var onSaved: (ActualsFillInSession) -> Void = { _ in }
    var onBack: (() -> Void)?
    var presentsVerifiedOnSave: Bool = true
    var onUnverify: (() -> Void)?

    @State private var logbookVM: LogbookViewModel?

    var body: some View {
        Group {
            if let logbookVM {
                LogbookView(
                    viewModel: logbookVM,
                    // Pass the optional straight through: wrapping it in a
                    // closure made it always non-nil, so LogbookView's own
                    // dismiss() fallback never ran for callers that pass none.
                    onBack: onBack,
                    onSaved: onSaved,
                    onUnverify: onUnverify,
                    presentsVerifiedOnSave: presentsVerifiedOnSave
                )
            } else {
                ProgressView()
                    .task { bootstrapLogbook() }
            }
        }
    }

    private func bootstrapLogbook() {
        guard logbookVM == nil else { return }
        let draft = LogbookSeeding.draft(
            from: viewModel.session,
            mode: .after,
            ghostLookup: ActualsRepository()
        )
        logbookVM = LogbookViewModel(
            draft: draft,
            draftRepository: LogDraftRepository(),
            actualsRepository: ActualsRepository(),
            weightUnit: .stored
        )
    }
}
