//
//  LogbookWheelSheet.swift
//  AmakaFlow
//
//  AMA-2426: side-by-side weight + reps wheels (rig panel 3 — snap, center, fade).
//

import SwiftUI

struct LogbookWheelSheet: View {
    @ObservedObject var viewModel: LogbookViewModel
    @State private var weightDisplay: Double = 0
    @State private var reps: Int = 8
    @State private var didCenter = false

    private var weightValues: [Double] {
        WeightUnitMath.wheelValues(unit: viewModel.weightUnit, fine: viewModel.fineSteps)
    }

    private var repsValues: [Int] { Array(1...40) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DailyDriver.borderStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            if let focused = viewModel.focusedSet() {
                Text("\(focused.entry.name) · Set \(focused.set.index)")
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .padding(.top, 14)

                headerLine(focused: focused)
                    .padding(.top, 6)
            }

            HStack(spacing: 0) {
                weightWheel
                repsWheel
            }
            .frame(height: 180)
            .padding(.top, 8)
            .overlay {
                // Center emphasis bar
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DailyDriver.borderStrong, lineWidth: 1)
                    .frame(height: 36)
                    .allowsHitTesting(false)
            }

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

            VStack(spacing: 10) {
                Button {
                    viewModel.sameAsLastTime()
                    syncFromFocus()
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

                Button {
                    viewModel.applyWheel(weightDisplay: weightDisplay, reps: reps, advance: true)
                    syncFromFocus()
                } label: {
                    Text(LogbookCopy.nextSet)
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
            syncFromFocus()
            didCenter = true
        }
        .onChange(of: viewModel.wheelFocus) { _, _ in
            syncFromFocus()
        }
        .onChange(of: viewModel.weightUnit) { _, _ in
            syncFromFocus()
        }
    }

    private func headerLine(focused: (entry: LogbookExerciseEntry, set: SetActual)) -> some View {
        let ghost = viewModel.ghost(for: focused.entry.id, setIndex: focused.set.index)
        let lastText: String
        if let ghost, !ghost.isEmpty {
            lastText = "LAST TIME \(ghost.displayLine(unit: viewModel.weightUnit))"
        } else {
            lastText = "LAST TIME —"
        }
        let nowText =
            "NOW \(WeightUnitMath.formatWeight(kg: WeightUnitMath.kilograms(fromDisplay: weightDisplay, unit: viewModel.weightUnit), unit: viewModel.weightUnit)) \(viewModel.weightUnit.logbookLabel) × \(reps)"
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

    private func syncFromFocus() {
        guard let focused = viewModel.focusedSet() else { return }
        let ghost = viewModel.ghost(for: focused.entry.id, setIndex: focused.set.index)
        let kilograms = focused.set.weightKg ?? ghost?.weightKg ?? focused.entry.planned.weightKg
        weightDisplay = WeightUnitMath.nearestWheelValue(
            kg: kilograms,
            unit: viewModel.weightUnit,
            fine: viewModel.fineSteps
        )
        reps = focused.set.reps ?? ghost?.reps ?? focused.entry.planned.reps
    }

    private func recenterWeight() {
        weightDisplay = WeightUnitMath.nearestWheelValue(
            kg: WeightUnitMath.kilograms(fromDisplay: weightDisplay, unit: viewModel.weightUnit),
            unit: viewModel.weightUnit,
            fine: viewModel.fineSteps
        )
    }

    private func formatWheelWeight(_ value: Double) -> String {
        if abs(value - value.rounded()) < 1e-9 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}
