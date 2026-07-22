//
//  DDEditorLegacyCards.swift
//  AmakaFlow
//
//  AMA-2307 — legacy accordion block/exercise rows (backfill only).
//

import SwiftUI

// MARK: - Block card

struct DDEditorBlockCard: View {
    @Binding var block: DDEditorBlockDraft
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onAddExercise: () -> Void
    let onDeleteExercise: (Int) -> Void
    let onMoveExercise: (Int, Int) -> Void
    let onSwap: (Int) -> Void
    let onEdit: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ReorderColumn(onUp: onMoveUp, onDown: onMoveDown)

                Text(block.structure.label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(block.structure.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(block.structure.accentColor.opacity(0.18))
                    .clipShape(Capsule())

                Button { block.isOpen.toggle() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.label)
                            .ddDisplayText(13.5, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                            .lineLimit(1)
                        Text(block.metaLine)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(4)
                }
                .buttonStyle(.plain)

                Button { block.isOpen.toggle() } label: {
                    Image(systemName: block.isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)

            if block.isOpen {
                VStack(spacing: 0) {
                    if block.exercises.isEmpty {
                        Text("No exercises yet — add one below")
                            .font(.system(size: 11.5))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }

                    ForEach(Array(block.exercises.enumerated()), id: \.element.id) { index, exercise in
                        DDEditorExerciseRow(
                            exercise: exercise,
                            onMoveUp: { onMoveExercise(index, -1) },
                            onMoveDown: { onMoveExercise(index, 1) },
                            onDelete: { onDeleteExercise(index) },
                            onSwap: { onSwap(index) },
                            onEdit: { onEdit(index) }
                        )
                        if index < block.exercises.count - 1 {
                            Divider().overlay(DailyDriver.border)
                        }
                    }

                    Button(action: onAddExercise) {
                        Text("＋ Add exercise")
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                    .foregroundColor(DailyDriver.borderStrong)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .background(Color.black.opacity(0.3))
                .overlay(alignment: .top) {
                    Rectangle().fill(DailyDriver.border).frame(height: 1)
                }
            }
        }
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(block.structure.accentColor)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DDEditorExerciseRow: View {
    let exercise: DDEditorExerciseDraft
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onSwap: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ReorderColumn(onUp: onMoveUp, onDown: onMoveDown)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(DailyDriver.foreground)
                Text(exercise.summaryLine)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(exercise.showsLastTime ? DailyDriver.foregroundDim : DailyDriver.foregroundMuted)

                if let swapMessage = exercise.swapMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Text(swapMessage)
                            .font(.system(size: 11))
                            .foregroundColor(DailyDriver.amber)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: onSwap) {
                            Text("Swap")
                                .ddDisplayText(11, weight: .bold)
                                .foregroundColor(Color(hex: "1A1200"))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(DailyDriver.amber)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dd_editor_exercise_edit")

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }
}

struct ReorderColumn: View {
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(1)
            }
            .buttonStyle(.plain)
            Button(action: onDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(1)
            }
            .buttonStyle(.plain)
        }
    }
}

struct DDEditorBlockTypePicker: View {
    let onSelect: (DDEditorStructureKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What type of block?")
                .ddDisplayText(14, weight: .bold)
                .foregroundColor(DailyDriver.foreground)

            DDEditorFlowLayout(spacing: 7) {
                ForEach(DDEditorStructureKind.allCases) { kind in
                    Button { onSelect(kind) } label: {
                        Text("\(kind.emoji) \(kind.label)")
                            .ddDisplayText(12.5, weight: .semibold)
                            .foregroundColor(DailyDriver.foreground)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(DailyDriver.card2)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(kind.accentColor.opacity(0.45), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onCancel) {
                Text("Cancel")
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Simple wrapping layout for block-type chips.
struct DDEditorFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

