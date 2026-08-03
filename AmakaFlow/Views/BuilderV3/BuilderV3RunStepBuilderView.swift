//
//  BuilderV3RunStepBuilderView.swift
//  AmakaFlow
//
//  AMA-2372 — Run step builder: warmup/work/recover/cooldown timeline with add
//  chips + steppers. Saves through the same `WorkoutEditorViewModel` +
//  `SocialImportBlock` path as Editor v2, so the mapper needs no changes.
//

import SwiftUI

struct BuilderV3RunStepBuilderView: View {
    let seed: BuilderV3TypeSeed
    var onChangeType: () -> Void
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var saveModel = WorkoutEditorViewModel()
    @State private var session: BuilderV3RunSession
    @State private var showChangeTypeConfirm = false
    @State private var toastMessage: String?

    init(
        seed: BuilderV3TypeSeed,
        onChangeType: @escaping () -> Void = {},
        onSaved: @escaping () -> Void = {}
    ) {
        self.seed = seed
        self.onChangeType = onChangeType
        self.onSaved = onSaved
        _session = State(initialValue: BuilderV3RunRegistry.makeRunSession(for: seed))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($session.blocks) { $block in
                            BuilderV3RunBlockCard(block: $block) {
                                session.removeBlock(block.id)
                            }
                        }
                        addChips
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .scrollContentBackground(.hidden)
            }
            if !session.blocks.isEmpty {
                DDEditorSaveBar(title: "Save run", isSaving: saveModel.isSaving, action: saveTapped)
                    .accessibilityIdentifier("builder_v3_run_save_button")
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("builder_v3_run_builder_screen")
        .overlay(alignment: .bottom) { toastOverlay }
        .onChange(of: saveModel.didSave) { _, saved in
            if saved {
                dismiss()
                onSaved()
            }
        }
        .onChange(of: saveModel.errorMessage) { _, message in
            if let message, !message.isEmpty { showToast(message) }
        }
        .alert("Change workout type?", isPresented: $showChangeTypeConfirm) {
            Button("Keep editing", role: .cancel) {}
            Button("Change type", role: .destructive) { onChangeType() }
        } message: {
            Text("This clears your current run draft.")
        }
    }

    private var header: some View {
        let accent = Color(hex: seed.category.accentHex)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    changeTypeTapped()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                        Text("Type").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(DailyDriver.foregroundMuted)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: changeTypeTapped) {
                    Text("\(seed.label.uppercased()) · CHANGE")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(accent.opacity(0.18)))
                        .overlay(Capsule().stroke(accent.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("builder_v3_type_change_button")
            }

            TextField("Name your run", text: $session.title)
                .ddDisplayText(22, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .accessibilityIdentifier("workout_name_field")

            Text(BuilderV3RunInstructionCopy.line(isBlankDraft: session.isBlankDraft))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var addChips: some View {
        EditorV2FlowWrap {
            addChip("+ Warm-up", id: "builder_v3_run_add_warmup") { session.addWarmup() }
            addChip("+ Work", id: "builder_v3_run_add_work") {
                session.addStandaloneWork(name: "Run", durationSeconds: 600, paceTarget: "easy")
            }
            addChip("+ Repeat block", id: "builder_v3_run_add_repeat_block") {
                session.addRepeatBlock(
                    repeatCount: 4,
                    work: BuilderV3RunStep(kind: .work, name: "400 m", distanceMeters: 400),
                    recover: BuilderV3RunStep(kind: .recover, name: "Recover", durationSeconds: 90)
                )
            }
            addChip("+ Cool-down", id: "builder_v3_run_add_cooldown") { session.addCooldown() }
        }
        .padding(.top, 8)
    }

    private func addChip(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .ddDisplayText(11.5, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(DailyDriver.card2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func changeTypeTapped() {
        if session.isBlankDraft {
            onChangeType()
        } else {
            showChangeTypeConfirm = true
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toastMessage {
            Text(toastMessage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DailyDriver.foreground)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DailyDriver.backgroundElevated)
                .clipShape(Capsule())
                .padding(.bottom, 88)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { self.toastMessage = nil }
                    }
                }
        }
    }

    private func saveTapped() {
        saveModel.name = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saveModel.sport = .running
        saveModel.saveBlocks = session.toSocialImportBlocks()
        saveModel.intervals = session.toSaveIntervals()
        Task { await saveModel.save() }
    }
}

/// Timeline card for one run block — single step or a repeat-block.
private struct BuilderV3RunBlockCard: View {
    @Binding var block: BuilderV3RunBlock
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(block.timelineLabel.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.lime)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("builder_v3_run_remove_block_\(block.id)")
            }

            ForEach($block.steps) { $step in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DailyDriver.foreground)
                        Text(step.summaryLine.isEmpty ? step.kind.label : step.summaryLine)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)
                    }
                    Spacer()
                }
            }

            if block.isRepeatBlock {
                EditorV2Stepper(
                    label: "Repeat ×",
                    value: block.repeatCount,
                    min: 1,
                    max: 30,
                    step: 1
                ) { block.repeatCount = $0 }
                .accessibilityIdentifier("builder_v3_run_repeat_stepper_\(block.id)")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("builder_v3_run_block_\(block.id)")
    }
}

/// Instruction subtitle under the run title (AMA-2372 mockup chrome).
enum BuilderV3RunInstructionCopy {
    static func line(isBlankDraft: Bool) -> String {
        if isBlankDraft {
            return "JUST ADD STEPS — STRUCTURE COMES LATER"
        }
        return "DEFAULTS APPLIED — TAP ANYTHING TO TWEAK"
    }
}

#if DEBUG
#Preview {
    BuilderV3RunStepBuilderView(seed: BuilderV3TypeRegistry.intervals) {}
}
#endif
