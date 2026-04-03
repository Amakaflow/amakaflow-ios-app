//
//  BalanceIndicatorsView.swift
//  AmakaFlow
//
//  Push/Pull and Upper/Lower balance ratio gauges (AMA-1414)
//

import SwiftUI

struct BalanceIndicatorsView: View {
    let pushPullRatio: Double?
    let upperLowerRatio: Double?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let ratio = pushPullRatio {
                balanceGauge(label: "Push / Pull", ratio: ratio)
            }
            if let ratio = upperLowerRatio {
                balanceGauge(label: "Upper / Lower", ratio: ratio)
            }
            if pushPullRatio == nil && upperLowerRatio == nil {
                Text("Not enough data for balance analysis")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private func balanceGauge(label: String, ratio: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(String(format: "%.2f:1", ratio))
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(balanceColor(ratio))
                statusBadge(ratio)
            }

            // Gauge track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.surface)
                        .frame(height: 8)

                    // Balanced zone highlight (0.8-1.2 mapped to track)
                    let zoneStart = mapRatioToPosition(0.8, width: geo.size.width)
                    let zoneEnd = mapRatioToPosition(1.2, width: geo.size.width)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.accentGreen.opacity(0.2))
                        .frame(width: zoneEnd - zoneStart, height: 8)
                        .offset(x: zoneStart)

                    // Position indicator
                    let pos = mapRatioToPosition(ratio, width: geo.size.width)
                    Circle()
                        .fill(balanceColor(ratio))
                        .frame(width: 14, height: 14)
                        .offset(x: pos - 7)
                }
            }
            .frame(height: 14)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func mapRatioToPosition(_ ratio: Double, width: Double) -> Double {
        // Map ratio 0.5-1.5 to 0-width
        let clamped = min(max(ratio, 0.5), 1.5)
        return (clamped - 0.5) / 1.0 * width
    }

    private func balanceColor(_ ratio: Double) -> Color {
        if ratio >= 0.8 && ratio <= 1.2 { return Theme.Colors.accentGreen }
        if ratio >= 0.5 && ratio <= 1.5 { return Theme.Colors.accentOrange }
        return Theme.Colors.accentRed
    }

    private func statusBadge(_ ratio: Double) -> some View {
        let (text, color) = statusInfo(ratio)
        return Text(text)
            .font(Theme.Typography.footnote)
            .foregroundColor(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(Theme.CornerRadius.sm)
    }

    private func statusInfo(_ ratio: Double) -> (String, Color) {
        if ratio >= 0.8 && ratio <= 1.2 { return ("Balanced", Theme.Colors.accentGreen) }
        if ratio >= 0.5 && ratio <= 1.5 { return ("Slightly Off", Theme.Colors.accentOrange) }
        return ("Needs Attention", Theme.Colors.accentRed)
    }
}
