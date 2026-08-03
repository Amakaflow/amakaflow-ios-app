//
//  SuggestWorkoutGeneratingView.swift
//  AmakaFlow
//
//  AMA-2371 — extracted from SuggestWorkoutView to satisfy SwiftLint's
//  file_length / type_body_length (mirrors the AMA-2360
//  WorkoutStartSheetPrefNotes precedent). Hosts the "Generating your
//  workout" staged-progress screen so it stays testable/previewable on its
//  own, independent of the suggestion-results layout.
//

import SwiftUI

struct SuggestWorkoutGeneratingView: View {
    @ObservedObject var viewModel: SuggestWorkoutViewModel
    var onCancel: () -> Void

    @State private var generatingStepIndex = 0
    @State private var generatingRingSpinning = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.Colors.chipBackground)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("suggest_workout_loading_cancel")
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)

            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.lg) {
                generatingRing

                Text(currentGeneratingStep)
                    .afH2()
                    .id(generatingStepIndex)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeOut(duration: 0.3), value: generatingStepIndex)

                if !signalChips.isEmpty {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(signalChips, id: \.self) { chip in
                            AFChip(text: chip, outline: true)
                        }
                    }
                }

                generatingProgress
                    .padding(.horizontal, Theme.Spacing.xl)

                Text(SuggestWorkoutGeneratingCopy.failureFinePrint)
                    .afMuted()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("suggest_workout_loading")
        .task { await cycleGeneratingSteps() }
    }

    private var generatingRing: some View {
        ZStack {
            Circle()
                .stroke(DailyDriver.lime.opacity(0.18), lineWidth: 3)
                .frame(width: 88, height: 88)

            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(DailyDriver.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 88, height: 88)
                .rotationEffect(.degrees(generatingRingSpinning ? 360 : 0))
                .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: generatingRingSpinning)

            Circle()
                .fill(DailyDriver.lime)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(DailyDriver.ink)
                )
                .ddLimeGlow()
        }
        .onAppear { generatingRingSpinning = true }
        .accessibilityHidden(true)
    }

    private var generatingProgress: some View {
        VStack(spacing: Theme.Spacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.chipBackground)
                    Capsule()
                        .fill(DailyDriver.lime)
                        .frame(width: geo.size.width * generatingProgressFraction)
                }
            }
            .frame(height: 4)

            Text(SuggestWorkoutGeneratingCopy.stepProgressLabel(
                step: generatingProgressStep,
                total: SuggestWorkoutGeneratingCopy.steps.count
            ))
            .font(Theme.Typography.label)
            .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    private var currentGeneratingStep: String {
        let steps = SuggestWorkoutGeneratingCopy.steps
        guard !steps.isEmpty else { return "" }
        return steps[generatingStepIndex % steps.count]
    }

    /// AMA-2371 final-review fix (I3): the progress bar and "STEP n OF total"
    /// label must never visibly run backwards within the advertised ~20s
    /// window. `generatingStepIndex` keeps incrementing for as long as
    /// generation takes (and `currentGeneratingStep` keeps cycling through
    /// `steps` above for motion), but the bar/label clamp at the final step
    /// once one full pass completes instead of resetting to 25%.
    private var generatingProgressStep: Int {
        min(generatingStepIndex + 1, SuggestWorkoutGeneratingCopy.steps.count)
    }

    private var generatingProgressFraction: CGFloat {
        let total = SuggestWorkoutGeneratingCopy.steps.count
        guard total > 0 else { return 0 }
        return CGFloat(generatingProgressStep) / CGFloat(total)
    }

    /// Real signal chips derived from the readiness fetch this view model
    /// already makes (AMA-1265's `/coach/fatigue-advice`). Intentionally
    /// does not fabricate SLEEP/HRV numbers the backend hasn't given us —
    /// see `debugPlaceholderSignalChips` for the rig-matching preview-only
    /// fallback used when there's no real signal to show.
    private var realSignalChips: [String] {
        guard viewModel.readinessLevel != .unknown else { return [] }
        return ["READINESS · \(viewModel.readinessLevel.badgeText.uppercased())"]
    }

    private var signalChips: [String] {
        if !realSignalChips.isEmpty { return realSignalChips }
        #if DEBUG
        return Self.debugPlaceholderSignalChips
        #else
        return []
        #endif
    }

    #if DEBUG
    /// Rig-matching placeholders (`SLEEP…`, `HRV…`) for DEBUG/Previews only
    /// when no real readiness signal is available yet — compiled out of
    /// release builds, so production never shows a fake production chip.
    private static let debugPlaceholderSignalChips = ["SLEEP 82", "HRV 61ms", "RHR 54"]
    #endif

    private func cycleGeneratingSteps() async {
        generatingStepIndex = 0
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 2_500_000_000)
            } catch {
                return
            }
            generatingStepIndex += 1
        }
    }
}

#Preview {
    SuggestWorkoutGeneratingView(viewModel: SuggestWorkoutViewModel()) {}
}

#if DEBUG
/// Generating state with a real readiness signal already fetched — shows
/// the `READINESS · GREEN` chip instead of the rig-placeholder fallback.
#Preview("Generating — real signal") {
    let viewModel = SuggestWorkoutViewModel()
    viewModel.readinessLevel = .green
    viewModel.readinessMessage = "Recovery looks solid — HRV and sleep both trended up overnight."
    return SuggestWorkoutGeneratingView(viewModel: viewModel) {}
}
#endif
