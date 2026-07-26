//
//  StructureClarifyChipBar.swift
//  AmakaFlow
//
//  AMA-2326 — sticky format chips + Section… label sheet (ADR-017 clarify UX).
//

import SwiftUI

struct StructureClarifySelectionChipBar: View {
    let selectedCount: Int
    var onGroup: (_ type: StructureBlockType, _ label: String?, _ allowSingle: Bool) -> Void
    var onOpenSectionLabel: () -> Void
    var onCancel: () -> Void

    private var formatReady: Bool { selectedCount >= 2 }
    private var softReady: Bool { selectedCount >= 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatReady
                 ? "\(selectedCount) SELECTED — GROUP AS:"
                 : "\(selectedCount) SELECTED — SECTION CHIPS OK · FORMATS NEED 2+")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    chipButton("Superset", enabled: formatReady) {
                        onGroup(.superset, nil, false)
                    }
                    chipButton("Circuit", enabled: formatReady) {
                        onGroup(.circuit, nil, false)
                    }
                    chipButton("EMOM", enabled: formatReady) {
                        onGroup(.emom, nil, false)
                    }
                    chipButton("AMRAP", enabled: formatReady) {
                        onGroup(.amrap, nil, false)
                    }
                    chipButton("Tabata", enabled: formatReady) {
                        onGroup(.tabata, nil, false)
                    }
                    chipButton("For Time", enabled: formatReady) {
                        onGroup(.forTime, nil, false)
                    }
                    chipButton("Warm-up", enabled: softReady, soft: true) {
                        onGroup(.warmup, "Warm-up", true)
                    }
                    chipButton("Cool-down", enabled: softReady, soft: true) {
                        onGroup(.sets, "Cool Down", true)
                    }
                    chipButton("Section…", enabled: softReady, soft: true) {
                        onOpenSectionLabel()
                    }
                    Button("Cancel", action: onCancel)
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(DailyDriver.card2))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("structure_clarify_chip_cancel")
                }
            }
            .accessibilityIdentifier("structure_clarify_chip_bar")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.card.opacity(0.98))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.lime.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chipButton(
        _ title: String,
        enabled: Bool,
        soft: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(DailyDriver.card2))
                .overlay(
                    Capsule().stroke(
                        (soft ? DailyDriver.blue : DailyDriver.amber).opacity(0.45),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .accessibilityIdentifier(
            "structure_clarify_chip_\(title.lowercased().replacingOccurrences(of: "…", with: "section").replacingOccurrences(of: " ", with: "_"))"
        )
    }
}

/// Free-text section label (trim, 40-char cap, last-write-wins).
struct StructureClarifySectionLabelSheet: View {
    @Binding var labelDraft: String
    var isFocused: FocusState<Bool>.Binding
    var onCancel: () -> Void
    var onApply: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Name this section")
                    .ddDisplayText(20, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text("e.g. Accessory, Finisher, Mobility — max 40 characters.")
                    .font(.system(size: 12))
                    .foregroundColor(DailyDriver.foregroundMuted)
                TextField("Section name", text: $labelDraft)
                    .textInputAutocapitalization(.words)
                    .focused(isFocused)
                    .padding(12)
                    .background(DailyDriver.card2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("structure_clarify_section_label_field")
                Spacer()
            }
            .padding(20)
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let trimmed = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onApply(String(trimmed.prefix(40)))
                    }
                    .disabled(labelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("structure_clarify_section_label_apply")
                }
            }
            .onAppear { isFocused.wrappedValue = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
