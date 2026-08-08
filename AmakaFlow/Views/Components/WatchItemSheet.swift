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
                if viewModel.showingStepsOverlay {
                    WatchItemDeliveredStepsOverlay(
                        stepCount: viewModel.stepCount,
                        sections: viewModel.stepSections,
                        onClose: { viewModel.showingStepsOverlay = false }
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(WatchItemCopy.done) { dismiss() }
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.lime)
                        .accessibilityIdentifier("af_watchitem_done")
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
                    onWatchCard
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

                    libraryRow
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            pinnedActionBar
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(viewModel.isApple ? DailyDriver.card2 : Color(red: 0.35, green: 0.72, blue: 0.96))
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

    private var onWatchCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(viewModel.onWatchLabel)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.snapshotPills, id: \.self) { pill in
                        Text(pill)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(DailyDriver.card2)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 10)
            .padding(.bottom, 9)

            Button {
                viewModel.showingStepsOverlay = true
            } label: {
                HStack {
                    Text(WatchItemCopy.seeSteps(count: viewModel.stepCount))
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(DailyDriver.lime)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DailyDriver.lime)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_watchitem_see_steps")
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DailyDriver.border)
                    .frame(height: 1)
            }
        }
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 12)
        .accessibilityIdentifier("af_watchitem_onwatch_card")
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

    private var libraryRow: some View {
        Group {
            if viewModel.isLinkedToLibrary, let name = viewModel.libraryWorkoutTitle {
                Button {
                    onOpenWorkout?()
                } label: {
                    libraryRowContent(
                        title: WatchItemCopy.libraryRowTitle(workoutName: name),
                        muted: false
                    )
                }
                .buttonStyle(.plain)
            } else {
                libraryRowContent(title: WatchItemCopy.notLinked, muted: true)
            }
        }
        .accessibilityIdentifier("af_watchitem_library_row")
    }

    private func libraryRowContent(title: String, muted: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundDim)
            VStack(alignment: .leading, spacing: 1) {
                Text(WatchItemCopy.fromYourLibrary)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                Text(title)
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(muted ? DailyDriver.foregroundDim : DailyDriver.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(DailyDriver.border)
        )
    }

    private var pinnedActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DailyDriver.border)
                .frame(height: 1)
            VStack(spacing: 0) {
                Button {
                    Task { await viewModel.replace() }
                } label: {
                    Text(viewModel.replaceCTATitle())
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(
                            viewModel.canReplace || viewModel.isReplacing
                                ? DailyDriver.ink
                                : DailyDriver.foregroundDim
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            viewModel.canReplace || viewModel.isReplacing
                                ? DailyDriver.lime
                                : DailyDriver.card2
                        )
                        .clipShape(Capsule())
                        .modifier(ReplaceGlow(active: viewModel.canReplace))
                        .opacity(viewModel.isReplacing ? 0.75 : 1)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canReplace)
                .accessibilityIdentifier("af_watchitem_replace")

                Text(viewModel.applyNote)
                    .font(.system(size: 9.5))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 7)
                    .accessibilityIdentifier("af_watchitem_apply_note")

                Button {
                    onRemove?()
                } label: {
                    Text(WatchItemCopy.removeFromWatch)
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.red)
                }
                .buttonStyle(.plain)
                .padding(.top, 9)
                .accessibilityIdentifier("af_watchitem_remove")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .background(Color.black.opacity(0.92))
        }
    }
}

private struct ReplaceGlow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.ddLimeGlow()
        } else {
            content
        }
    }
}
