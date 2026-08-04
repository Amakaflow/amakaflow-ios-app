//
//  EditorV2EditSheet.swift
//  AmakaFlow
//
//  AMA-2312 — focused edit sheet with always-editable Sets/Reps + user provenance.
//

import SwiftUI

/// The five mutually exclusive work-target families presented by the focused editor.
enum EditorV2EditTargetKind: String, CaseIterable, Equatable {
    case reps
    case range
    case timed
    case cals
    case open

    var title: String {
        switch self {
        case .reps: return "Reps"
        case .range: return "Range"
        case .timed: return "Timed"
        case .cals: return "Cals"
        case .open: return "Open"
        }
    }

    var accessibilityIdentifier: String {
        "af_exsheet_target_\(rawValue)"
    }
}

/// Session-local values for each target family. Switching targets never destroys a
/// value the athlete just entered; an absent family receives its product default.
struct EditorV2EditTargetMemory: Equatable {
    var kind: EditorV2EditTargetKind
    var reps: Int = 10
    var rangeMin: Int = 8
    var rangeMax: Int = 12
    var workSeconds: Int = 40
    var calories: Int = 15

    init(exercise: EditorV2Exercise) {
        if exercise.openGoal {
            kind = .open
        } else if let range = exercise.repsRange {
            kind = .range
            rangeMin = range.low
            rangeMax = range.high
        } else if let seconds = exercise.durationSeconds {
            kind = .timed
            workSeconds = seconds
        } else if let targetCalories = exercise.calories {
            kind = .cals
            calories = targetCalories
        } else {
            kind = .reps
            reps = exercise.reps ?? Self.defaultReps
        }
    }

    static let defaultReps = 10
    static let defaultRangeMin = 8
    static let defaultRangeMax = 12
    static let defaultWorkSeconds = 40
    static let defaultCalories = 15

    mutating func setRangeMin(_ value: Int) {
        rangeMin = Swift.min(Swift.max(1, value), rangeMax)
    }

    mutating func setRangeMax(_ value: Int) {
        rangeMax = Swift.max(rangeMin, Swift.min(50, value))
    }

    mutating func apply(to exercise: inout EditorV2Exercise) {
        exercise.openGoal = false
        exercise.reps = nil
        exercise.repsRange = nil
        exercise.durationSeconds = nil
        exercise.distanceMeters = nil
        exercise.calories = nil

        switch kind {
        case .reps:
            exercise.reps = reps
            exercise.stampUser("reps")
        case .range:
            exercise.repsRange = RepsRange(low: rangeMin, high: rangeMax)
            exercise.stampUser("reps_range")
        case .timed:
            exercise.durationSeconds = workSeconds
            exercise.stampUser("duration_seconds")
        case .cals:
            exercise.calories = calories
            exercise.stampUser("calories")
        case .open:
            exercise.openGoal = true
            exercise.stampUser("open_goal")
        }
    }
}

struct EditorV2EditSheet: View {
    @State private var draft: EditorV2Exercise
    @State private var targetMemory: EditorV2EditTargetMemory
    var onDone: (EditorV2Exercise) -> Void

    init(exercise: EditorV2Exercise, onDone: @escaping (EditorV2Exercise) -> Void) {
        _draft = State(initialValue: exercise)
        _targetMemory = State(initialValue: EditorV2EditTargetMemory(exercise: exercise))
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetHeading
            targetEditors
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
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var sheetHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.name)
                .ddDisplayText(18, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Text(summaryDraft.summaryLine)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var targetEditors: some View {
        sectionLabel("TARGET")
        HStack(spacing: 4) {
            ForEach(EditorV2EditTargetKind.allCases, id: \.self) { kind in
                targetKindChip(kind)
            }
        }
        proportionalGrid {
            stepperCell(
                label: "SETS",
                value: draft.sets ?? PrescriptionDefaults.defaultSets,
                min: 1,
                max: 12,
                accessibilityIdentifier: "af_exsheet_sets"
            ) { newValue in
                draft.sets = newValue
                draft.stampUser("sets")
            }
        } right: {
            targetValueCell
        }
    }

    /// AMA-2368 — Open (tap) vs Timed rest; timed stepper only when Timed selected.
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
        sectionLabel("REST")
        proportionalGrid {
            HStack(spacing: 4) {
                restModeChip(title: "Open", selected: isRestOpen) {
                    try? draft.setRestIntent(restSeconds: nil, restOpen: true)
                }
                .accessibilityIdentifier("af_exsheet_rest_open")
                restModeChip(title: "Timed", selected: isTimedRest) {
                    let seconds = draft.restSeconds ?? PrescriptionDefaults.defaultRestSec
                    try? draft.setRestIntent(restSeconds: seconds, restOpen: false)
                }
                .accessibilityIdentifier("af_exsheet_rest_timed")
            }
        } right: {
            if isTimedRest {
                stepperCell(
                    label: "DURATION",
                    value: draft.restSeconds ?? PrescriptionDefaults.defaultRestSec,
                    min: 15,
                    max: 300,
                    step: 15,
                    valueText: { "\($0)s" },
                    accessibilityIdentifier: "af_exsheet_rest_duration"
                ) { try? draft.setRestIntent(restSeconds: $0, restOpen: false) }
            } else {
                Text("YOU END REST ON THE WATCH — TAP / LAP")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("af_exsheet_rest_open_caption")
            }
        }
    }

    private var targetValueCell: some View {
        Group {
            switch targetMemory.kind {
            case .reps:
                stepperCell(
                    label: "REPS",
                    value: targetMemory.reps,
                    min: 1,
                    max: 50,
                    accessibilityIdentifier: "af_exsheet_reps"
                ) { targetMemory.reps = $0 }
            case .range:
                rangeCell
            case .timed:
                stepperCell(
                    label: "WORK",
                    value: targetMemory.workSeconds,
                    min: 10,
                    max: 3_600,
                    step: 10,
                    valueText: formatSeconds,
                    accessibilityIdentifier: "af_exsheet_work"
                ) { targetMemory.workSeconds = $0 }
            case .cals:
                stepperCell(
                    label: "CALORIES",
                    value: targetMemory.calories,
                    min: 5,
                    max: 500,
                    step: 5,
                    accessibilityIdentifier: "af_exsheet_calories"
                ) { targetMemory.calories = $0 }
            case .open:
                openGoalCell
            }
        }
        .frame(maxWidth: .infinity)
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
        .frame(height: 72)
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            targetMemory.kind = kind
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

    private func stepperCell(
        label: String,
        value: Int,
        min: Int,
        max: Int,
        step: Int = 1,
        valueText: ((Int) -> String)? = nil,
        accessibilityIdentifier: String,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        EditorV2Stepper(
            label: label,
            value: value,
            min: min,
            max: max,
            step: step,
            valueText: valueText,
            onChange: onChange
        )
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func proportionalGrid<Left: View, Right: View>(
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
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

    private var summaryDraft: EditorV2Exercise {
        var summary = draft
        targetMemory.apply(to: &summary)
        return summary
    }

    private func committedDraft() -> EditorV2Exercise {
        var committed = draft
        targetMemory.apply(to: &committed)
        // AMA-2368 — open rest must not serialize with timed seconds (preserve provenance).
        if committed.restOpen == true {
            committed.restSeconds = nil
        }
        return committed
    }
}
