//
//  DDExerciseEditSheet.swift
//  AmakaFlow
//
//  Local exercise editor sheet — design-handoff DDExerciseSheet (~L1004).
//  Updates in-memory block draft only; no API save until workout Save.
//

import SwiftUI

enum DDExerciseEditKind: String, CaseIterable, Identifiable {
    case setsReps = "Sets/Reps"
    case duration = "Duration"
    case distance = "Distance"
    case calories = "Calories"

    var id: String { rawValue }
}

struct DDExerciseEditTarget: Identifiable, Equatable {
    let blockIndex: Int
    let exerciseIndex: Int

    var id: String { "\(blockIndex)-\(exerciseIndex)" }
}

struct DDExerciseEditSheet: View {
    @Binding var blocks: [DDEditorBlockDraft]
    let target: DDExerciseEditTarget
    let onDismiss: () -> Void

    @State private var draft: DDEditorExerciseDraft
    @State private var kind: DDExerciseEditKind

    init(
        blocks: Binding<[DDEditorBlockDraft]>,
        target: DDExerciseEditTarget,
        onDismiss: @escaping () -> Void
    ) {
        _blocks = blocks
        self.target = target
        self.onDismiss = onDismiss
        let exercise = blocks.wrappedValue[target.blockIndex].exercises[target.exerciseIndex]
        _draft = State(initialValue: exercise)
        _kind = State(initialValue: DDExerciseEditKind.inferred(from: exercise))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Exercise name", text: $draft.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DailyDriver.foreground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(DailyDriver.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    kindPicker

                    HStack(spacing: 8) {
                        switch kind {
                        case .setsReps:
                            DDEditorStepper(label: "Sets", value: bindingInt(\.sets), range: 1...10)
                            DDEditorStepper(label: "Reps", value: bindingInt(\.reps), range: 1...50)
                            DDEditorWeightStepper(weightKg: $draft.weightKg)
                        case .duration:
                            DDEditorStepper(
                                label: "Duration",
                                value: bindingInt(\.durationSeconds),
                                range: 1...600,
                                step: 5,
                                format: DDEditorFormatting.duration
                            )
                        case .distance:
                            DDEditorStepper(
                                label: "Distance m",
                                value: bindingInt(\.distanceMeters),
                                range: 1...5000,
                                step: 50
                            )
                        case .calories:
                            DDEditorStepper(
                                label: "Calories",
                                value: bindingInt(\.calories),
                                range: 1...500,
                                step: 5
                            )
                        }
                    }

                    Text("REST AFTER EXERCISE")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.top, 4)

                    DDEditorStepper(
                        label: "Rest",
                        value: bindingInt(\.restSeconds),
                        range: 0...300,
                        step: 5,
                        format: DDEditorFormatting.duration
                    )
                }
                .padding(18)
            }
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .navigationTitle("Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyDraft()
                        onDismiss()
                    }
                    .foregroundColor(DailyDriver.lime)
                }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: kind) { _, newKind in
            applyKindSwitch(newKind)
        }
    }

    private var kindPicker: some View {
        HStack(spacing: 0) {
            ForEach(DDExerciseEditKind.allCases) { tab in
                Button {
                    kind = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(kind == tab ? DailyDriver.foreground : DailyDriver.foregroundMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(kind == tab ? DailyDriver.card2 : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(DailyDriver.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
    }

    private func bindingInt(_ keyPath: WritableKeyPath<DDEditorExerciseDraft, Int?>) -> Binding<Int> {
        Binding(
            get: { draft[keyPath: keyPath] ?? 0 },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func applyKindSwitch(_ newKind: DDExerciseEditKind) {
        switch newKind {
        case .setsReps:
            draft.durationSeconds = nil
            draft.distanceMeters = nil
            draft.calories = nil
            if draft.sets == nil { draft.sets = 3 }
            if draft.reps == nil { draft.reps = 10 }
        case .duration:
            draft.sets = nil
            draft.reps = nil
            draft.distanceMeters = nil
            draft.calories = nil
            if draft.durationSeconds == nil { draft.durationSeconds = 60 }
        case .distance:
            draft.sets = nil
            draft.reps = nil
            draft.durationSeconds = nil
            draft.calories = nil
            if draft.distanceMeters == nil { draft.distanceMeters = 100 }
        case .calories:
            draft.sets = nil
            draft.reps = nil
            draft.durationSeconds = nil
            draft.distanceMeters = nil
            if draft.calories == nil { draft.calories = 15 }
        }
    }

    private func applyDraft() {
        guard blocks.indices.contains(target.blockIndex),
              blocks[target.blockIndex].exercises.indices.contains(target.exerciseIndex) else { return }
        blocks[target.blockIndex].exercises[target.exerciseIndex] = draft
    }
}

private struct DDEditorWeightStepper: View {
    @Binding var weightKg: Double?

    private var displayValue: Double { weightKg ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WEIGHT KG")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
            HStack(spacing: 8) {
                Button {
                    let next = max(0, displayValue - 2.5)
                    weightKg = next == 0 ? nil : next
                } label: {
                    Text("−")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                Text(displayValue.truncatingRemainder(dividingBy: 1) == 0
                     ? String(Int(displayValue))
                     : String(format: "%.1f", displayValue))
                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity)
                Button {
                    weightKg = min(300, displayValue + 2.5)
                } label: {
                    Text("＋")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(minWidth: 96)
    }
}

private struct DDEditorStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...999
    var step: Int = 1
    var format: ((Int) -> String)?

    var body: some View {
        stepperContent(value: value) { value = $0 }
    }

    private func stepperContent(value: Int, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
            HStack(spacing: 8) {
                Button {
                    onChange(max(range.lowerBound, value - step))
                } label: {
                    Text("−")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                Text(format?(value) ?? "\(value)")
                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity)
                Button {
                    onChange(min(range.upperBound, value + step))
                } label: {
                    Text("＋")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(minWidth: 96)
    }
}

private extension DDExerciseEditKind {
    static func inferred(from exercise: DDEditorExerciseDraft) -> DDExerciseEditKind {
        if let duration = exercise.durationSeconds, duration > 0 { return .duration }
        if let distance = exercise.distanceMeters, distance > 0 { return .distance }
        if let calories = exercise.calories, calories > 0 { return .calories }
        return .setsReps
    }
}
