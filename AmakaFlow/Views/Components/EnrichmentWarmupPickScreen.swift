//
//  EnrichmentWarmupPickScreen.swift
//  AmakaFlow
//
//  AMA-2378 Task 3 — navigation stub. The per-exercise ramp toggle + editor
//  (Reps/Timed/Cals/Open sets, apply-to-all, amber open rail) lands in Task 5;
//  this placeholder proves the enhance sheet's Binding<[PerExerciseRamp]>
//  round-trip so Task 5 only has to fill in the pick-row UI.
//

import SwiftUI

struct EnrichmentWarmupPickScreen: View {
    @Binding var ramps: [PerExerciseRamp]
    /// Candidate exercise names from the push plan — display-only in this stub.
    let exercises: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Warm-up sets")
                    .ddDisplayText(20, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(WorkoutEnrichmentPushCopy.warmupPickHint)
                    .font(Theme.Typography.mono)
                    .foregroundColor(DailyDriver.foregroundMuted)
            }

            Text("Per-exercise ramp editor lands in Task 5 — Save keeps whatever the enhance sheet already has for these exercises.")
                .font(Theme.Typography.caption)
                .foregroundColor(DailyDriver.foregroundMuted)

            if exercises.isEmpty {
                Text("NO EXERCISES")
                    .font(Theme.Typography.mono)
                    .foregroundColor(DailyDriver.foregroundDim)
                    .accessibilityIdentifier("af_warmup_pick_empty")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(exercises, id: \.self) { name in
                        Text(WorkoutEnrichmentPushCopy.warmupExerciseTag(name: name, ramp: ramp(for: name)))
                            .font(Theme.Typography.mono)
                            .foregroundColor(DailyDriver.foreground)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Text("Save")
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .lg))
            .accessibilityIdentifier("af_warmup_pick_save")
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("Warm-up sets")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("af_warmup_pick_screen")
    }

    /// Matches by normalized name — ramps minted before an `exercise_id` exists
    /// key off name the same way the backend's `exercise_ref` fallback does.
    private func ramp(for exerciseName: String) -> PerExerciseRamp? {
        let key = ExerciseKeyNormalizer.normalize(exerciseName)
        return ramps.first { ExerciseKeyNormalizer.normalize($0.exerciseRef) == key }
    }
}

#if DEBUG
#Preview("Warm-up pick") {
    NavigationStack {
        EnrichmentWarmupPickScreen(
            ramps: .constant([]),
            exercises: ["Deadlift", "Overhead Press", "Leg Press"]
        )
    }
}

#Preview("Warm-up pick — empty") {
    NavigationStack {
        EnrichmentWarmupPickScreen(ramps: .constant([]), exercises: [])
    }
}
#endif
