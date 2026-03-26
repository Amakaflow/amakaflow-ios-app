//
//  XPBarView.swift
//  AmakaFlow
//
//  XP progress bar showing current level name and XP count.
//  AMA-1285
//

import SwiftUI

struct XPBarView: View {
    let xpTotal: Int
    let currentLevel: Int
    let levelName: String
    let xpToNextLevel: Int
    let xpToday: Int
    let dailyCap: Int

    /// Progress fraction (0.0 - 1.0) within the current level
    private var levelProgress: Double {
        let thresholds = [0, 500, 1500, 3500, 7000, 12000, 20000, 35000, 55000, 80000]
        let idx = max(0, min(currentLevel - 1, thresholds.count - 1))
        let currentThreshold = thresholds[idx]
        if currentLevel >= thresholds.count {
            return 1.0 // Max level
        }
        let nextThreshold = thresholds[min(idx + 1, thresholds.count - 1)]
        let range = nextThreshold - currentThreshold
        guard range > 0 else { return 1.0 }
        return min(1.0, Double(xpTotal - currentThreshold) / Double(range))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Level label + XP count
            HStack {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundColor(levelColor)

                    Text("Lv.\(currentLevel) \(levelName)")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Spacer()

                Text("\(xpTotal) XP")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.surfaceElevated)
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [levelColor, levelColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * levelProgress, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: levelProgress)
                }
            }
            .frame(height: 8)

            // XP to next level
            if xpToNextLevel > 0 {
                Text("\(xpToNextLevel) XP to next level")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            } else {
                Text("Max level reached!")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(levelColor)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
        .accessibilityIdentifier("xp_bar")
    }

    private var levelColor: Color {
        switch currentLevel {
        case 1...2: return Theme.Colors.accentGreen
        case 3...4: return Theme.Colors.accentBlue
        case 5...6: return Theme.Colors.accentOrange
        case 7...8: return Color(hex: "9333EA") // Purple
        case 9...10: return Color(hex: "FFD700") // Gold
        default: return Theme.Colors.accentBlue
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        XPBarView(
            xpTotal: 1200,
            currentLevel: 2,
            levelName: "Regular",
            xpToNextLevel: 300,
            xpToday: 100,
            dailyCap: 300
        )

        XPBarView(
            xpTotal: 80000,
            currentLevel: 10,
            levelName: "Legend",
            xpToNextLevel: 0,
            xpToday: 200,
            dailyCap: 300
        )
    }
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
