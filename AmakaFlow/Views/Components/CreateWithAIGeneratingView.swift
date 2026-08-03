//
//  CreateWithAIGeneratingView.swift
//  AmakaFlow
//
//  AMA-2373: Create with AI — staged generating screen (ring, cycling steps,
//  ask echo, attached signal chips, cancel). Daily Driver chrome only; no
//  readiness/history claims are ever rendered here (createWithAI never
//  requests those signals).
//

import Combine
import SwiftUI

struct CreateWithAIGeneratingView: View {
    let ask: String
    let chips: [CreateWithAIContextChip]
    let onCancel: () -> Void

    @State private var stepIndex = 0
    @State private var spin = false
    private let timer = Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()

    private var steps: [String] {
        var result = ["Reading your ask"]
        if chips.contains(.gym) { result.append("Checking your gym equipment") }
        if chips.contains(.profile) { result.append("Applying your training profile") }
        if chips.contains(.memories) { result.append("Recalling coach notes") }
        result.append("Building your session")
        result.append("Finalizing details")
        return result
    }

    private var trimmedAsk: String {
        ask.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 22) {
            ring

            Text(steps[safe: stepIndex] ?? steps.last ?? "Generating…")
                .ddDisplayText(16, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .id(stepIndex)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.3), value: stepIndex)

            if !trimmedAsk.isEmpty {
                Text("“\(trimmedAsk)”")
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("create_with_ai_generating_ask")
            }

            if !chips.isEmpty {
                chipsRow
            }

            Text("STEP \(min(stepIndex + 1, steps.count)) OF \(steps.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)

            Button(action: onCancel) {
                Text("Cancel")
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(DailyDriver.card2)
                    .overlay(Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("create_with_ai_generating_cancel")

            Text(CreateWithAICopy.failureFinePrint)
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 32)
        .onAppear { spin = true }
        .onReceive(timer) { _ in
            stepIndex = (stepIndex + 1) % steps.count
        }
        .accessibilityIdentifier("create_with_ai_generating")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 3)
                .frame(width: 84, height: 84)

            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(DailyDriver.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)

            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(DailyDriver.lime)
        }
    }

    private var chipsRow: some View {
        HStack(spacing: 8) {
            ForEach(chips) { chip in
                HStack(spacing: 6) {
                    Image(systemName: chip.icon)
                    Text(chip.label)
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
            ask: "A 30-minute full-body strength session",
            chips: [.gym, .profile]
        ) {}
    }
    .preferredColorScheme(.dark)
}
#endif
