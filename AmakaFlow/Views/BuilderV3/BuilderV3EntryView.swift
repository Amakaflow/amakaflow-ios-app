//
//  BuilderV3EntryView.swift
//  AmakaFlow
//
//  AMA-2372 — "Build from scratch" entry point. Lands on the type picker
//  first (never an empty Editor v2); routes Lift/Conditioning/Recover seeds
//  into `EditorV2View` and Run seeds into the dedicated run step builder.
//  `TYPE · CHANGE` on either surface calls back here to reopen the picker.
//

import SwiftUI

struct BuilderV3EntryView: View {
    var onSaved: () -> Void = {}

    @State private var selectedSeed: BuilderV3TypeSeed?

    var body: some View {
        Group {
            if let seed = selectedSeed {
                if BuilderV3TypeRegistry.isRunSeed(seed) {
                    BuilderV3RunStepBuilderView(
                        seed: seed,
                        onChangeType: { selectedSeed = nil },
                        onSaved: onSaved
                    )
                } else {
                    WorkoutEditorView(
                        builderV3Seed: seed,
                        onBuilderV3ChangeType: { selectedSeed = nil }
                    )
                }
            } else {
                BuilderV3TypePickerView { seed in selectedSeed = seed }
            }
        }
    }
}

#if DEBUG
#Preview {
    BuilderV3EntryView()
}
#endif
