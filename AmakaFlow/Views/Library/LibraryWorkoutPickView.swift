//
//  LibraryWorkoutPickView.swift
//  AmakaFlow
//
//  AMA-2376 Task 6: multi-select picker for "+ Add workouts" — candidates are
//  Library workouts not already in the current collection (caller filters).
//

import SwiftUI

struct LibraryWorkoutPickView: View {
    let title: String
    let workouts: [Workout]
    let onAdd: ([String]) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var selectedIDs: Set<String> = []

    private var filteredWorkouts: [Workout] {
        guard !searchText.isEmpty else { return workouts }
        return workouts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                DDSearchField(text: $searchText, placeholder: "Search workouts…")
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(filteredWorkouts) { workout in
                            pickRow(workout)
                        }

                        if filteredWorkouts.isEmpty {
                            Text(
                                workouts.isEmpty
                                    ? "Every Library workout is already in this collection."
                                    : "No matches."
                            )
                            .font(.system(size: 12))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 30)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationBarHidden(true)
        .accessibilityIdentifier("af_workout_pick")
    }

    private var header: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundMuted)
                .accessibilityIdentifier("af_workout_pick_cancel")

            Spacer(minLength: 0)

            Text(title)
                .ddDisplayText(15, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                onAdd(Array(selectedIDs))
            } label: {
                Text(selectedIDs.isEmpty ? "Add" : "Add (\(selectedIDs.count))")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(selectedIDs.isEmpty ? DailyDriver.foregroundDim : DailyDriver.lime)
            .disabled(selectedIDs.isEmpty)
            .accessibilityIdentifier("af_workout_pick_add")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private func pickRow(_ workout: Workout) -> some View {
        let isSelected = selectedIDs.contains(workout.id)
        let presentation = DDLibraryPresentation.row(for: workout)

        return Button {
            if isSelected {
                selectedIDs.remove(workout.id)
            } else {
                selectedIDs.insert(workout.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(isSelected ? DailyDriver.lime : DailyDriver.foregroundDim)

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
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .lineLimit(1)
                    Text(presentation.meta)
                        .font(.system(size: 10))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
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
        .accessibilityIdentifier("af_workout_pick_row_\(workout.id)")
    }
}
