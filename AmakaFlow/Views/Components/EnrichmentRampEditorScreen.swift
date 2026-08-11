//
//  EnrichmentRampEditorScreen.swift
//  AmakaFlow
//
//  AMA-2378 Task 5 — per-exercise ramp editor (design 2026-08-04
//  `make-it-watch-ready-v2-design.md` §Surface 4). Reps/Timed/Cals/Open sets
//  with an amber "no target" rail for Open, plus "Apply this ramp to all
//  selected" — a one-shot copy onto every other enabled exercise's ramp.
//  `[RampSet]` is a value type, so the moment `applyRampSets` returns, every
//  copy is already independent: mutating this exercise's sets afterward can
//  never reach through to another's (verified in
//  `WorkoutEnrichmentModelsTests.testApplyRampSetsCopiesThenDiverge`).
//

import SwiftUI

struct EnrichmentRampEditorScreen: View {
    @Binding var ramps: [PerExerciseRamp]
    let exerciseName: String
    /// Declared working-set count for this exercise, `nil` when the ingest
    /// draft never declared one — the header then reads "YOUR WORKING SETS"
    /// rather than guessing a number.
    var workingSetCount: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var applyToAll = false
    @State private var didSeed = false

    /// Builder card left rail for non-open sets — mobility band token (same as
    /// sequence builder / watch preview prep accent).
    private static let railColor = DailyDriver.mobilityBand

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerMeta
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if ramp.sets.isEmpty {
                        Text("NO WARM-UP SETS")
                            .font(Theme.Typography.mono)
                            .foregroundColor(DailyDriver.foregroundDim)
                            .accessibilityIdentifier("af_ramp_editor_empty")
                    } else {
                        ForEach(Array(ramp.sets.enumerated()), id: \.element.id) { index, _ in
                            setCard(index: index)
                        }
                    }

                    addSetButton
                    applyToAllRow

                    Text(WorkoutEnrichmentPushCopy.loadsOffRampNote)
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
            DDEditorSaveBar(title: "Save ramp") { dismiss() }
                .accessibilityIdentifier("af_ramp_editor_save")
        }
        .preferredColorScheme(.dark)
        .navigationTitle("\(exerciseName) ramp")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("af_ramp_editor_screen")
        .onAppear(perform: seedIfNeeded)
    }
}

// MARK: - Header

private extension EnrichmentRampEditorScreen {
    var headerMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(exerciseName) ramp")
                .ddDisplayText(20, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
            Text(
                WorkoutEnrichmentPushCopy.rampEditorHeaderMeta(
                    setCount: ramp.sets.count,
                    workingSetCount: workingSetCount
                )
            )
            .font(Theme.Typography.mono)
            .foregroundColor(DailyDriver.foregroundMuted)
            .accessibilityIdentifier("af_ramp_editor_header_meta")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Set cards

private extension EnrichmentRampEditorScreen {
    func setCard(index: Int) -> some View {
        let set = ramp.sets[index]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("SET \(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(width: 46, alignment: .leading)
                TextField("Intensity note", text: intensityNoteBinding(index: index))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("af_ramp_set_note_\(index)")
                Spacer(minLength: 0)
                Button {
                    removeSet(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove set \(index + 1)")
                .accessibilityIdentifier("af_ramp_set_remove_\(index)")
            }

            HStack(spacing: 8) {
                Picker("", selection: kindBinding(index: index)) {
                    ForEach(WarmupSetKind.allCases, id: \.self) { candidate in
                        Text(candidate.rampSegmentLabel).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .tint(DailyDriver.lime)
                .accessibilityIdentifier("af_ramp_set_kind_\(index)")

                if set.kind == .open {
                    Text(WorkoutEnrichmentPushCopy.openStepperCaption)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.amber)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 128, alignment: .leading)
                } else {
                    RampStepperPill(
                        text: WorkoutEnrichmentPushCopy.rampSetLabel(set),
                        onDecrement: { bump(index: index, direction: -1) },
                        onIncrement: { bump(index: index, direction: 1) }
                    )
                    .accessibilityIdentifier("af_ramp_set_stepper_\(index)")
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
                .fill(set.kind == .open ? DailyDriver.amber : Self.railColor)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.bottom, 8)
        .accessibilityIdentifier("af_ramp_set_\(index)")
    }
}

// MARK: - Add set + apply-to-all

private extension EnrichmentRampEditorScreen {
    var addSetButton: some View {
        Button {
            addSet()
        } label: {
            Text("＋ Add warm-up set")
                .ddDisplayText(12, weight: .semibold)
                .foregroundColor(DailyDriver.foreground)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Capsule().fill(DailyDriver.card))
                .overlay(Capsule().stroke(DailyDriver.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_ramp_editor_add_set")
        .padding(.top, Theme.Spacing.sm)
    }

    var applyToAllRow: some View {
        Toggle(isOn: applyToAllBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apply this ramp to all selected")
                    .ddDisplayText(12.5, weight: .semibold)
                    .foregroundColor(DailyDriver.foreground)
                Text("Copies today's sets to every warm-up-enabled exercise — each stays editable after.")
                    .font(.system(size: 9.5))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(DailyDriver.lime)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, Theme.Spacing.sm)
        .accessibilityIdentifier("af_ramp_apply_all")
    }

    /// A momentary trigger dressed as a toggle (design brief): flipping ON
    /// copies today's sets onto every enabled ramp right now via the pure
    /// `WorkoutEnrichmentMutations.applyRampSets`. There is nothing to keep
    /// "in sync" afterward — every copy is independent the instant this
    /// returns — so flipping OFF is just a visual reset, no data changes.
    var applyToAllBinding: Binding<Bool> {
        Binding(
            get: { applyToAll },
            set: { newValue in
                applyToAll = newValue
                guard newValue else { return }
                ramps = WorkoutEnrichmentMutations.applyRampSets(ramp.sets, toEnabledRampsIn: ramps)
            }
        )
    }
}

// MARK: - Ramp lookup + mutations

private extension EnrichmentRampEditorScreen {
    var rampKey: String { ExerciseKeyNormalizer.normalize(exerciseName) }

    /// Always reflects stored state. Call `seedIfNeeded` on appear so the
    /// unseeded path never rebuilds fresh `RampSet` UUIDs every render.
    var ramp: PerExerciseRamp {
        ramps.first { ExerciseKeyNormalizer.normalize($0.exerciseRef) == rampKey }
            ?? PerExerciseRamp(exerciseRef: exerciseName, enabled: true, sets: [])
    }

    /// Mints the entry once so `RampSet.id` stays stable across renders.
    func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        guard !ramps.contains(where: {
            ExerciseKeyNormalizer.normalize($0.exerciseRef) == rampKey
        }) else {
            return
        }
        ramps.append(PerExerciseRamp(
            exerciseRef: exerciseName,
            enabled: true,
            sets: WorkoutEnrichmentMutations.defaultRampSets()
        ))
    }

    /// Writes through to the matching `ramps` entry, minting one if somehow
    /// never seeded (pick screen / onAppear always seed first).
    func mutateRamp(_ mutate: (inout PerExerciseRamp) -> Void) {
        if let index = ramps.firstIndex(where: { ExerciseKeyNormalizer.normalize($0.exerciseRef) == rampKey }) {
            mutate(&ramps[index])
        } else {
            var fresh = PerExerciseRamp(
                exerciseRef: exerciseName,
                enabled: true,
                sets: WorkoutEnrichmentMutations.defaultRampSets()
            )
            mutate(&fresh)
            ramps.append(fresh)
        }
    }

    func intensityNoteBinding(index: Int) -> Binding<String> {
        Binding(
            get: { ramp.sets.indices.contains(index) ? (ramp.sets[index].intensityNote ?? "") : "" },
            set: { newValue in setIntensityNote(newValue, at: index) }
        )
    }

    func setIntensityNote(_ note: String, at index: Int) {
        mutateRamp { rampValue in
            guard rampValue.sets.indices.contains(index) else { return }
            rampValue.sets[index].intensityNote = note.isEmpty ? nil : note
        }
    }

    func kindBinding(index: Int) -> Binding<WarmupSetKind> {
        Binding(
            get: { ramp.sets.indices.contains(index) ? ramp.sets[index].kind : .reps },
            set: { newKind in setKind(newKind, at: index) }
        )
    }

    func setKind(_ kind: WarmupSetKind, at index: Int) {
        mutateRamp { rampValue in
            guard rampValue.sets.indices.contains(index) else { return }
            let current = rampValue.sets[index]
            guard let updated = try? RampSet(
                kind: kind,
                value: Self.defaultValue(for: kind),
                intensityNote: current.intensityNote,
                id: current.id
            ) else {
                return
            }
            rampValue.sets[index] = updated
        }
    }

    func bump(index: Int, direction: Int) {
        mutateRamp { rampValue in
            guard rampValue.sets.indices.contains(index) else { return }
            let current = rampValue.sets[index]
            guard current.kind != .open else { return }
            let stepped = (current.value ?? 0) + direction * Self.stepAmount(for: current.kind)
            let clamped = max(Self.floorValue(for: current.kind), stepped)
            guard let updated = try? RampSet(
                kind: current.kind,
                value: clamped,
                // AMA-2408 — value edits drop intensity notes so enrich labels
                // carry the new reps (backend prefers note over reps).
                intensityNote: nil,
                id: current.id
            ) else {
                return
            }
            rampValue.sets[index] = updated
        }
    }

    func removeSet(at index: Int) {
        mutateRamp { rampValue in
            guard rampValue.sets.indices.contains(index) else { return }
            rampValue.sets.remove(at: index)
        }
    }

    func addSet() {
        mutateRamp { rampValue in
            guard let newSet = try? RampSet(kind: .reps, value: 5) else { return }
            rampValue.sets.append(newSet)
        }
    }

    /// Switching-kind defaults (Reps 8 / Timed 30s / Cals 15 / Open none).
    static func defaultValue(for kind: WarmupSetKind) -> Int? {
        switch kind {
        case .reps: return 8
        case .time: return 30
        case .cals: return 15
        case .open: return nil
        }
    }

    /// Stepper increments (Task 5 brief: Reps ±1 / Timed ±30s / Cals ±5).
    static func stepAmount(for kind: WarmupSetKind) -> Int {
        switch kind {
        case .reps: return 1
        case .time: return 30
        case .cals: return 5
        case .open: return 0
        }
    }

    /// Stepper floors — Reps floors at 1 (never 0 reps); Timed/Cals floor at
    /// their own step amount, matching the sequence builder's convention.
    static func floorValue(for kind: WarmupSetKind) -> Int {
        switch kind {
        case .reps: return 1
        case .time: return 30
        case .cals: return 5
        case .open: return 0
        }
    }
}

/// Display-only segment labels for the ramp editor's kind picker — scoped to
/// this file so the shared `WarmupSetKind` model stays free of UI copy.
private extension WarmupSetKind {
    var rampSegmentLabel: String {
        switch self {
        case .reps: return "Reps"
        case .time: return "Timed"
        case .cals: return "Cals"
        case .open: return "Open"
        }
    }
}

/// `− value +` pill, matching the sequence builder's `SequenceStepperPill`
/// (kept as its own local copy — that one is private to
/// `EnrichmentSequenceScreen.swift`).
private struct RampStepperPill: View {
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
#Preview("Ramp editor") {
    NavigationStack {
        EnrichmentRampEditorScreen(
            ramps: .constant([
                PerExerciseRamp(
                    exerciseRef: "Deadlift",
                    enabled: true,
                    sets: WorkoutEnrichmentMutations.defaultRampSets() + [
                        try? RampSet(kind: .open, value: nil, intensityNote: "GO TILL READY")
                    ].compactMap { $0 }
                )
            ]),
            exerciseName: "Deadlift",
            workingSetCount: 3
        )
    }
}

#Preview("Ramp editor — empty") {
    NavigationStack {
        EnrichmentRampEditorScreen(
            ramps: .constant([]),
            exerciseName: "Overhead Press",
            workingSetCount: nil
        )
    }
}
#endif
