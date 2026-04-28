//
//  Theme.swift
//  AmakaFlow
//
//  Design system matching Figma specifications
//

import SwiftUI

struct Theme {
    // MARK: - Colors
    struct Colors {
        // Primary
        static let background = Color(hex: "0D0D0F")
        static let backgroundSubtle = Color(hex: "141418")
        static let surface = Color(hex: "1A1A1E")
        static let surfaceElevated = Color(hex: "1A1A1E")
        
        // Text
        static let textPrimary = Color.white
        static let textSecondary = Color(hex: "9CA3AF")
        static let textTertiary = Color.white.opacity(0.52)
        
        // Accents
        static let accentBlue = Color(hex: "3A8BFF")
        static let accentGreen = Color(hex: "4EDF9B")
        static let accentRed = Color(hex: "EF4444")
        static let accentOrange = Color(hex: "FDE047")
        static let readyHigh = Color(hex: "4EDF9B")
        static let readyModerate = Color(hex: "FDE047")
        static let readyLow = Color(hex: "EF4444")
        static let destructive = Color(hex: "EF4444")

        // Device brand colors
        static let garminBlue = Color(hex: "007ACC")
        static let amazfitOrange = Color(hex: "FF6B00")
        
        // Borders
        static let borderLight = Color.white.opacity(0.08)
        static let borderMedium = Color.white.opacity(0.18)
        static let inputBackground = Color.white.opacity(0.08)
        static let chipBackground = Color.white.opacity(0.08)
        static let accentBackground = Color.white.opacity(0.08)
    }
    
    // MARK: - Typography
    struct Typography {
        // Display
        static let largeTitle = Font.system(size: 24, weight: .semibold, design: .default)
        static let title1 = Font.system(size: 22, weight: .semibold, design: .default)
        static let title2 = Font.system(size: 17, weight: .semibold, design: .default)
        static let title3 = Font.system(size: 14, weight: .semibold, design: .default)
        
        // Body
        static let body = Font.system(size: 13, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 13, weight: .medium, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionBold = Font.system(size: 12, weight: .medium, design: .default)
        static let footnote = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let label = Font.system(size: 10, weight: .medium, design: .monospaced)
        static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }
}

// MARK: - Claude Design helpers
extension Theme {
    struct Ready {
        static func color(for value: Int) -> Color {
            if value >= 70 { return Colors.readyHigh }
            if value >= 45 { return Colors.readyModerate }
            return Colors.readyLow
        }

        static func label(for value: Int) -> String {
            if value >= 70 { return "Ready" }
            if value >= 45 { return "Moderate" }
            return "Recover"
        }
    }
}

struct AFLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.label)
            .tracking(0.8)
            .foregroundColor(Theme.Colors.textSecondary)
    }
}

struct AFCard<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }
}

struct AFChip: View {
    let text: String
    var outline = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.Colors.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(outline ? Color.clear : Theme.Colors.chipBackground)
            .overlay(
                Capsule().stroke(outline ? Theme.Colors.borderMedium : Color.clear, lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

struct AFPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.bodyBold)
            .foregroundColor(Theme.Colors.surface)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.textPrimary)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct AFGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.bodyBold)
            .foregroundColor(Theme.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Theme.Colors.accentBackground : Color.clear)
            .overlay(Capsule().stroke(Theme.Colors.borderMedium, lineWidth: 1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct AFTopBar<Left: View, Right: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                left
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                right
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .frame(minHeight: 32)

            if let title {
                Text(title)
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }
}

struct AFReadinessRing: View {
    let value: Int
    var size: CGFloat = 76
    var stroke: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.borderLight, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: CGFloat(value) / 100)
                .stroke(
                    Theme.Ready.color(for: value),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.system(size: size * 0.32, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.Colors.textPrimary)
                AFLabel(text: "Readiness")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
