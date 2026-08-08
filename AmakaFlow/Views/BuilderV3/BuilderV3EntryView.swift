//
//  BuilderV3EntryView.swift
//  AmakaFlow
//
//  AMA-2372 — "Build from scratch" entry point. Lands on the type picker
//  first (never an empty Editor v2); routes Lift/Conditioning/Recover seeds
//  into `EditorV2View` and Run seeds into the dedicated run step builder.
//  `TYPE · CHANGE` on either surface calls back here to reopen the picker.
//
//  AMA-2387 — optional actuals-capture mode (Map v2 "Build what you did"):
//  custom title + lime session banner; Done lands on match-save (no Library yet).
//

import SwiftUI

struct BuilderV3EntryView: View {
    var onSaved: () -> Void = {}
    /// When set, Builder is capturing actuals for a finished session (Map v2).
    var actualsActivity: ActualsUnmappedActivity?
    var onCaptureComplete: ((ActualsCaptureDraft) -> Void)?

    @State private var selectedSeed: BuilderV3TypeSeed?

    private var isActualsCapture: Bool { onCaptureComplete != nil }

    var body: some View {
        Group {
            if let seed = selectedSeed {
                if BuilderV3TypeRegistry.isRunSeed(seed) {
                    BuilderV3RunStepBuilderView(
                        seed: seed,
                        onChangeType: { selectedSeed = nil },
                        onSaved: {
                            if let onCaptureComplete {
                                onCaptureComplete(
                                    ActualsCaptureDraft(
                                        id: UUID().uuidString,
                                        title: seed.label,
                                        blockSummaries: ["Run steps"],
                                        estimatedMinutes: 40,
                                        source: .built,
                                        sport: WorkoutSport.running.rawValue,
                                        intervals: [
                                            WorkoutSaveInterval(
                                                type: "time",
                                                name: seed.label,
                                                seconds: 40 * 60
                                            )
                                        ],
                                        blocks: nil
                                    )
                                )
                            } else {
                                onSaved()
                            }
                        }
                    )
                } else {
                    WorkoutEditorView(
                        builderV3Seed: seed,
                        onBuilderV3ChangeType: { selectedSeed = nil },
                        onSaved: onSaved,
                        actualsCaptureComplete: onCaptureComplete,
                        actualsSessionBanner: actualsBannerStyle,
                        actualsSuggestedTitle: actualsActivity?.title
                    )
                }
            } else {
                BuilderV3TypePickerView(
                    onSelect: { seed in selectedSeed = seed },
                    title: isActualsCapture
                        ? ActualsCopy.captureBuilderTitle
                        : "What are you building?",
                    subhead: isActualsCapture
                        ? ActualsCopy.captureBuilderSubhead
                        : "Pick a shape and we set the structure — or start blank and let it emerge.",
                    sessionBanner: actualsBannerStyle
                )
            }
        }
    }

    private var actualsBannerStyle: DDStatusBanner.Style? {
        guard let actualsActivity else { return nil }
        return .lime(
            title: ActualsCopy.captureBannerTitle,
            body: ActualsCaptureContext.bannerDetail(for: actualsActivity)
        )
    }
}

#if DEBUG
#Preview {
    BuilderV3EntryView()
}
#endif
