//
//  EnrichmentSequenceScreen.swift
//  AmakaFlow
//
//  AMA-2378 Task 4 — shared mobility/cooldown sequence builder (design
//  2026-08-04 `make-it-watch-ready-v2-design.md` §Surface 2 / §Surface 5).
//  One component parameterized by `EnrichmentSequenceKind` so mobility prep
//  and cooldown can never drift: ordered step cards (target segment +
//  stepper), an activity chip registry to append steps, and a Save CTA that
//  dismisses back to the enhance sheet (the binding is already live-updated,
//  same round-trip Task 3 proved with the stub).
//

import SwiftUI

struct EnrichmentSequenceScreen: View {
    @Binding var activities: [EnrichmentActivityPref]
    let kind: EnrichmentSequenceKind

    @Environment(\.dismiss) private var dismiss

    /// Design §Surface 2 — "combine several into an ordered sequence" chip
    /// registry. Fixed list per the design's open question (not yet fed from
    /// exercise-db conditioning entries).
    private static let activityRegistry = [
        "Ski erg", "Assault bike", "Jump rope", "Rower", "Treadmill", "Stretch flow"
    ]

    /// Builder card left rail — `SE.gray` in the prototype (screens-enhance2.jsx),
    /// used for both mobility and cooldown; the blue/gray split only applies to
    /// the watch-preview bands (§Surface 6), not this builder.
    private static let stepRailColor = DailyDriver.mobilityBand

    private var title: String {
        WorkoutEnrichmentPushCopy.offerTitle(
            for: kind == .mobility ? .sessionWarmup : .cooldown,
            target: .garmin
        )
    }

    private var saveLabel: String {
        kind == .mobility ? "Save sequence" : "Save cooldown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerMeta
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if activities.isEmpty {
                        Text("NO STEPS ADDED")
                            .font(Theme.Typography.mono)
                            .foregroundColor(DailyDriver.foregroundDim)
                            .accessibilityIdentifier("af_seq_screen_empty")
                    } else {
                        ForEach(Array(activities.enumerated()), id: \.element.id) { index, _ in
                            stepCard(index: index, activity: $activities[index])
                        }
                    }

                    activityChipsSection

                    Text("Each step becomes its own watch step, in this order. Open steps end when you tap.")
                        .font(.system(size: 10.5))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(.top, Theme.Spacing.xs)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 110)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            DDEditorSaveBar(title: saveLabel) { dismiss() }
                .accessibilityIdentifier("af_seq_save")
        }
        .preferredColorScheme(.dark)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("af_seq_screen_\(kind.rawValue)")
    }
}

// MARK: - Header

private extension EnrichmentSequenceScreen {
    var headerMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .ddDisplayText(22, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
            Text(WorkoutEnrichmentPushCopy.sequenceHeaderMeta(
                activities.map(EnrichmentActivity.init(pref:)),
                kind: kind
            ))
            .font(Theme.Typography.mono)
            .foregroundColor(DailyDriver.foregroundMuted)
            .accessibilityIdentifier("af_seq_header_meta")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Step cards

private extension EnrichmentSequenceScreen {
    func stepCard(index: Int, activity: Binding<EnrichmentActivityPref>) -> some View {
        let stepKind = resolvedKind(for: activity.wrappedValue)
        let value = currentValue(activity.wrappedValue, kind: stepKind)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(width: 16, alignment: .leading)
                Text(activity.wrappedValue.name)
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    removeStep(id: activity.wrappedValue.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(activity.wrappedValue.name)")
                .accessibilityIdentifier("af_seq_step_remove_\(index)")
            }

            HStack(spacing: 8) {
                Picker("", selection: kindBinding(activity)) {
                    ForEach(ActivityGoalKind.allCases, id: \.self) { candidate in
                        Text(candidate.sequenceSegmentLabel).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .tint(DailyDriver.lime)
                .accessibilityIdentifier("af_seq_step_target_\(index)")

                if stepKind == .open {
                    Text(WorkoutEnrichmentPushCopy.openStepperCaption)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 128, alignment: .leading)
                } else {
                    SequenceStepperPill(
                        text: stepperValueLabel(kind: stepKind, value: value),
                        onDecrement: { bump(activity, kind: stepKind, from: value, direction: -1) },
                        onIncrement: { bump(activity, kind: stepKind, from: value, direction: 1) }
                    )
                    .accessibilityIdentifier("af_seq_step_stepper_\(index)")
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.stepRailColor)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.bottom, 8)
        .accessibilityIdentifier("af_seq_step_\(index)")
    }
}

// MARK: - Activity chip registry (add a step)

private extension EnrichmentSequenceScreen {
    var activityChipsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("ADD A STEP — COMBINE AS MANY AS YOU LIKE")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .padding(.top, Theme.Spacing.sm)

            EditorV2FlowWrap {
                ForEach(Self.activityRegistry, id: \.self) { name in
                    Button {
                        addStep(named: name)
                    } label: {
                        Text(name)
                            .ddDisplayText(12, weight: .semibold)
                            .foregroundColor(DailyDriver.foreground)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(DailyDriver.card))
                            .overlay(Capsule().stroke(DailyDriver.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_seq_add_\(activityChipSlug(name))")
                }
            }
        }
    }

    func activityChipSlug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Mutations (design §Surface 2 stepper increments/floors + write-through)

private extension EnrichmentSequenceScreen {
    /// A step's currently-declared target kind. Legacy rows (no `goal` yet)
    /// fall back the same way `activityGoalLabel` already reads them:
    /// a positive `durationSec` means Time, otherwise Open — never invent a
    /// Distance/Cals reading for data that predates AMA-2378.
    func resolvedKind(for activity: EnrichmentActivityPref) -> ActivityGoalKind {
        if let goal = activity.goal { return goal.kind }
        if let durationSec = activity.durationSec, durationSec > 0 { return .time }
        return .open
    }

    func currentValue(_ activity: EnrichmentActivityPref, kind: ActivityGoalKind) -> Int {
        if let goal = activity.goal, goal.kind == kind, let value = goal.value {
            return value
        }
        if kind == .time, let durationSec = activity.durationSec, durationSec > 0 {
            return durationSec
        }
        return defaultValue(for: kind) ?? 0
    }

    func kindBinding(_ activity: Binding<EnrichmentActivityPref>) -> Binding<ActivityGoalKind> {
        Binding(
            get: { resolvedKind(for: activity.wrappedValue) },
            set: { newKind in
                guard newKind != resolvedKind(for: activity.wrappedValue) else { return }
                setGoal(activity, kind: newKind, value: defaultValue(for: newKind))
            }
        )
    }

    func bump(_ activity: Binding<EnrichmentActivityPref>, kind: ActivityGoalKind, from value: Int, direction: Int) {
        let stepped = value + direction * stepAmount(for: kind)
        setGoal(activity, kind: kind, value: max(floorValue(for: kind), stepped))
    }

    /// Goal write-through (Task 4 brief): Time also projects to `durationSec`
    /// (back-compat with v1 readers); Open clears `durationSec` entirely;
    /// Distance/Cals clear `durationSec` too so there is only one signal for
    /// a non-time goal — the backend prefers `goal` when both are present.
    func setGoal(_ activity: Binding<EnrichmentActivityPref>, kind: ActivityGoalKind, value: Int?) {
        switch kind {
        case .time:
            activity.wrappedValue.goal = try? ActivityGoal(kind: .time, value: value)
            activity.wrappedValue.durationSec = value
        case .open:
            activity.wrappedValue.goal = try? ActivityGoal(kind: .open, value: nil)
            activity.wrappedValue.durationSec = nil
        case .distance, .cals:
            activity.wrappedValue.goal = try? ActivityGoal(kind: kind, value: value)
            activity.wrappedValue.durationSec = nil
        }
    }

    func removeStep(id: UUID) {
        activities.removeAll { $0.id == id }
    }

    /// Design §Surface 2: "tap appends with Time 2:00 default" — write-through
    /// stamps both `goal` and the legacy `durationSec` projection.
    func addStep(named name: String) {
        let defaultTime = defaultValue(for: .time)
        activities.append(EnrichmentActivityPref(
            name: name,
            durationSec: defaultTime,
            goal: try? ActivityGoal(kind: .time, value: defaultTime)
        ))
    }

    /// Switching-kind defaults (Time 2:00=120 / Distance 500 / Cals 15).
    func defaultValue(for kind: ActivityGoalKind) -> Int? {
        switch kind {
        case .time: return 120
        case .distance: return 500
        case .cals: return 15
        case .open: return nil
        }
    }

    /// Stepper increments (Time ±30s / Distance ±100m / Cals ±5).
    func stepAmount(for kind: ActivityGoalKind) -> Int {
        switch kind {
        case .time: return 30
        case .distance: return 100
        case .cals: return 5
        case .open: return 0
        }
    }

    /// Stepper floors — same values as the increments (Task 4 brief).
    func floorValue(for kind: ActivityGoalKind) -> Int {
        switch kind {
        case .time: return 30
        case .distance: return 100
        case .cals: return 5
        case .open: return 0
        }
    }

    func stepperValueLabel(kind: ActivityGoalKind, value: Int) -> String {
        switch kind {
        case .time: return "\(WorkoutEnrichmentPushCopy.formatMinSec(value)) MIN"
        case .distance: return "\(value) M"
        case .cals: return "\(value) CAL"
        case .open: return WorkoutEnrichmentPushCopy.openStepperCaption
        }
    }
}

/// Display-only segment labels for the sequence builder's target tabs —
/// scoped to this file so the shared `ActivityGoalKind` model stays free of
/// UI copy.
private extension ActivityGoalKind {
    var sequenceSegmentLabel: String {
        switch self {
        case .time: return "Time"
        case .distance: return "Distance"
        case .cals: return "Cals"
        case .open: return "Open"
        }
    }
}

/// `− value +` pill, matching the prototype's `SEStepperPill` (screens-enhance2.jsx)
/// and the card2/capsule idiom `EditorV2Stepper` already uses elsewhere — kept
/// local (no label row) so it fits beside the four-way target segment on one line.
private struct SequenceStepperPill: View {
    let text: String
    var onDecrement: () -> Void
    var onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onDecrement) {
                Text("−")
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease")

            Text(text)
                .font(Theme.Typography.mono)
                .fontWeight(.semibold)
                .foregroundColor(DailyDriver.foreground)
                .monospacedDigit()
                .fixedSize()

            Button(action: onIncrement) {
                Text("＋")
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(DailyDriver.card2))
    }
}

#if DEBUG
#Preview("Mobility") {
    NavigationStack {
        EnrichmentSequenceScreen(
            activities: .constant([
                EnrichmentActivityPref(
                    name: "Ski erg",
                    goal: try? ActivityGoal(kind: .distance, value: 500)
                ),
                EnrichmentActivityPref(
                    name: "Assault bike",
                    durationSec: 120,
                    goal: try? ActivityGoal(kind: .time, value: 120)
                )
            ]),
            kind: .mobility
        )
    }
}

#Preview("Cooldown — empty") {
    NavigationStack {
        EnrichmentSequenceScreen(
            activities: .constant([]),
            kind: .cooldown
        )
    }
}
#endif
