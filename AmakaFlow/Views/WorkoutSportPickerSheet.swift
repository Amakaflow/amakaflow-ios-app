//
//  WorkoutSportPickerSheet.swift
//  AmakaFlow
//
//  AMA-2393 — single-choice sport sheet for the detail type chip.
//

import SwiftUI

struct WorkoutSportPickerSheet: View {
    let selected: WorkoutSport
    let footnote: String
    let onSelect: (WorkoutSport) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(footnote)
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                List {
                    ForEach(WorkoutSport.pickerOptions, id: \.self) { sport in
                        Button(
                            action: { onSelect(sport) },
                            label: {
                                HStack {
                                    Text(sport.displayName)
                                        .foregroundColor(DailyDriver.foreground)
                                    Spacer()
                                    if sport == selected {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Color(hex: "7AB953"))
                                    }
                                }
                            }
                        )
                        .accessibilityIdentifier("af_sport_picker_\(sport.rawValue)")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(DailyDriver.screenBackground)
            .navigationTitle("Workout type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(DailyDriver.screenBackground)
    }
}
