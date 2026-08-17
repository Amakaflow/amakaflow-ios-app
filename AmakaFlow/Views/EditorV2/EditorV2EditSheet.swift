//
//  EditorV2EditSheet.swift
//  AmakaFlow
//
//  AMA-2312 — focused edit sheet with always-editable Sets/Reps + user provenance.
//

import SwiftUI

struct EditorV2EditSheet: View {
    @State private var draft: EditorV2Exercise
    @State private var targetMemory: EditorV2EditTargetMemory
    /// Weight's session memory. `setBodyweightLoad()` clears `weightKg`, so
    /// without this the Weight chip round-trip would hand back the default
    /// instead of the athlete's own number — the rule the target families follow.
    @State private var lastWeightKg: Double
    var onDone: (EditorV2Exercise) -> Void

    init(exercise: EditorV2Exercise, onDone: @escaping (EditorV2Exercise) -> Void) {
        _draft = State(initialValue: exercise)
        _targetMemory = State(initialValue: EditorV2EditTargetMemory(exercise: exercise))
        _lastWeightKg = State(initialValue: exercise.weightKg ?? Self.defaultWeightKg)
        self.onDone = onDone
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sheetHeading
                trackRow
                wheelRow
                if showsRestEditor { restEditors }
                Button {
                    onDone(committedDraft())
                } label: {
                    Text("Done")
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DailyDriver.foreground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_exsheet_done")
            }
            .padding(.horizontal, 18)
            // Clear the sheet grabber — 8pt was clipping display titles like "Bench Press".
            .padding(.top, 28)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var sheetHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.name)
                .ddDisplayText(18, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(summaryDraft.summaryLine)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// TRACK — Reps / Time / Distance are exclusive, Weight is an add-on chip.
    @ViewBuilder
    private var trackRow: some View {
        sectionLabel("TRACK")
        HStack(spacing: 4) {
            ForEach(targetMemory.visibleKinds, id: \.self) { kind in
                targetKindChip(kind)
            }
            weightChip
        }
    }

    private var isWeightOn: Bool {
        draft.weightKg != nil
    }

    private var weightChip: some View {
        Button {
            if isWeightOn {
                lastWeightKg = draft.weightKg ?? lastWeightKg
                draft.setBodyweightLoad()
            } else {
                draft.setWeightedLoad(kilograms: lastWeightKg)
            }
        } label: {
            Text(isWeightOn ? "✓ Weight" : "＋ Weight")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(isWeightOn ? DailyDriver.lime : DailyDriver.foregroundMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isWeightOn ? DailyDriver.lime.opacity(0.16) : DailyDriver.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isWeightOn ? DailyDriver.lime.opacity(0.5) : .clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_exsheet_track_weight")
        .accessibilityAddTraits(isWeightOn ? .isSelected : [])
    }

    /// At most three columns — `EditorV2WheelLayout` owns that rule.
    @ViewBuilder
    private var wheelRow: some View {
        let columns = EditorV2WheelLayout.columns(track: targetMemory.kind, weightOn: isWeightOn)
        if targetMemory.kind == .open {
            openGoalCell
            if columns.contains(.weight) { wheelStrip([.weight]) }
        } else {
            wheelStrip(columns)
        }
    }

    private func wheelStrip(_ columns: [EditorV2WheelColumn]) -> some View {
        HStack(spacing: 10) {
            ForEach(columns, id: \.self) { column in
                wheel(for: column)
            }
        }
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("af_exsheet_wheels")
    }

    @ViewBuilder
    private func wheel(for column: EditorV2WheelColumn) -> some View {
        switch column {
        case .sets:
            EditorV2NumberWheel(
                label: "SETS",
                range: 1...12,
                accessibilityIdentifier: column.accessibilityIdentifier,
                selection: setsBinding
            )
        case .reps:
            EditorV2NumberWheel(
                label: "REPS",
                range: 1...50,
                accessibilityIdentifier: column.accessibilityIdentifier,
                selection: bind(\.reps) { $0.setReps($1) }
            )
        case .seconds:
            EditorV2NumberWheel(
                label: "SECONDS",
                range: 5...3_600,
                step: 5,
                accessibilityIdentifier: column.accessibilityIdentifier,
                selection: bind(\.workSeconds) { $0.setWorkSeconds($1) },
                display: formatSeconds
            )
        case .meters:
            EditorV2NumberWheel(
                label: "METERS",
                range: 20...2_000,
                step: 20,
                accessibilityIdentifier: column.accessibilityIdentifier,
                selection: bind(\.meters) { $0.setMeters($1) }
            )
        case .calories:
            EditorV2NumberWheel(
                label: "CALORIES",
                range: 5...500,
                step: 5,
                accessibilityIdentifier: column.accessibilityIdentifier,
                selection: bind(\.calories) { $0.setCalories($1) }
            )
        case .range:
            rangeCell
        case .weight:
            EditorV2NumberWheel(
                label: "KG · STEP 2.5",
                values: Self.weightValues,
                display: formatKilograms,
                accessibilityIdentifier: column.accessibilityIdentifier,
                selection: weightBinding
            )
        }
    }

    /// AMA-2368 — Transition (open / tap) vs Timed rest; timed stepper only when Timed selected.
    private var showsRestEditor: Bool {
        draft.restSeconds != nil
            || draft.restOpen == true
            || draft.sets != nil
    }

    private var isRestOpen: Bool {
        draft.restOpen == true
    }

    private var isTimedRest: Bool {
        !isRestOpen
    }

    @ViewBuilder
    private var restEditors: some View {
        sectionLabel("BETWEEN MOVES")
        if isTimedRest {
            proportionalGrid {
                HStack(spacing: 4) {
                    restModeChip(title: "Transition", selected: isRestOpen) {
                        try? draft.setRestIntent(restSeconds: nil, restOpen: true)
                    }
                    .accessibilityIdentifier("af_exsheet_rest_open")
                    restModeChip(title: "Timed rest", selected: isTimedRest) {
                        let seconds = draft.restSeconds ?? PrescriptionDefaults.defaultRestSec
                        try? draft.setRestIntent(restSeconds: seconds, restOpen: false)
                    }
                    .accessibilityIdentifier("af_exsheet_rest_timed")
                }
            } right: {
                EditorV2EditSheetStepperCell(
                    configuration: .init(
                        label: "DURATION",
                        value: draft.restSeconds ?? PrescriptionDefaults.defaultRestSec,
                        min: 15,
                        max: 300,
                        step: 15,
                        valueText: formatSecondsWithSuffix,
                        accessibilityIdentifier: "af_exsheet_rest_duration"
                    )
                ) { try? draft.setRestIntent(restSeconds: $0, restOpen: false) }
            }
        } else {
            HStack(spacing: 4) {
                restModeChip(title: "Transition", selected: isRestOpen) {
                    try? draft.setRestIntent(restSeconds: nil, restOpen: true)
                }
                .accessibilityIdentifier("af_exsheet_rest_open")
                restModeChip(title: "Timed rest", selected: isTimedRest) {
                    let seconds = draft.restSeconds ?? PrescriptionDefaults.defaultRestSec
                    try? draft.setRestIntent(restSeconds: seconds, restOpen: false)
                }
                .accessibilityIdentifier("af_exsheet_rest_timed")
            }
            Text("End transition on the watch — tap / lap")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DailyDriver.foregroundDim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .accessibilityIdentifier("af_exsheet_rest_open_caption")
        }
    }

    private var rangeCell: some View {
        HStack(spacing: 0) {
            rangeHalf(
                label: "REPS MIN",
                value: targetMemory.rangeMin,
                accessibilityIdentifier: "af_exsheet_range_min"
            ) { targetMemory.setRangeMin($0) }
            Rectangle()
                .fill(DailyDriver.border)
                .frame(width: 1)
                .padding(.vertical, 8)
            rangeHalf(
                label: "MAX",
                value: targetMemory.rangeMax,
                accessibilityIdentifier: "af_exsheet_range_max"
            ) { targetMemory.setRangeMax($0) }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 155)
    }

    private var openGoalCell: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Open goal")
                .ddDisplayText(14, weight: .bold)
                .foregroundColor(DailyDriver.amber)
            Text("NO TARGET — GO TILL READY · END ON TAP")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, 14)
        .background(DailyDriver.amber.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.amber.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("af_exsheet_open_goal")
    }

    private func targetKindChip(_ kind: EditorV2EditTargetKind) -> some View {
        Button {
            targetMemory.select(kind)
        } label: {
            Text(kind.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(targetMemory.kind == kind ? DailyDriver.ink : DailyDriver.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(targetMemory.kind == kind ? DailyDriver.foreground : DailyDriver.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(kind.accessibilityIdentifier)
        .accessibilityAddTraits(targetMemory.kind == kind ? .isSelected : [])
    }
}

extension EditorV2EditSheet {
    static let defaultWeightKg: Double = 20
    static let maxWeightKg: Double = 300
    static let weightValues: [Double] = stride(from: 0, through: maxWeightKg, by: 2.5).map { $0 }

    /// Wheels drive the target memory's mutating setters, so switching TRACK
    /// still preserves whatever the athlete typed into the other families.
    private func bind(
        _ value: KeyPath<EditorV2EditTargetMemory, Int>,
        set: @escaping (inout EditorV2EditTargetMemory, Int) -> Void
    ) -> Binding<Int> {
        Binding(
            get: { targetMemory[keyPath: value] },
            set: { newValue in set(&targetMemory, newValue) }
        )
    }

    private var setsBinding: Binding<Int> {
        Binding(
            get: { draft.sets ?? PrescriptionDefaults.defaultSets },
            set: { newValue in
                draft.sets = newValue
                draft.stampUser("sets")
            }
        )
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { draft.weightKg ?? lastWeightKg },
            set: { newValue in
                lastWeightKg = newValue
                draft.setWeightedLoad(kilograms: newValue)
            }
        )
    }

    private func formatKilograms(_ kilograms: Double) -> String {
        if abs(kilograms - kilograms.rounded()) < 1e-9 {
            return String(Int(kilograms.rounded()))
        }
        return String(format: "%.1f", kilograms)
    }

    private func proportionalGrid<Left: View, Right: View>(
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) -> some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 10
            HStack(spacing: 10) {
                left()
                    .frame(width: availableWidth / 2.35)
                right()
                    .frame(width: availableWidth * 1.35 / 2.35)
            }
        }
        .frame(height: 72)
    }

    private func rangeHalf(
        label: String,
        value: Int,
        accessibilityIdentifier: String,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
            HStack(spacing: 2) {
                Button { onChange(value - 1) } label: {
                    Text("−").ddDisplayText(16, weight: .bold)
                }
                .buttonStyle(.plain)
                .foregroundColor(DailyDriver.foregroundMuted)
                Text("\(value)")
                    .ddDisplayText(16, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity)
                Button { onChange(value + 1) } label: {
                    Text("＋").ddDisplayText(16, weight: .bold)
                }
                .buttonStyle(.plain)
                .foregroundColor(DailyDriver.foregroundMuted)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func restModeChip(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? DailyDriver.ink : DailyDriver.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? DailyDriver.foreground : DailyDriver.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.bottom, -7)
    }

    private func formatSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private func formatSecondsWithSuffix(_ seconds: Int) -> String {
        "\(seconds)s"
    }

    private var summaryDraft: EditorV2Exercise {
        var summary = draft
        targetMemory.apply(to: &summary)
        return summary
    }

    private func committedDraft() -> EditorV2Exercise {
        editorV2CommitEditDraft(draft, targetMemory: targetMemory)
    }
}
