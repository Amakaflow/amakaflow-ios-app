//
//  StructureClarifyView.swift
//  AmakaFlow
//
//  AMA-2305 — "Check the structure" intervene step (ADR-017).
//  Ground truth: design-handoff/screenshots/rig-clarify-states.png
//  + design-handoff/reference/screens-clarify.jsx
//

import SwiftUI

struct StructureClarifyView: View {
    @ObservedObject var viewModel: SocialImportViewModel
    var onBack: (() -> Void)?
    var onSaved: (() -> Void)?

    @State private var describeOpen = false

    private var session: StructureClarifySession {
        viewModel.clarifySession ?? StructureClarifySession()
    }

    private var draft: SocialImportDraft? { viewModel.draft }

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.units) { unit in
                            switch unit {
                            case .group(let group):
                                StructureClarifyGroupCard(
                                    group: group,
                                    onConfirm: { viewModel.confirmClarifyGroup(group.id) },
                                    onUndo: { viewModel.undoClarifyGroup(group.id) },
                                    onRounds: { viewModel.bumpClarifyRounds(group.id, delta: $0) }
                                )
                            case .row(let row):
                                StructureClarifyFlatRow(
                                    row: row,
                                    selected: session.selectedRowIDs.contains(row.id),
                                    onToggle: { viewModel.toggleClarifyRow(row.id) }
                                )
                            }
                        }

                        if !session.selectedRowIDs.isEmpty {
                            selectionChipBar
                        }

                        describeDoor
                            .padding(.top, 4)

                        Text("Unconfirmed groups save as a flat list — we never guess silently.")
                            .font(.system(size: 10.5))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 140)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
            }

            footerCTAs
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .ddSuppressFloatingChrome()
        .sheet(isPresented: $describeOpen) {
            StructureDescribeSheet(viewModel: viewModel) {
                describeOpen = false
            }
        }
        .onChange(of: viewModel.phase) { _, phase in
            if case .saved = phase {
                onSaved?()
            }
        }
        .accessibilityIdentifier("structure_clarify_screen")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onBack?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

                Text("Check the structure")
                .ddDisplayText(24, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 10)

            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(2)
                .padding(.top, 5)

            provenanceCard
                .padding(.top, 10)
        }
        .padding(.horizontal, 18)
    }

    private var subtitle: String {
        let count = session.exerciseCount
        return "\(count) exercise\(count == 1 ? "" : "s") found. The grouping was implied, not stated — confirm it so the player runs it right."
    }

    private var provenanceCard: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(DailyDriver.purple)
                    .frame(width: 28, height: 28)
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(draft?.title ?? "Imported workout")
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .lineLimit(1)
                Text(provenanceMono)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if session.pendingGroupCount > 0 {
                Button {
                    viewModel.confirmAllClarifyGroups()
                } label: {
                    Text("✓ Confirm all (\(session.pendingGroupCount))")
                        .ddDisplayText(11, weight: .bold)
                        .foregroundColor(DailyDriver.lime)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("structure_clarify_confirm_all")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var provenanceMono: String {
        let creator = draft?.postProvenance?.creatorDisplay.uppercased() ?? "CREATOR"
        let mode = (draft?.postProvenance?.mode ?? "reel caption").uppercased()
        return "\(creator) · \(mode) PARSED"
    }

    // MARK: - Chips / Describe

    private var selectionChipBar: some View {
        let count = session.selectedRowIDs.count
        return VStack(alignment: .leading, spacing: 8) {
            Text(count < 2
                 ? "\(count) SELECTED — PICK ANOTHER TO GROUP THEM"
                 : "\(count) SELECTED — GROUP AS:")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)

            HStack(spacing: 7) {
                chipButton("Superset", enabled: count >= 2) {
                    viewModel.groupClarifySelection(as: .superset)
                }
                chipButton("Circuit ×4", enabled: count >= 2) {
                    viewModel.groupClarifySelection(as: .circuit)
                }
                Button("Cancel") {
                    viewModel.clearClarifySelection()
                }
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(DailyDriver.card2))
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.lime.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 10)
    }

    private func chipButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(DailyDriver.card2))
                .overlay(
                    Capsule().stroke(DailyDriver.amber.opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }

    private var describeDoor: some View {
        Button {
            describeOpen = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Not right? Describe it")
                        .ddDisplayText(13, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text("“bench + pull ups are a superset, finisher is a circuit ×5”")
                        .font(.system(size: 10.5))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DailyDriver.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("structure_clarify_describe_door")
        .padding(.bottom, 12)
    }

    // MARK: - Footer

    private var footerCTAs: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.saveFromClarify(leaveFlat: true) }
            } label: {
                Text("Leave flat")
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule()
                            .fill(Color(red: 16 / 255, green: 16 / 255, blue: 18 / 255).opacity(0.96))
                    )
                    .overlay(
                        Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("structure_clarify_leave_flat")

            Button {
                Task { await viewModel.saveFromClarify(leaveFlat: false) }
            } label: {
                Text(saveLabel)
                    .ddDisplayText(14.5, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(DailyDriver.lime))
            }
            .buttonStyle(.plain)
            .ddLimeGlow()
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            .accessibilityIdentifier("structure_clarify_save")
        }
    }

    private var saveLabel: String {
        let confirmed = session.confirmedGroupCount
        if confirmed > 0 {
            return "Save · \(confirmed) block\(confirmed == 1 ? "" : "s") ✓"
        }
        return "Looks right — Save"
    }
}

// MARK: - Group card

private struct StructureClarifyGroupCard: View {
    let group: StructureClarifyGroup
    var onConfirm: () -> Void
    var onUndo: () -> Void
    var onRounds: (Int) -> Void

    private var typeColor: Color {
        DDEditorStructureKind(rawValue: group.type.canonical.rawValue)?.accentColor
            ?? structureAccent(group.type)
    }

    private var tagColor: Color {
        switch group.status {
        case .confirmed: return DailyDriver.lime
        case .pending:
            return group.structureSource == .userNote ? DailyDriver.blue : DailyDriver.amber
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(group.provenanceTag)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(tagColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tagColor.opacity(0.16)))
                    Spacer()
                    if !group.metaLine.isEmpty {
                        Text(group.metaLine)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundDim)
                    }
                }
                Text(group.label)
                    .ddDisplayText(14.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .padding(.top, 7)
            }
            .padding(.horizontal, 13)
            .padding(.top, 11)
            .padding(.bottom, 9)

            VStack(spacing: 0) {
                ForEach(Array(group.exercises.enumerated()), id: \.element.id) { index, exercise in
                    if index > 0 {
                        Divider().background(DailyDriver.border)
                    }
                    HStack(spacing: 10) {
                        Text(group.markIndex(at: index))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(typeColor)
                            .frame(width: 20, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .ddDisplayText(13, weight: .semibold)
                                .foregroundColor(DailyDriver.foreground)
                            Text(exercise.summary)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(DailyDriver.foregroundMuted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 9)
                }
            }
            .padding(.horizontal, 13)
            .background(Color.black.opacity(0.3))
            .overlay(alignment: .top) {
                Rectangle().fill(DailyDriver.border).frame(height: 1)
            }

            HStack(spacing: 8) {
                if group.status != .confirmed {
                    Button(action: onConfirm) {
                        Text("✓ Confirm")
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(DailyDriver.lime))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("SAVES AS A \(group.type.displayLabel.uppercased()) BLOCK")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.lime)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if group.type.canonical == .circuit || group.type.canonical == .forTime {
                    HStack(spacing: 7) {
                        Button { onRounds(-1) } label: {
                            Text("−").foregroundColor(DailyDriver.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        Text("×\(group.rounds ?? 1)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(DailyDriver.foreground)
                        Button { onRounds(1) } label: {
                            Text("＋").foregroundColor(DailyDriver.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DailyDriver.card2))
                }

                Button(action: onUndo) {
                    Text(group.status == .confirmed ? "Ungroup" : "Undo")
                        .ddDisplayText(11.5, weight: .bold)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(DailyDriver.card2))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .overlay(alignment: .top) {
                Rectangle().fill(DailyDriver.border).frame(height: 1)
            }
        }
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    group.status == .confirmed
                        ? DailyDriver.lime.opacity(0.45)
                        : DailyDriver.border,
                    lineWidth: 1
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(typeColor)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 10)
    }

    private func structureAccent(_ type: StructureBlockType) -> Color {
        switch type.canonical {
        case .superset: return DailyDriver.amber
        case .circuit, .rounds: return DailyDriver.zoneGreen
        case .warmup: return Color(hex: "8890A0")
        case .sets, .regular: return Color.white.opacity(0.35)
        case .emom: return DailyDriver.blue
        case .amrap: return DailyDriver.orange
        case .tabata: return DailyDriver.red
        case .forTime, .fortime: return DailyDriver.purple
        }
    }
}

// MARK: - Flat row

private struct StructureClarifyFlatRow: View {
    let row: StructureClarifyRow
    var selected: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .stroke(DailyDriver.borderStrong, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                        .opacity(selected ? 0 : 1)
                    if selected {
                        Circle()
                            .fill(DailyDriver.lime)
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(DailyDriver.ink)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.exercise.name)
                        .ddDisplayText(13.5, weight: .semibold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(row.exercise.summary)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                Spacer()
                Text("NOT GROUPED")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(selected ? DailyDriver.lime.opacity(0.12) : DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? DailyDriver.lime.opacity(0.55) : DailyDriver.border,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
}

// MARK: - Describe sheet

struct StructureDescribeSheet: View {
    @ObservedObject var viewModel: SocialImportViewModel
    var onClose: () -> Void

    private let examples = [
        "curls go after the incline pair, finisher is a circuit x5",
        "everything is straight sets — leave it flat"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DailyDriver.backgroundElevated.ignoresSafeArea()
                if viewModel.isReadingNote {
                    readingState
                } else {
                    formContent
                }
            }
            .navigationTitle("Describe the structure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        guard !viewModel.isReadingNote else { return }
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DailyDriver.foregroundMuted)
                    }
                    .disabled(viewModel.isReadingNote)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("structure_describe_sheet")
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Say it like you'd tell a training partner — we turn it into blocks you can confirm. Nothing applies until you check it.")
                .font(.system(size: 11.5))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(2)
                .padding(.bottom, 10)

            TextEditor(text: $viewModel.describeNote)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 84)
                .padding(12)
                .background(DailyDriver.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 10)
                .accessibilityIdentifier("structure_describe_note")

            FlowExampleChips(examples: examples) { example in
                viewModel.describeNote = example
            }
            .padding(.bottom, 14)

            Button {
                Task {
                    await viewModel.applyDescribeNote()
                    if case .clarify = viewModel.phase {
                        onClose()
                    }
                }
            } label: {
                Text("Apply to workout")
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(
                            viewModel.describeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? DailyDriver.foregroundDim
                                : DailyDriver.lime
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.describeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("structure_describe_apply")

            Spacer()
        }
        .padding(18)
    }

    private var readingState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 2.5)
                    .frame(width: 64, height: 64)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(DailyDriver.lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                    .modifier(StructureSpinningModifier())
                Circle()
                    .fill(DailyDriver.lime)
                    .frame(width: 40, height: 40)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DailyDriver.ink)
            }
            Text("Reading your note…")
                .ddDisplayText(15, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Text("“\(viewModel.describeNote)”")
                .font(.system(size: 11).italic())
                .foregroundColor(DailyDriver.foregroundMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
    }
}

private struct FlowExampleChips: View {
    let examples: [String]
    var onTap: (String) -> Void

    var body: some View {
        FlexibleChipWrap(examples: examples, onTap: onTap)
    }
}

private struct FlexibleChipWrap: View {
    let examples: [String]
    var onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(examples, id: \.self) { example in
                Button {
                    onTap(example)
                } label: {
                    Text("“\(example)”")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(DailyDriver.card2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct StructureSpinningModifier: ViewModifier {
    @State private var rotating = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
    }
}
