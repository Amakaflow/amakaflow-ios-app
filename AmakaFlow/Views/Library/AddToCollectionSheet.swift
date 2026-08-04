//
//  AddToCollectionSheet.swift
//  AmakaFlow
//
//  AMA-2376 Task 7: multi-membership picker for a single workout — checkmark
//  rows toggle membership in place, inline "+ New collection" creates and
//  adds immediately. Copy affirms the invariant: a workout can live in
//  several folders, and removing it from one never deletes it.
//

import SwiftUI

struct AddToCollectionSheet: View {
    struct Item: Identifiable {
        let id: String
        let name: String
        let workoutCount: Int
    }

    let items: [Item]
    let memberIDs: Set<String>
    let onToggle: (String, Bool) -> Void
    let onCreateAndAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingNew = false
    @State private var newCollectionName = ""

    var body: some View {
        DDBottomSheetChrome(title: "Add to Collection") {
            VStack(alignment: .leading, spacing: 12) {
                Text("A workout can live in several collections — removing it from one never deletes it.")
                    .font(.system(size: 11.5))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("af_add_to_collection_invariant_copy")

                if items.isEmpty {
                    Text("No collections yet — create one below.")
                        .font(.system(size: 12))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.vertical, 6)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            row(for: item)
                        }
                    }
                }
                .frame(maxHeight: 320)

                newCollectionRow

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .ddDisplayText(13, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DailyDriver.lime)
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_add_to_collection_done")
            }
        }
        .accessibilityIdentifier("af_add_to_collection_sheet")
    }

    private func row(for item: Item) -> some View {
        let isMember = memberIDs.contains(item.id)
        return Button {
            onToggle(item.id, !isMember)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(isMember ? DailyDriver.lime : DailyDriver.foregroundDim)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .lineLimit(1)
                    Text(item.workoutCount == 1 ? "1 workout" : "\(item.workoutCount) workouts")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundColor(DailyDriver.foregroundMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isMember ? DailyDriver.lime.opacity(0.14) : DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isMember ? DailyDriver.lime : DailyDriver.border, lineWidth: isMember ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_add_to_collection_row_\(item.id)")
    }

    @ViewBuilder
    private var newCollectionRow: some View {
        if isCreatingNew {
            HStack(spacing: 10) {
                TextField("Collection name", text: $newCollectionName)
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foreground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DailyDriver.inputBackground)
                    .clipShape(Capsule(style: .continuous))
                    .submitLabel(.done)
                    .onSubmit(confirmCreate)

                Button {
                    confirmCreate()
                } label: {
                    let isDisabled = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Text("Create")
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(isDisabled ? DailyDriver.foregroundDim : DailyDriver.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isDisabled ? DailyDriver.card2 : DailyDriver.lime)
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("af_add_to_collection_new_confirm")
            }
        } else {
            DDDoorRow(
                icon: "plus",
                iconBackground: DailyDriver.lime,
                iconForeground: DailyDriver.ink,
                title: "New collection",
                subtitle: "Create and add here"
            ) {
                isCreatingNew = true
            }
            .accessibilityIdentifier("af_add_to_collection_new")
        }
    }

    private func confirmCreate() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newCollectionName = ""
        isCreatingNew = false
        onCreateAndAdd(trimmed)
    }
}
