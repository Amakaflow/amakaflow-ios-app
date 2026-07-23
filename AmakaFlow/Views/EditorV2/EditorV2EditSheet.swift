//
//  EditorV2EditSheet.swift
//  AmakaFlow
//
//  AMA-2312 — focused edit sheet with always-editable Sets/Reps + user provenance.
//

import SwiftUI

struct EditorV2EditSheet: View {
    @State private var draft: EditorV2Exercise
    @State private var rangeText: String
    @State private var useRangeMode: Bool
    var onDone: (EditorV2Exercise) -> Void

    init(exercise: EditorV2Exercise, onDone: @escaping (EditorV2Exercise) -> Void) {
        _draft = State(initialValue: exercise)
        _rangeText = State(initialValue: exercise.repsRange?.display ?? "")
        _useRangeMode = State(initialValue: exercise.repsRange != nil)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            editorV2SheetTitle(draft.name)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 8
            ) {
                if draft.showsStrengthPrescriptionEditors {
                    strengthEditors
                } else {
                    modalityEditors
                }
                if draft.durationSeconds != nil {
                    EditorV2Stepper(
                        label: "Time",
                        value: draft.durationSeconds ?? 0,
                        unit: "s",
                        min: 5,
                        max: 3600,
                        step: 5
                    ) { draft.durationSeconds = $0 }
                }
                if draft.distanceMeters != nil {
                    EditorV2Stepper(
                        label: "Distance",
                        value: draft.distanceMeters ?? 0,
                        unit: " m",
                        min: 10,
                        max: 5000,
                        step: 10
                    ) { draft.distanceMeters = $0 }
                }
                if draft.weightKg != nil {
                    EditorV2Stepper(
                        label: "Weight",
                        value: Int(((draft.weightKg ?? 0) * 10).rounded()),
                        min: 0,
                        max: 3_000,
                        step: 5,
                        valueText: { tenths in
                            "\(EditorV2Exercise.formatWeight(Double(tenths) / 10)) kg"
                        },
                        onChange: { draft.weightKg = Double($0) / 10 }
                    )
                }
                if draft.calories != nil {
                    EditorV2Stepper(
                        label: "Calories",
                        value: draft.calories ?? 0,
                        unit: " cal",
                        min: 1,
                        max: 200,
                        step: 1
                    ) { draft.calories = $0 }
                }
                if draft.restSeconds != nil || draft.showsStrengthPrescriptionEditors {
                    EditorV2Stepper(
                        label: "Rest",
                        value: draft.restSeconds ?? 0,
                        unit: "s",
                        min: 0,
                        max: 300,
                        step: 15,
                        valueText: { draft.restSeconds == nil ? "—" : "\($0)s" },
                        onChange: { newValue in
                            if draft.restSeconds == nil {
                                draft.restSeconds = PrescriptionDefaults.defaultRestSec
                            } else {
                                draft.restSeconds = newValue
                            }
                            draft.stampUser("rest_sec")
                        }
                    )
                }
            }
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
            .accessibilityIdentifier("editor_v2_edit_done")
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(DailyDriver.backgroundElevated)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var strengthEditors: some View {
        EditorV2Stepper(
            label: "Sets",
            value: draft.sets ?? 0,
            min: 1,
            max: 12,
            valueText: { draft.sets == nil ? "—" : "\($0)" },
            onChange: { newValue in
                if draft.sets == nil {
                    draft.sets = PrescriptionDefaults.defaultSets
                } else {
                    draft.sets = newValue
                }
                draft.stampUser("sets")
            }
        )

        if useRangeMode {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Rep range")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                    Spacer()
                    Button("Reps") {
                        useRangeMode = false
                        draft.repsRange = nil
                        if draft.reps == nil {
                            draft.reps = PrescriptionDefaults.defaultReps
                            draft.stampUser("reps")
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                }
                TextField("8-10", text: $rangeText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .padding(12)
                    .background(DailyDriver.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(DailyDriver.foreground)
                    .accessibilityIdentifier("editor_v2_edit_rep_range")
                    .onChange(of: rangeText) { _, _ in
                        draft.stampUser("reps_range")
                    }
            }
            .gridCellColumns(2)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer()
                    Button("Range") {
                        useRangeMode = true
                        draft.reps = nil
                        if rangeText.isEmpty { rangeText = "8-10" }
                        draft.stampUser("reps_range")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                }
                EditorV2Stepper(
                    label: "Reps",
                    value: draft.reps ?? 0,
                    min: 1,
                    max: 50,
                    valueText: { draft.reps == nil ? "—" : "\($0)" },
                    onChange: { newValue in
                        if draft.reps == nil {
                            draft.reps = PrescriptionDefaults.defaultReps
                        } else {
                            draft.reps = newValue
                        }
                        draft.stampUser("reps")
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var modalityEditors: some View {
        if draft.sets != nil {
            EditorV2Stepper(label: "Sets", value: draft.sets ?? 0, min: 1, max: 12) {
                draft.sets = $0
                draft.stampUser("sets")
            }
        }
        if draft.repsRange != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rep range")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                TextField("8-10", text: $rangeText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .padding(12)
                    .background(DailyDriver.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(DailyDriver.foreground)
                    .accessibilityIdentifier("editor_v2_edit_rep_range")
            }
            .gridCellColumns(2)
        } else if draft.reps != nil {
            EditorV2Stepper(label: "Reps", value: draft.reps ?? 0, min: 1, max: 50) {
                draft.reps = $0
                draft.stampUser("reps")
            }
        }
    }

    private func committedDraft() -> EditorV2Exercise {
        guard useRangeMode else { return draft }
        if let updated = RepsRange.fromRangeText(rangeText, preservingQualifier: draft.repsRange?.qualifier) {
            draft.repsRange = updated
            draft.reps = nil
            draft.stampUser("reps_range")
        }
        return draft
    }
}
