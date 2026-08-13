//
//  ActualsFillInFlowView.swift
//  AmakaFlow
//
//  AMA-2426: Fill in › mode select → Quick (unchanged) or Set-by-set logbook.
//

import SwiftUI

/// Wraps the shipped Quick fill-in with a mode door for the logbook.
struct ActualsFillInFlowView: View {
    @ObservedObject var viewModel: ActualsFillInViewModel
    var onSaved: (ActualsFillInSession) -> Void = { _ in }
    var onBack: (() -> Void)?
    var presentsVerifiedOnSave: Bool = true
    var dismissOnSave: Bool = true
    var onUnverify: (() -> Void)?
    var onWriteBackDecoration: ((StravaDecorationState) -> Void)?
    /// When true, skip mode select (e.g. deep-link straight to Quick).
    var startInQuick: Bool = false

    @State private var mode: ActualsLoggingMode?
    @State private var logbookVM: LogbookViewModel?

    var body: some View {
        Group {
            if let mode {
                switch mode {
                case .quick:
                    ActualsFillInView(
                        viewModel: viewModel,
                        onSaved: onSaved,
                        onBack: {
                            self.mode = nil
                            onBack?()
                        },
                        presentsVerifiedOnSave: presentsVerifiedOnSave,
                        dismissOnSave: dismissOnSave,
                        onUnverify: onUnverify,
                        onWriteBackDecoration: onWriteBackDecoration
                    )
                case .setBySet:
                    if let logbookVM {
                        LogbookView(
                            viewModel: logbookVM,
                            onBack: { self.mode = nil },
                            onSaved: onSaved
                        )
                    } else {
                        ProgressView()
                            .task { bootstrapLogbook() }
                    }
                }
            } else {
                ActualsModeSelectView(
                    subtitle: viewModel.session.subtitle,
                    onSelect: { selected in
                        if selected == .setBySet {
                            bootstrapLogbook()
                        }
                        mode = selected
                    },
                    onBack: onBack
                )
            }
        }
        .onAppear {
            if startInQuick {
                mode = .quick
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
        let unit: WeightUnit = {
            if let raw = UserDefaults.standard.string(forKey: DefaultsKey.userWeightUnit.rawValue),
               let parsed = WeightUnit(rawValue: raw) {
                return parsed
            }
            return .kg
        }()
        logbookVM = LogbookViewModel(
            draft: draft,
            draftRepository: LogDraftRepository(),
            actualsRepository: ActualsRepository(),
            weightUnit: unit
        )
    }
}
