//
//  CollectionMemberRow.swift
//  AmakaFlow
//
//  AMA-2376 Task 6: a single workout row in `CollectionDetailView`, with
//  Organize-mode selection chrome and a pin marker when globally pinned.
//

import SwiftUI

struct CollectionMemberRow: View {
    let workout: Workout
    let isOrganizing: Bool
    let isSelected: Bool
    let isPinned: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if isOrganizing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? DailyDriver.lime : DailyDriver.foregroundDim)
                }

                let presentation = DDLibraryPresentation.row(for: workout)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: presentation.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: presentation.icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(workout.name)
                            .ddDisplayText(14, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                            .lineLimit(1)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(DailyDriver.coral)
                        }
                    }
                    Text(presentation.meta)
                        .font(.system(size: 10.5))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if !isOrganizing {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
            }
            .padding(10)
            .background(isSelected ? DailyDriver.lime.opacity(0.14) : DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? DailyDriver.lime : DailyDriver.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_collection_member_\(workout.id)")
    }
}
