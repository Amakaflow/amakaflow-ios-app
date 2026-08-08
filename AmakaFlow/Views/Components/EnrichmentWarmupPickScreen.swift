//
//  EnrichmentWarmupPickScreen.swift
//  AmakaFlow
//
//  AMA-2378 Task 3 shipped a navigation stub proving the enhance sheet's
//  `Binding<[PerExerciseRamp]>` round-trip.
//  AMA-2378 Task 5 — real per-exercise toggle + live ramp digest + `Edit ramp ›`
//  push to `EnrichmentRampEditorScreen` (design 2026-08-04
//  `make-it-watch-ready-v2-design.md` §Surface 3). Every card binds to its own
//  `PerExerciseRamp` entry matched by normalized name — editing one exercise's
//  ramp can never mutate another's, and turning a toggle ON for the first time
//  mints a fresh entry seeded with the global 8·5 default
//  (`WorkoutEnrichmentMutations.defaultRampSets`).
//

import SwiftUI

struct EnrichmentWarmupPickScreen: View {
    @Binding var ramps: [PerExerciseRamp]
    /// Candidate exercise names from the push plan, in display order.
    let exercises: [String]
    /// AMA-2378 Task 5 — each candidate's declared working-set count (`nil`
    /// when unknown), same order as `exercises`. Threaded to the ramp
    /// editor's header meta so "→ THEN YOUR K WORKING SETS" is real when
    /// the ingest draft declared one.
    var workingSetCounts: [Int?] = []

    @Environment(\.dismiss) private var dismiss
    @State private var editingExercise: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerMeta
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if exercises.isEmpty {
                        Text("NO EXERCISES")
                            .font(Theme.Typography.mono)
                            .foregroundColor(DailyDriver.foregroundDim)
                            .accessibilityIdentifier("af_warmup_pick_empty")
                    } else {
                        ForEach(Array(exercises.enumerated()), id: \.offset) { index, name in
                            exerciseCard(index: index, name: name)
                        }
                        Text("Ramps are saved per exercise on this workout — change one without touching the others.")
                            .font(.system(size: 10.5))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Spacing.xs)
                            .accessibilityIdentifier("af_warmup_pick_footer_hint")
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 110)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            DDEditorSaveBar(title: "Save warm-ups") {
                DDToastCenter.shared.success(
                    WatchItemCopy.toastWarmupsSaved,
                    sub: WatchItemCopy.toastSavedSub
                )
                dismiss()
            }
                .accessibilityIdentifier("af_warmup_pick_save")
        }
        .navigationDestination(item: $editingExercise) { name in
            EnrichmentRampEditorScreen(
                ramps: $ramps,
                exerciseName: name,
                workingSetCount: workingSetCount(for: name)
            )
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Warm-up sets")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("af_warmup_pick_screen")
    }
}

// MARK: - Header

private extension EnrichmentWarmupPickScreen {
    var headerMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Warm-up sets")
                .ddDisplayText(20, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
            Text(
                WorkoutEnrichmentPushCopy.warmupPickHeaderMeta(
                    enabledCount: enabledCount,
                    total: exercises.count
                )
            )
            .font(Theme.Typography.mono)
            .foregroundColor(DailyDriver.foregroundMuted)
            .accessibilityIdentifier("af_warmup_pick_header_meta")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
    }

    var enabledCount: Int {
        exercises.filter { ramp(for: $0)?.enabled ?? false }.count
    }
}

// MARK: - Exercise cards

private extension EnrichmentWarmupPickScreen {
    func exerciseCard(index: Int, name: String) -> some View {
        let currentRamp = ramp(for: name)
        let isOn = currentRamp?.enabled ?? false
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: toggleBinding(for: name)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .ddDisplayText(14.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(WorkoutEnrichmentPushCopy.perExerciseRampDigest(currentRamp))
                        .font(Theme.Typography.mono)
                        .foregroundColor(isOn ? DailyDriver.foregroundMuted : DailyDriver.foregroundDim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("af_enhance_warmup_ex_digest_\(index)")
                }
            }
            .tint(DailyDriver.lime)
            .accessibilityIdentifier("af_enhance_warmup_ex_\(index)")
            .accessibilityLabel(WorkoutEnrichmentPushCopy.warmupExerciseTag(name: name, ramp: currentRamp))
            .accessibilityAddTraits(isOn ? [.isSelected] : [])

            if isOn {
                // Full-width pill — design Surface 3 (`screens-enhance2.jsx`); the
                // prior trailing text link was too small to tap reliably.
                Button {
                    editingExercise = name
                } label: {
                    Text("Edit ramp ›")
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(DailyDriver.card2))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_enhance_warmup_ex_edit_\(index)")
                .accessibilityHint("Opens the \(name) ramp editor")
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                .stroke(isOn ? DailyDriver.lime : DailyDriver.border, lineWidth: isOn ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
        .padding(.bottom, 4)
        .accessibilityIdentifier("af_enhance_warmup_ex_card_\(index)")
    }
}

// MARK: - Mutations (toggle + seed-on-first-enable)

private extension EnrichmentWarmupPickScreen {
    /// Matches by normalized name — ramps minted before an `exercise_id` exists
    /// key off name the same way the backend's `exercise_ref` fallback does.
    func ramp(for exerciseName: String) -> PerExerciseRamp? {
        let key = ExerciseKeyNormalizer.normalize(exerciseName)
        return ramps.first { ExerciseKeyNormalizer.normalize($0.exerciseRef) == key }
    }

    func workingSetCount(for exerciseName: String) -> Int? {
        guard let index = exercises.firstIndex(of: exerciseName),
              workingSetCounts.indices.contains(index) else { return nil }
        return workingSetCounts[index]
    }

    func toggleBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { ramp(for: name)?.enabled ?? false },
            set: { setEnabled($0, for: name) }
        )
    }

    /// Absent ramp ⇒ off/skipped (design default). Turning ON for the first
    /// time mints a `PerExerciseRamp` seeded with the global 8·5 default;
    /// turning OFF an exercise that never had a ramp is a no-op — there is
    /// nothing to disable. Re-enabling a previously-configured ramp keeps its
    /// existing sets untouched (never re-seeds over a user's edits).
    func setEnabled(_ enabled: Bool, for name: String) {
        let key = ExerciseKeyNormalizer.normalize(name)
        if let index = ramps.firstIndex(where: { ExerciseKeyNormalizer.normalize($0.exerciseRef) == key }) {
            ramps[index].enabled = enabled
            if enabled, ramps[index].sets.isEmpty {
                ramps[index].sets = WorkoutEnrichmentMutations.defaultRampSets()
            }
        } else if enabled {
            ramps.append(PerExerciseRamp(
                exerciseRef: name,
                enabled: true,
                sets: WorkoutEnrichmentMutations.defaultRampSets()
            ))
        }
    }
}

#if DEBUG
#Preview("Warm-up pick") {
    NavigationStack {
        EnrichmentWarmupPickScreen(
            ramps: .constant([
                PerExerciseRamp(
                    exerciseRef: "Deadlift",
                    enabled: true,
                    sets: WorkoutEnrichmentMutations.defaultRampSets()
                )
            ]),
            exercises: ["Deadlift", "Overhead Press", "Leg Press"],
            workingSetCounts: [3, nil, 4]
        )
    }
}

#Preview("Warm-up pick — empty") {
    NavigationStack {
        EnrichmentWarmupPickScreen(ramps: .constant([]), exercises: [])
    }
}
#endif
