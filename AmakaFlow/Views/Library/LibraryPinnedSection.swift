//
//  LibraryPinnedSection.swift
//  AmakaFlow
//
//  AMA-2376: Library home — pinned workouts row. Hidden entirely when there
//  are no pins so it never reserves empty space above Collections.
//

import SwiftUI

/// Derived pin-context line (e.g. "NEXT UP · THU SESSION"). v1 always returns
/// `nil` — no synthetic schedule data until a real scheduler is wired.
typealias PinContextProvider = (_ workoutID: String) -> String?

struct LibraryPinnedSection: View {
    let pinnedWorkouts: [Workout]
    var contextProvider: PinContextProvider = { _ in nil }
    let onSelect: (String) -> Void
    let onUnpin: (String) -> Void

    @State private var isEditing = false

    var body: some View {
        if !pinnedWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DailyDriver.coral)
                        Text("PINNED")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(DailyDriver.foregroundDim)
                    }
                    Spacer(minLength: 0)
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.15)) { isEditing.toggle() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .accessibilityIdentifier("af_pinned_edit")
                }

                VStack(spacing: 8) {
                    ForEach(pinnedWorkouts) { workout in
                        row(for: workout)
                    }
                }
            }
            .accessibilityIdentifier("af_pinned_section")
        }
    }

    @ViewBuilder
    private func row(for workout: Workout) -> some View {
        let presentation = DDLibraryPresentation.row(for: workout)
        let subtitle = contextProvider(workout.id)

        HStack(spacing: 12) {
            Button {
                onSelect(workout.id)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: presentation.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: presentation.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.name)
                            .ddDisplayText(14.5, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle.uppercased())
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(DailyDriver.foregroundDim)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if isEditing {
                Button {
                    onUnpin(workout.id)
                } label: {
                    Image(systemName: "pin.slash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DailyDriver.coral)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_pinned_unpin_\(workout.id)")
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("af_pinned_item_\(workout.id)")
    }
}
