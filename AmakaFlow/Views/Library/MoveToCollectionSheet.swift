//
//  MoveToCollectionSheet.swift
//  AmakaFlow
//
//  AMA-2376 Task 6: Organize mode "Move to" destination picker — real
//  collections only (Uncategorized is derived, never a valid move target),
//  live workout counts, and inline "+ New collection" creation.
//

import SwiftUI

struct MoveToCollectionSheet: View {
    struct Destination: Identifiable {
        let id: String
        let name: String
        let workoutCount: Int
        let previewWorkout: Workout?
    }

    let destinations: [Destination]
    let onMove: (String) -> Void
    let onCreateAndMove: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingNew = false
    @State private var newCollectionName = ""

    var body: some View {
        DDBottomSheetChrome(title: "Move to") {
            VStack(spacing: 10) {
                if destinations.isEmpty {
                    Text("No other collections yet — create one below.")
                        .font(.system(size: 12))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(destinations) { destination in
                            destinationRow(destination)
                        }
                    }
                }
                .frame(maxHeight: 320)

                newCollectionRow
            }
        }
        .accessibilityIdentifier("af_move_to_collection_sheet")
    }

    private func destinationRow(_ destination: Destination) -> some View {
        Button {
            onMove(destination.id)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                cover(for: destination.previewWorkout)

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .ddDisplayText(14.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .lineLimit(1)
                    Text(destination.workoutCount == 1 ? "1 workout" : "\(destination.workoutCount) workouts")
                        .font(.system(size: 11))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_move_to_\(destination.id)")
    }

    @ViewBuilder
    private func cover(for workout: Workout?) -> some View {
        if let workout {
            let presentation = DDLibraryPresentation.row(for: workout)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: presentation.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: presentation.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(width: 38, height: 38)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DailyDriver.card2)
                Image(systemName: "folder.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .frame(width: 38, height: 38)
        }
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
                    .onSubmit(confirmCreateAndMove)

                Button("Create") {
                    confirmCreateAndMove()
                }
                .ddDisplayText(12.5, weight: .bold)
                .foregroundColor(
                    newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? DailyDriver.foregroundDim
                        : DailyDriver.ink
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? DailyDriver.card2
                        : DailyDriver.lime
                )
                .clipShape(Capsule(style: .continuous))
                .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("af_move_to_new_confirm")
            }
        } else {
            DDDoorRow(
                icon: "plus",
                iconBackground: DailyDriver.lime,
                iconForeground: DailyDriver.ink,
                title: "New collection",
                subtitle: "Create and move here"
            ) {
                isCreatingNew = true
            }
            .accessibilityIdentifier("af_move_to_new")
        }
    }

    private func confirmCreateAndMove() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newCollectionName = ""
        isCreatingNew = false
        onCreateAndMove(trimmed)
        dismiss()
    }
}
