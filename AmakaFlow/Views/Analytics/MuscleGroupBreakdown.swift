//
//  MuscleGroupBreakdown.swift
//  AmakaFlow
//
//  Sorted muscle group volume list (AMA-1414)
//

import SwiftUI

struct MuscleGroupBreakdown: View {
    let groups: [(name: String, volume: Double, percentage: Double)]

    var body: some View {
        if groups.isEmpty {
            Text("No muscle group data available")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(groups, id: \.name) { group in
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(group.name.capitalized)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .frame(width: 80, alignment: .leading)

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.Colors.accentBlue)
                                .frame(width: geo.size.width * group.percentage / 100)
                        }
                        .frame(height: 12)

                        Text(formatVolume(group.volume))
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(width: 50, alignment: .trailing)

                        Text(String(format: "%.0f%%", group.percentage))
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: 35, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.1fk", value / 1000) }
        return "\(Int(value))"
    }
}
