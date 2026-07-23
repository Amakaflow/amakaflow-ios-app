//
//  DDExerciseInfoView.swift
//  AmakaFlow
//
//  AMA-2312 — full-screen Exercise Info (cues / muscles) from library detail tap.
//

import SwiftUI

struct DDExerciseInfoView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(exercise.name)
                    .ddDisplayText(28, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .accessibilityIdentifier("dd_exercise_info_name")

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("PRESCRIPTION")
                    Text(exercise.ddInfoPrescriptionLine)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foreground)
                        .accessibilityIdentifier("dd_exercise_info_prescription")
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("CUES")
                    let cues = exercise.notes?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if cues.isEmpty || Exercise.looksLikeMuscleFocus(cues) {
                        Text("No coaching notes")
                            .font(.system(size: 14))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .accessibilityIdentifier("dd_exercise_info_cues_empty")
                    } else {
                        Text(cues)
                            .font(.system(size: 15))
                            .foregroundColor(DailyDriver.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("dd_exercise_info_cues")
                    }
                }

                if let focus = exercise.ddMuscleHint {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("TARGET")
                        Text(focus)
                            .font(.system(size: 14))
                            .foregroundColor(DailyDriver.foreground)
                            .accessibilityIdentifier("dd_exercise_info_focus")
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("dd_exercise_info_done")
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
    }
}
