//
//  BuilderV3ExercisePickerSheet+DescribeIt.swift
//  AmakaFlow
//
//  AMA-2450 — "Describe it" natural-language entry (screens-exsearch.jsx browse stage).
//

import SwiftUI

extension BuilderV3ExercisePickerSheet {
    /// Tier-3 natural language, entered from browse rather than from a dead end.
    /// Reuses the same `onAskAmaka` path the did-you-mean state uses — the coach
    /// opens with an empty prefill, ready for a description (ADR-017).
    @ViewBuilder
    var describeItCard: some View {
        if case .add = mode, onAskAmaka != nil {
            Button {
                onAskAmaka?("")
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DailyDriver.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Describe it")
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                        Text("“4 × 800 AT 10K PACE, 90S EASY”")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(DailyDriver.purple.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(DailyDriver.purple.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("builder_v3_describe_it")
        }
    }
}
