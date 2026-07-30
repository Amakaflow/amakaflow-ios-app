//
//  AppleWorkoutKitPreviewSheet.swift
//  AmakaFlow
//
//  AMA-2351 — preview mapper composition before scheduling in Workout.
//

import SwiftUI

struct AppleWorkoutKitPreviewSheet: View {
    let workoutName: String
    let meta: WorkoutKitPlanMeta
    let intervalCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("What we're scheduling")
                    .font(.headline)
                Text(workoutName)
                    .font(.title3.weight(.semibold))
                Text(WorkoutKitRoutingCopy.compositionLine(meta: meta))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("af_apple_wk_composition_line")
                Text("\(intervalCount) step\(intervalCount == 1 ? "" : "s") from mapper")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onConfirm) {
                    Text("Schedule in Workout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("af_apple_wk_preview_confirm")
                Button("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
