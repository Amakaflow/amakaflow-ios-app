//
//  LibraryCollectionsGrid.swift
//  AmakaFlow
//
//  AMA-2376: Library home — Collections 2-col grid (named collections +
//  derived Uncategorized). Header always renders (with "+ New") even when
//  the grid itself is empty.
//

import SwiftUI

struct LibraryCollectionsGrid: View {
    let items: [CollectionGridItem]
    let workoutsByID: [String: Workout]
    let onSelectCollection: (String) -> Void
    let onNewCollection: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Collections")
                    .ddDisplayText(19, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                Spacer(minLength: 0)
                Button(action: onNewCollection) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("New")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(DailyDriver.lime)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_collection_new")
            }

            if !items.isEmpty {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        LibraryCollectionCard(
                            item: item,
                            workoutsByID: workoutsByID,
                            action: { onSelectCollection(item.id) }
                        )
                    }
                }
            }
        }
        .accessibilityIdentifier("af_collections_section")
    }
}

private struct LibraryCollectionCard: View {
    let item: CollectionGridItem
    let workoutsByID: [String: Workout]
    let action: () -> Void

    private var previewWorkouts: [Workout] {
        item.workoutIDs.prefix(4).compactMap { workoutsByID[$0] }
    }

    private var caption: String {
        let count = item.workoutIDs.count
        let unit = count == 1 ? "WORKOUT" : "WORKOUTS"
        let duration = CollectionPresentation.formattedTotalDuration(seconds: item.totalSeconds)
        return "\(count) \(unit) · \(duration)"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                collage
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .lineLimit(1)
                    Text(caption)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_collection_card_\(item.id)")
    }

    @ViewBuilder
    private var collage: some View {
        let workouts = previewWorkouts
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                tile(workouts[safe: 0])
                tile(workouts[safe: 1])
            }
            HStack(spacing: 3) {
                tile(workouts[safe: 2])
                tile(workouts[safe: 3])
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func tile(_ workout: Workout?) -> some View {
        guard let workout else {
            return AnyView(
                Rectangle()
                    .fill(DailyDriver.card2)
            )
        }
        let presentation = DDLibraryPresentation.row(for: workout)
        return AnyView(
            ZStack {
                LinearGradient(
                    colors: presentation.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: presentation.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
