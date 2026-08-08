//
//  WatchItemSheet.swift
//  AmakaFlow
//
//  AMA-2386 / AMA-2388: tap a scheduled/queued watch row → edit readiness & replace.
//  v2: ON THE WATCH card, always-pinned CTA, EDITED chips, FROM YOUR LIBRARY row.
//

import SwiftUI

struct WatchItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WatchItemViewModel
    @State private var route: Route?
    var onRemove: (() -> Void)?
    var onOpenWorkout: (() -> Void)?

    private enum Route: Hashable {
        case sequence(EnrichmentSequenceKind)
        case warmupPick
    }

    init(
        viewModel: WatchItemViewModel,
        onRemove: (() -> Void)? = nil,
        onOpenWorkout: (() -> Void)? = nil,
        onSeeSteps: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onRemove = onRemove
        self.onOpenWorkout = onOpenWorkout
        // onSeeSteps retained for call-site compat; overlay is owned by the sheet.
        _ = onSeeSteps
    }

    var body: some View {
        NavigationStack {
            ZStack {
                sheetChrome
                    .accessibilityHidden(viewModel.showingStepsOverlay)
                    .allowsHitTesting(!viewModel.showingStepsOverlay)
                if viewModel.showingStepsOverlay {
                    WatchItemDeliveredStepsOverlay(
                        stepCount: viewModel.stepCount,
                        sections: viewModel.stepSections
                    ) {
                        viewModel.showingStepsOverlay = false
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(WatchItemCopy.done) { dismiss() }
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.lime)
                        .accessibilityIdentifier("af_watchitem_done")
                        .accessibilityHidden(viewModel.showingStepsOverlay)
                        .disabled(viewModel.showingStepsOverlay)
                }
            }
            .navigationDestination(item: $route) { route in
                switch route {
                case .sequence(let kind):
                    EnrichmentSequenceScreen(
                        activities: kind == .mobility
                            ? viewModel.mobilityBinding()
                            : viewModel.cooldownBinding(),
                        kind: kind
                    )
                case .warmupPick:
                    EnrichmentWarmupPickScreen(
                        ramps: viewModel.rampsBinding(),
                        exercises: viewModel.warmupExerciseNames
                    )
                }
            }
        }
        // Sheet sits above the app-root toast host — mount one here so
        // Replace morph + Save sequence/cooldown confirmations are visible.
        .ddToastHost()
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("af_watchitem_sheet")
    }

    private var sheetChrome: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    WatchItemOnWatchCard(viewModel: viewModel)
                    Text(WatchItemCopy.sectionLabel)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(.top, 13)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("af_watchitem_section")

                    doorRow(.mobility, title: WatchItemCopy.mobilityTitle)
                    doorRow(.warmups, title: WatchItemCopy.warmupsTitle)
                    restRow
                    doorRow(.cooldown, title: WatchItemCopy.cooldownTitle)

                    WatchItemLibraryRow(viewModel: viewModel, onOpenWorkout: onOpenWorkout)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            WatchItemPinnedActionBar(viewModel: viewModel, onRemove: onRemove)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(viewModel.isApple ? DailyDriver.card2 : DailyDriver.blue)
                    .frame(width: 34, height: 34)
                Image(systemName: "applewatch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.title)
                    .ddDisplayText(17, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(viewModel.stateLine)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(stateLineColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("af_watchitem_header")
    }

    private var stateLineColor: Color {
        if viewModel.isApple { return DailyDriver.foregroundDim }
        if viewModel.garminState == .waiting { return DailyDriver.amber }
        return DailyDriver.lime
    }

    private func doorRow(_ row: WatchItemReadinessRow, title: String) -> some View {
        let enabled = viewModel.tracker.draft.isEnabled(row)
        let edited = viewModel.isEdited(row)
        return HStack(spacing: 12) {
            Button {
                route = doorRoute(for: row)
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(title)
                                .ddDisplayText(14.5, weight: .bold)
                                .foregroundColor(DailyDriver.foreground)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DailyDriver.foregroundDim)
                            if edited {
                                editedChip
                                    .accessibilityIdentifier("af_watchitem_row_\(row.rawValue)_edited")
                            }
                        }
                        Text(viewModel.summary(for: row))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(edited ? DailyDriver.amber : DailyDriver.foregroundMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isReplacing)
            .accessibilityHint("Opens the \(title) configurator")

            Toggle("", isOn: Binding(
                get: { enabled },
                set: { viewModel.setEnabled(row, $0) }
            ))
            .labelsHidden()
            .accessibilityLabel(title)
            .tint(DailyDriver.lime)
            .disabled(viewModel.isReplacing)
            .accessibilityIdentifier("af_watchitem_row_\(row.rawValue)_toggle")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(edited ? DailyDriver.amber.opacity(0.55) : DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 8)
        .accessibilityIdentifier("af_watchitem_row_\(row.rawValue)")
    }

    private var editedChip: some View {
        Text(WatchItemCopy.editedChip)
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundColor(DailyDriver.amber)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(
                Capsule().stroke(DailyDriver.amber, lineWidth: 1)
            )
    }

    private var restRow: some View {
        let enabled = viewModel.restEnabled
        let edited = viewModel.isEdited(.rest)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(WatchItemCopy.restTitle)
                            .ddDisplayText(14.5, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                        if edited {
                            editedChip
                                .accessibilityIdentifier("af_watchitem_row_rest_edited")
                        }
                    }
                    Text(viewModel.summary(for: .rest))
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(edited ? DailyDriver.amber : DailyDriver.foregroundMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { viewModel.setEnabled(.rest, $0) }
                ))
                .labelsHidden()
                .accessibilityLabel(WatchItemCopy.restTitle)
                .tint(DailyDriver.lime)
                .disabled(viewModel.isReplacing)
                .accessibilityIdentifier("af_watchitem_row_rest_toggle")
            }

            if enabled {
                Picker("", selection: viewModel.restOpenBinding()) {
                    Text(WorkoutEnrichmentPushCopy.restOpenSegmentLabel(target: viewModel.enrichmentTarget))
                        .tag(true)
                    Text(WorkoutEnrichmentPushCopy.restTimedSegmentLabel)
                        .tag(false)
                }
                .pickerStyle(.segmented)
                .tint(DailyDriver.lime)
                .disabled(viewModel.isReplacing)
                .accessibilityIdentifier("af_watchitem_rest_open")

                if !viewModel.restOpen {
                    Stepper(
                        "\(viewModel.restSec)s",
                        value: viewModel.restSecBinding(),
                        in: WorkoutEnrichmentPushCopy.restSecRange,
                        step: 15
                    )
                    .font(.system(size: 11))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .monospacedDigit()
                    .disabled(viewModel.isReplacing)
                    .accessibilityIdentifier("af_watchitem_rest_sec")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(edited ? DailyDriver.amber.opacity(0.55) : DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 8)
        .accessibilityIdentifier("af_watchitem_row_rest")
    }

    private func doorRoute(for row: WatchItemReadinessRow) -> Route? {
        switch row {
        case .mobility: return .sequence(.mobility)
        case .cooldown: return .sequence(.cooldown)
        case .warmups: return .warmupPick
        case .rest: return nil
        }
    }
}
