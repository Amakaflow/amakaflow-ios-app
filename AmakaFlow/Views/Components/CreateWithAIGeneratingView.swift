//
//  CreateWithAIGeneratingView.swift
//  AmakaFlow
//
//  AMA-2373: Create with AI — staged generating screen matching the approved
//  rig (ring + ask echo + status + chips + progress bar + cancel). No
//  readiness/history claims are ever rendered here (createWithAI never
//  requests those signals).
//

import SwiftUI

struct CreateWithAIGeneratingView: View {
    let ask: String
    let chips: [CreateWithAIContextChip]
    let onCancel: () -> Void

    @State private var stepIndex = 0
    @State private var ringSpinning = false

    private var steps: [String] {
        var result = ["Reading your ask…"]
        if chips.contains(.gym) { result.append("Checking gym + equipment…") }
        if chips.contains(.profile) { result.append("Applying your training profile…") }
        if chips.contains(.memories) { result.append("Recalling coach notes…") }
        result.append("Picking movements…")
        result.append("Building your session…")
        return result
    }

    private var trimmedAsk: String {
        ask.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Progress bar / STEP label clamp at the final step once one full pass
    /// completes (same AMA-2371 rule — never visibly run backwards).
    private var progressStep: Int {
        min(stepIndex + 1, steps.count)
    }

    private var progressFraction: CGFloat {
        guard !steps.isEmpty else { return 0 }
        return CGFloat(progressStep) / CGFloat(steps.count)
    }

    private var displayStepIndex: Int {
        guard !steps.isEmpty else { return 0 }
        return min(stepIndex, steps.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(width: 36, height: 36)
                        .background(DailyDriver.card2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("create_with_ai_generating_cancel")

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                generatingRing

                if !trimmedAsk.isEmpty {
                    Text("“\(trimmedAsk)”")
                        .font(.system(size: 14).italic())
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 28)
                        .accessibilityIdentifier("create_with_ai_generating_ask")
                }

                Text(steps[safe: displayStepIndex] ?? "Generating…")
                    .ddDisplayText(20, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .multilineTextAlignment(.center)
                    .id(displayStepIndex)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeOut(duration: 0.3), value: displayStepIndex)
                    .padding(.horizontal, 24)

                if !chips.isEmpty {
                    chipsRow
                }

                progressSection
                    .padding(.horizontal, 36)
                    .padding(.top, 8)

                Text(CreateWithAICopy.failureFinePrint)
                    .font(.system(size: 11))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await cycleSteps() }
        .accessibilityIdentifier("create_with_ai_generating")
    }

    /// Fixed-size ZStack + filled center disc. The orphaned-arc bug came from
    /// animating a bare `Circle().trim` without a stable frame/center glyph —
    /// the rotating stroke's layout bounds drifted off the sparkles.
    private var generatingRing: some View {
        ZStack {
            Circle()
                .stroke(DailyDriver.lime.opacity(0.18), lineWidth: 3)
                .frame(width: 88, height: 88)

            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(DailyDriver.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 88, height: 88)
                .rotationEffect(.degrees(-90))
                .rotationEffect(.degrees(ringSpinning ? 360 : 0))
                .animation(
                    .linear(duration: 1.1).repeatForever(autoreverses: false),
                    value: ringSpinning
                )

            Circle()
                .fill(DailyDriver.lime)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(DailyDriver.ink)
                )
                .ddLimeGlow()
        }
        .frame(width: 88, height: 88)
        .onAppear { ringSpinning = true }
        .accessibilityHidden(true)
    }

    private var chipsRow: some View {
        HStack(spacing: 8) {
            ForEach(chips) { chip in
                HStack(spacing: 6) {
                    Image(systemName: chip.icon)
                    Text(chip.label.uppercased())
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(DailyDriver.card)
                .overlay(Capsule().stroke(DailyDriver.border, lineWidth: 1))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 24)
    }

    private var progressSection: some View {
        VStack(spacing: Theme.Spacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DailyDriver.card2)
                    Capsule()
                        .fill(DailyDriver.lime)
                        .frame(width: max(4, geo.size.width * progressFraction))
                }
            }
            .frame(height: 4)

            Text("STEP \(progressStep) OF \(steps.count) · \(CreateWithAICopy.usuallyUnder)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
        }
    }

    private func cycleSteps() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            stepIndex += 1
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#if DEBUG
#Preview {
    ZStack {
        DailyDriver.screenBackground.ignoresSafeArea()
        CreateWithAIGeneratingView(
            ask: "Chest pump, about 45 minutes, nothing on cables",
            chips: [.gym, .profile]
        ) {}
    }
    .preferredColorScheme(.dark)
}
#endif
