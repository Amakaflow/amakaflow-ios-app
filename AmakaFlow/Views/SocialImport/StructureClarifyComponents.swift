//
//  StructureClarifyComponents.swift
//  AmakaFlow
//
//  AMA-2305 — clarify group cards, flat rows, Describe sheet (screens-clarify.jsx).
//

import SwiftUI

// MARK: - Group card

struct StructureClarifyGroupCard: View {
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

struct StructureClarifyFlatRow: View {
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

struct FlowExampleChips: View {
    let examples: [String]
    var onTap: (String) -> Void

    var body: some View {
        FlexibleChipWrap(examples: examples, onTap: onTap)
    }
}

struct FlexibleChipWrap: View {
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

struct StructureSpinningModifier: ViewModifier {
    @State private var rotating = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
    }
}
