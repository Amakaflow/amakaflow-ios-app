//
//  LogbookWheelSheet.swift
//  AmakaFlow
//
//  AMA-2426: weight+reps wheels, or TIME+CAL for metric/cardio stations.
//

import SwiftUI

struct LogbookWheelSheet: View {
    @ObservedObject var viewModel: LogbookViewModel
    @State private var weightDisplay: Double = 0
    @State private var reps: Int = 8
    @State private var durationSeconds: Int = 60
    @State private var calories: Int = 0
    /// Bumped to remount wheel pickers — UIPickerView often ignores programmatic selection changes.
    @State private var pickerEpoch: Int = 0

    private var isMetric: Bool {
        viewModel.wheelFocus?.mode == .metric
    }

    private var weightValues: [Double] {
        WeightUnitMath.wheelValues(unit: viewModel.weightUnit, fine: viewModel.fineSteps)
    }

    private var repsValues: [Int] { Array(1...40) }
    private var durationValues: [Int] { Array(stride(from: 0, through: 60 * 60, by: 5)) }
    private var calorieValues: [Int] { Array(0...2000) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DailyDriver.borderStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            if let focused = viewModel.focusedSet() {
                Text(title(for: focused))
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .padding(.top, 14)

                headerLine(focused: focused)
                    .padding(.top, 6)
            }

            Group {
                if isMetric {
                    HStack(spacing: 0) {
                        durationWheel
                        calorieWheel
                    }
                } else {
                    HStack(spacing: 0) {
                        weightWheel
                        repsWheel
                    }
                }
            }
            .id(pickerEpoch)
            .frame(height: 180)
            .padding(.top, 8)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DailyDriver.borderStrong, lineWidth: 1)
                    .frame(height: 36)
                    .allowsHitTesting(false)
            }
            .onChange(of: viewModel.weightUnit) { _, _ in
                guard !isMetric else { return }
                recenterWeight()
            }

            if isMetric {
                Text("TIME · CAL — leave one blank if you only track one")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.top, 4)
            } else {
                Button {
                    viewModel.fineSteps.toggle()
                    recenterWeight()
                } label: {
                    Text(viewModel.fineSteps ? "Coarse steps" : "Finer steps (long-press)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                        viewModel.fineSteps = true
                        recenterWeight()
                    }
                )
            }

            VStack(spacing: 10) {
                Button {
                    applySameAsLastTime()
                } label: {
                    Text(LogbookCopy.sameAsLast)
                        .ddDisplayText(13, weight: .semibold)
                        .foregroundColor(DailyDriver.foreground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DailyDriver.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_logbook_same_as_last")

                Button {
                    commitAndAdvance()
                } label: {
                    Text(isMetric ? LogbookCopy.doneMetric : LogbookCopy.nextSet)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DailyDriver.lime)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_logbook_next_set")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(DailyDriver.screenBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            syncFromFocus(remountPickers: true)
        }
        .onChange(of: viewModel.wheelFocus) { _, _ in
            syncFromFocus(remountPickers: true)
        }
    }

    private func title(for focused: (entry: LogbookExerciseEntry, set: SetActual)) -> String {
        if focused.entry.isMetric {
            return focused.entry.name
        }
        return "\(focused.entry.name) · Set \(focused.set.index)"
    }

    private func headerLine(focused: (entry: LogbookExerciseEntry, set: SetActual)) -> some View {
        let ghost = viewModel.ghost(for: focused.entry.id, setIndex: focused.set.index)
        let lastText: String
        if let ghost, !ghost.isEmpty {
            lastText = "LAST TIME \(ghost.displayLine(unit: viewModel.weightUnit))"
        } else {
            lastText = "LAST TIME —"
        }
        let nowText: String
        if isMetric {
            var parts: [String] = []
            if durationSeconds > 0 {
                parts.append(LogbookMetricFormat.duration(durationSeconds))
            }
            if calories > 0 {
                parts.append("\(calories) CAL")
            }
            nowText = "NOW \(parts.isEmpty ? "—" : parts.joined(separator: " · "))"
        } else {
            let nowWeight: String
            if focused.set.weightKg == nil,
               ghost?.weightKg == nil,
               focused.entry.planned.weightKg == nil,
               weightDisplay == 0 {
                nowWeight = "—"
            } else {
                nowWeight =
                    "\(WeightUnitMath.formatWeight(kg: WeightUnitMath.kilograms(fromDisplay: weightDisplay, unit: viewModel.weightUnit), unit: viewModel.weightUnit)) \(viewModel.weightUnit.logbookLabel)"
            }
            nowText = "NOW \(nowWeight) × \(reps)"
        }
        return Text("\(lastText) · \(nowText)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private var weightWheel: some View {
        Picker(LogbookCopy.columnWeight(for: viewModel.weightUnit), selection: $weightDisplay) {
            ForEach(weightValues, id: \.self) { value in
                Text(formatWheelWeight(value))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(DailyDriver.foreground)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("af_logbook_weight_wheel")
    }

    private var repsWheel: some View {
        Picker(LogbookCopy.columnReps, selection: $reps) {
            ForEach(repsValues, id: \.self) { value in
                Text("\(value)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(DailyDriver.foreground)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("af_logbook_reps_wheel")
    }

    private var durationWheel: some View {
        Picker(LogbookCopy.columnTime, selection: $durationSeconds) {
            ForEach(durationValues, id: \.self) { value in
                Text(value == 0 ? "—" : LogbookMetricFormat.duration(value))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(DailyDriver.foreground)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("af_logbook_duration_wheel")
    }

    private var calorieWheel: some View {
        Picker(LogbookCopy.columnCal, selection: $calories) {
            ForEach(calorieValues, id: \.self) { value in
                Text(value == 0 ? "—" : "\(value)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(DailyDriver.foreground)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("af_logbook_calorie_wheel")
    }

    private func commitAndAdvance() {
        if isMetric {
            viewModel.applyMetric(
                durationSeconds: durationSeconds,
                calories: calories,
                distanceMeters: viewModel.focusedSet()?.set.distanceMeters,
                advance: true
            )
        } else {
            viewModel.applyWheel(weightDisplay: weightDisplay, reps: reps, advance: true)
        }
        syncFromFocus(remountPickers: true)
    }

    private func applySameAsLastTime() {
        guard let ghost = viewModel.sameAsLastTime() else { return }
        applyGhostToWheels(ghost)
        pickerEpoch += 1
    }

    private func applyGhostToWheels(_ ghost: LogbookGhost) {
        if isMetric {
            durationSeconds = ghost.durationSeconds ?? 0
            calories = ghost.calories ?? 0
            return
        }
        weightDisplay = WeightUnitMath.nearestWheelValue(
            kg: ghost.weightKg,
            unit: viewModel.weightUnit,
            fine: viewModel.fineSteps
        )
        if let ghostReps = ghost.reps {
            reps = max(1, min(40, ghostReps))
        }
    }

    private func syncFromFocus(remountPickers: Bool = false) {
        guard let focused = viewModel.focusedSet() else { return }
        let ghost = viewModel.ghost(for: focused.entry.id, setIndex: focused.set.index)
        if focused.entry.isMetric || viewModel.wheelFocus?.mode == .metric {
            durationSeconds = focused.set.durationSeconds
                ?? ghost?.durationSeconds
                ?? focused.entry.plannedDurationSeconds
                ?? 0
            // Snap to 5s wheel steps.
            durationSeconds = (durationSeconds / 5) * 5
            calories = focused.set.calories
                ?? ghost?.calories
                ?? focused.entry.plannedCalories
                ?? 0
        } else {
            let kilograms = focused.set.weightKg ?? ghost?.weightKg ?? focused.entry.planned.weightKg
            weightDisplay = WeightUnitMath.nearestWheelValue(
                kg: kilograms,
                unit: viewModel.weightUnit,
                fine: viewModel.fineSteps
            )
            reps = focused.set.reps
                ?? ghost?.reps
                ?? focused.entry.planned.reps
            reps = max(1, min(40, reps))
        }
        if remountPickers {
            pickerEpoch += 1
        }
    }

    private func recenterWeight() {
        weightDisplay = WeightUnitMath.nearestWheelValue(
            kg: WeightUnitMath.kilograms(fromDisplay: weightDisplay, unit: viewModel.weightUnit),
            unit: viewModel.weightUnit,
            fine: viewModel.fineSteps
        )
        pickerEpoch += 1
    }

    private func formatWheelWeight(_ value: Double) -> String {
        if abs(value - value.rounded()) < 1e-9 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}
