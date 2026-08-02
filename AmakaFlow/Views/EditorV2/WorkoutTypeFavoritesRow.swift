//
//  WorkoutTypeFavoritesRow.swift
//  AmakaFlow
//
//  Create-only shortcuts for frequently used canonical workout types.
//

import SwiftUI

struct WorkoutTypeFavoritesRow: View {
    let presets: [WorkoutTypeItem]
    let selectedCanonicalId: String?
    let onSelect: (WorkoutTypeItem) -> Void
    let onMore: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.id) { preset in
                    favoriteButton(preset)
                }
                moreButton
            }
        }
        .accessibilityIdentifier("workout_type_favorites_row")
    }

    private func favoriteButton(_ preset: WorkoutTypeItem) -> some View {
        let isSelected = selectedCanonicalId == preset.id
        return Button {
            onSelect(preset)
        } label: {
            Text(preset.displayName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? DailyDriver.lime : DailyDriver.foregroundMuted)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(DailyDriver.backgroundElevated)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? DailyDriver.lime : DailyDriver.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("workout_type_favorite_\(preset.id)")
    }

    private var moreButton: some View {
        Button(action: onMore) {
            HStack(spacing: 5) {
                Text("More")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(DailyDriver.foregroundMuted)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(DailyDriver.backgroundElevated)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(DailyDriver.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More workout types")
        .accessibilityHint("Opens workout type choices")
        .accessibilityIdentifier("workout_type_favorites_more")
    }
}

#if DEBUG
#Preview {
    WorkoutTypeFavoritesRow(
        presets: [
            WorkoutTypeItem(
                id: "tempo_run",
                category: "run",
                format: "continuous",
                focus: [],
                displayName: "Tempo Run",
                aliases: [],
                aiPreset: true,
                equipment: [],
                platformTags: [:]
            ),
            WorkoutTypeItem(
                id: "upper_push",
                category: "strength",
                format: "sets_reps",
                focus: [],
                displayName: "Upper Push",
                aliases: [],
                aiPreset: true,
                equipment: [],
                platformTags: [:]
            ),
        ],
        selectedCanonicalId: "tempo_run",
        onSelect: { _ in },
        onMore: {}
    )
    .padding()
    .background(DailyDriver.screenBackground)
    .preferredColorScheme(.dark)
}
#endif
