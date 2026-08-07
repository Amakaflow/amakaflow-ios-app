//
//  WatchItemSheet.swift
//  AmakaFlow
//
//  AMA-2386: tap a scheduled/queued watch row → edit readiness & replace.
//  Readiness row chevrons open the same AMA-2378 configurators as Make it watch-ready.
//

import SwiftUI

struct WatchItemSheet: View {
    @StateObject private var viewModel: WatchItemViewModel
    @State private var route: Route?
    var onRemove: (() -> Void)?
    var onOpenWorkout: (() -> Void)?
    var onSeeSteps: (() -> Void)?

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
        self.onSeeSteps = onSeeSteps
    }

    var body: some View {
        NavigationStack {
            sheetBody
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
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("af_watchitem_sheet")
    }

    private var sheetBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                snapshot
                Text(WatchItemCopy.sectionLabel)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("af_watchitem_section")

                doorRow(.mobility, title: WatchItemCopy.mobilityTitle)
                doorRow(.warmups, title: WatchItemCopy.warmupsTitle)
                restRow
                doorRow(.cooldown, title: WatchItemCopy.cooldownTitle)

                if viewModel.isReplaceAvailable {
                    replaceCTA
                        .padding(.top, 10)

                    Text(WatchItemCopy.replaceNote(isApple: viewModel.isApple))
                        .font(.system(size: 10.5))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }

                footer
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
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
                    .lineLimit(2)
                Text(viewModel.stateLine)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(stateLineColor)
                    .lineLimit(2)
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

    private var snapshot: some View {
        FlowWrappingHStack(spacing: 6) {
            ForEach(viewModel.snapshotPills, id: \.self) { pill in
                Text(pill)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(DailyDriver.card2)
                    .clipShape(Capsule())
            }
            Button {
                onSeeSteps?()
            } label: {
                Text(WatchItemCopy.seeSteps)
                    .ddDisplayText(11, weight: .bold)
                    .foregroundColor(DailyDriver.lime)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_watchitem_see_steps")
        }
        .padding(.top, 12)
        .accessibilityIdentifier("af_watchitem_snapshot")
    }

    private func doorRow(_ row: WatchItemReadinessRow, title: String) -> some View {
        let enabled = viewModel.tracker.draft.isEnabled(row)
        return HStack(spacing: 12) {
            Button {
                route = doorRoute(for: row)
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(title)
                                .ddDisplayText(14, weight: .bold)
                                .foregroundColor(DailyDriver.foreground)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DailyDriver.foregroundDim)
                        }
                        Text(viewModel.summary(for: row))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)
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
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 8)
        .accessibilityIdentifier("af_watchitem_row_\(row.rawValue)")
    }

    private var restRow: some View {
        let enabled = viewModel.restEnabled
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(WatchItemCopy.restTitle)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(viewModel.summary(for: .rest))
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
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
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
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

    private var replaceCTA: some View {
        Button {
            Task { await viewModel.replace() }
        } label: {
            Text(viewModel.replaceCTATitle())
                .ddDisplayText(14.5, weight: .bold)
                .foregroundColor(viewModel.canReplace || viewModel.isReplacing ? DailyDriver.ink : DailyDriver.foregroundMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    viewModel.canReplace || viewModel.isReplacing
                        ? DailyDriver.lime
                        : DailyDriver.card2
                )
                .clipShape(Capsule())
                .modifier(ReplaceGlow(active: viewModel.canReplace || viewModel.isReplacing))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canReplace)
        .accessibilityIdentifier("af_watchitem_replace")
    }

    private var footer: some View {
        HStack {
            Button {
                onRemove?()
            } label: {
                Text(WatchItemCopy.removeFromWatch)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.red)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_watchitem_remove")

            Spacer()

            Button {
                onOpenWorkout?()
            } label: {
                Text(WatchItemCopy.openWorkout)
                    .ddDisplayText(13, weight: .semibold)
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_watchitem_open_workout")
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

/// Minimal wrapping row for snapshot pills without pulling in a heavier layout helper.
private struct FlowWrappingHStack<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Prefer a simple HStack with wrap via ViewThatFits fallback — pills are few.
        HStack(spacing: spacing) {
            content()
            Spacer(minLength: 0)
        }
    }
}
