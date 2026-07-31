//
//  AppleWorkoutKitPreviewSheet.swift
//  AmakaFlow
//
//  AMA-2351 / AMA-2360 — preview mapper composition + step list before schedule.
//

import SwiftUI

struct AppleWorkoutKitPreviewSheet: View {
    let workoutName: String
    let meta: WorkoutKitPlanMeta
    let intervalCount: Int
    let stepLines: [String]
    let prefsSummary: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("What we're scheduling")
                    .font(.headline)
                Text(workoutName)
                    .font(.title3.weight(.semibold))
                Text(WorkoutKitRoutingCopy.compositionLine(meta: meta))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("af_apple_wk_composition_line")
                Text(prefsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("af_apple_wk_prefs_summary")
                Text("\(intervalCount) step\(intervalCount == 1 ? "" : "s") from mapper")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !stepLines.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(stepLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                    .accessibilityIdentifier("af_apple_wk_step_list")
                }

                Spacer(minLength: 8)
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
        .presentationDetents([.medium, .large])
    }
}
