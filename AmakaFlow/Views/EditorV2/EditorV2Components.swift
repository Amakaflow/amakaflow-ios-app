//
//  EditorV2Components.swift
//  AmakaFlow
//
//  AMA-2307 — calm cards, group pill + rail, steppers (screens-editor2.jsx).
//

import SwiftUI

// MARK: - Stepper

struct EditorV2Stepper: View {
    let label: String
    let value: Int
    var unit: String = ""
    var min: Int = 0
    var max: Int = 999
    var step: Int = 1
    /// Optional display override (e.g. tenths → `"12.5 kg"`).
    var valueText: ((Int) -> String)?
    var onChange: (Int) -> Void

    @State private var repeatDirection: Int = 0
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
            HStack(spacing: 8) {
                stepperButton(title: "−", direction: -1)
                Text(valueText?(value) ?? "\(value)\(unit)")
                    .ddDisplayText(17, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                stepperButton(title: "＋", direction: 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 92)
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDisappear { stopRepeating() }
    }

    private func stepperButton(title: String, direction: Int) -> some View {
        Text(title)
            .ddDisplayText(20, weight: .bold)
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                applyStep(direction)
            }
            .onLongPressGesture(
                minimumDuration: 0.35,
                maximumDistance: 48,
                pressing: { pressing in
                    if pressing {
                        startRepeating(direction: direction)
                    } else {
                        stopRepeating()
                    }
                },
                perform: {}
            )
            .accessibilityLabel(direction < 0 ? "Decrease \(label)" : "Increase \(label)")
            .accessibilityAddTraits(.isButton)
    }

    private func applyStep(_ direction: Int) {
        if direction < 0 {
            onChange(Swift.max(min, value - step))
        } else {
            onChange(Swift.min(max, value + step))
        }
    }

    private func startRepeating(direction: Int) {
        stopRepeating()
        repeatDirection = direction
        // Delay before first repeat so a short tap only counts once via onTapGesture.
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            while !Task.isCancelled, repeatDirection == direction {
                applyStep(direction)
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    private func stopRepeating() {
        repeatDirection = 0
        repeatTask?.cancel()
        repeatTask = nil
    }
}

// MARK: - Exercise card (max 2 controls)

struct EditorV2ExerciseCard: View {
    let exercise: EditorV2Exercise
    var inGroup: Bool = false
    var isFirst: Bool = true
    var onOpen: () -> Void
    var onMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 11) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.name)
                            .ddDisplayText(14, weight: .semibold)
                            .foregroundColor(DailyDriver.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(exercise.summaryLine)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editor_v2_exercise_body_\(exercise.id)")

                Button(action: onMenu) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editor_v2_exercise_menu_\(exercise.id)")
            }

            // AMA-2336 — warm-up sets are a sibling list; `sets` stays as written.
            if !exercise.warmupSets.isEmpty {
                Text("WARM-UP SETS · \(warmupSetsSummary)")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .accessibilityIdentifier("editor_v2_warmup_sets_\(exercise.id)")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(inGroup ? Color.clear : DailyDriver.card)
        .overlay(alignment: .top) {
            if inGroup && !isFirst {
                Rectangle().fill(DailyDriver.border).frame(height: 1)
            }
        }
        .overlay {
            if !inGroup {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: inGroup ? 0 : 16, style: .continuous))
        .padding(.bottom, inGroup ? 0 : 8)
    }

    private var warmupSetsSummary: String {
        exercise.warmupSets.map { row in
            if let kind = row.kind,
               let set = try? RampSet(kind: kind, value: kind == .open ? nil : (row.value ?? row.reps)) {
                return WorkoutEnrichmentPushCopy.rampSetLabel(set)
            }
            if let reps = row.reps {
                return "\(reps) REPS"
            }
            return "—"
        }.joined(separator: " · ")
    }
}

// MARK: - Group pill

struct EditorV2GroupPill: View {
    let group: EditorV2Group
    var isInsertionTarget: Bool = false
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(group.name.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(group.type.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(group.type.accentColor.opacity(0.18))
                    )
                Text(group.metaLine)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                if isInsertionTarget {
                    Text("ADDING HERE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(DailyDriver.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(DailyDriver.lime))
                        .accessibilityIdentifier("editor_v2_insertion_target_badge")
                }
                Spacer(minLength: 0)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editor_v2_group_pill_\(group.id)")
    }
}

// MARK: - Grouped run

struct EditorV2GroupedRun: View {
    let group: EditorV2Group
    let exercises: [EditorV2Exercise]
    var isInsertionTarget: Bool = false
    var onPill: () -> Void
    var onOpen: (EditorV2Exercise) -> Void
    var onMenu: (EditorV2Exercise) -> Void
    /// AMA-2443 slice 3 — "＋ Add here": open the picker with THIS group as the
    /// explicit destination. Does not move the format-group pin (shape B).
    var onAddHere: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                EditorV2GroupPill(
                    group: group,
                    isInsertionTarget: isInsertionTarget,
                    onTap: onPill
                )
                Spacer()
                Button(action: onAddHere) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add here")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(group.type.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(group.type.accentColor.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editor_v2_add_here_\(group.id)")
            }
            VStack(spacing: 0) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    EditorV2ExerciseCard(
                        exercise: exercise,
                        inGroup: true,
                        isFirst: index == 0,
                        onOpen: { onOpen(exercise) },
                        onMenu: { onMenu(exercise) }
                    )
                }
            }
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isInsertionTarget
                            ? group.type.accentColor.opacity(0.7)
                            : DailyDriver.border,
                        lineWidth: isInsertionTarget ? 1.5 : 1
                    )
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(group.type.accentColor)
                    .frame(width: isInsertionTarget ? 4 : 3)
                    .padding(.vertical, 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.bottom, 10)
        .accessibilityIdentifier(
            isInsertionTarget
                ? "editor_v2_grouped_run_active_\(group.id)"
                : "editor_v2_grouped_run_\(group.id)"
        )
    }
}

// MARK: - Reorder row

struct EditorV2ReorderRow: View {
    let exercise: EditorV2Exercise
    let group: EditorV2Group?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .ddDisplayText(13, weight: .semibold)
                    .foregroundColor(DailyDriver.foreground)
                if let group {
                    Text(group.name.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(group.type.accentColor)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if let group {
                RoundedRectangle(cornerRadius: 2)
                    .fill(group.type.accentColor)
                    .frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Flow wrap (format chips + Runs-as chips)

struct EditorV2FlowWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var originX: CGFloat = 0
        var originY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if originX + size.width > maxWidth, originX > 0 {
                originX = 0
                originY += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            originX += size.width + spacing
        }
        return CGSize(width: maxWidth, height: originY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var originX = bounds.minX
        var originY = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if originX + size.width > bounds.maxX, originX > bounds.minX {
                originX = bounds.minX
                originY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: originX, y: originY), proposal: ProposedViewSize(size))
            originX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
