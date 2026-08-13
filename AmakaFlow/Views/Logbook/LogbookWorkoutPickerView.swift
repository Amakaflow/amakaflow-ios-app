//
//  LogbookWorkoutPickerView.swift
//  AmakaFlow
//
//  AMA-2426: pick a library workout (or blank) before opening the logbook.
//

import SwiftUI

struct LogbookWorkoutPickerView: View {
    var workouts: [Workout]
    var onPick: (Workout?) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onPick(nil)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LogbookCopy.startBlank)
                            .ddDisplayText(15, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                        Text("Empty logbook — add exercises as you go")
                            .font(.system(size: 12))
                            .foregroundColor(DailyDriver.foregroundMuted)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(DailyDriver.card)

                ForEach(workouts) { workout in
                    Button {
                        onPick(workout)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.name)
                                .ddDisplayText(15, weight: .bold)
                                .foregroundColor(DailyDriver.foreground)
                            Text("\(workout.exerciseCount) exercises · prefill from plan")
                                .font(.system(size: 12))
                                .foregroundColor(DailyDriver.foregroundMuted)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(DailyDriver.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DailyDriver.screenBackground)
            .navigationTitle(LogbookCopy.pickWorkoutTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("af_logbook_workout_picker")
    }
}
