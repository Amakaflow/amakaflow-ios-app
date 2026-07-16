//
//  Theme.swift
//  AmakaFlow
//
//  Unified AmakaFlow design system: tokens, typography, and SwiftUI primitives.
//

import CoreText
import SwiftUI
import UIKit

struct Theme {
    // MARK: - Colors
    struct Colors {
        // Primary surfaces — dark values aligned with DailyDriver (DESIGN.md)
        static let background = Color(light: Color(hex: "FFFFFF"), dark: Color(hex: "0A0A0A"))
        static let backgroundSubtle = Color(light: Color(hex: "F7F7F8"), dark: Color(hex: "121212"))
        static let surface = Color(light: Color(hex: "FFFFFF"), dark: Color.white.opacity(0.055))
        static let surfaceElevated = Color(light: Color(hex: "FFFFFF"), dark: Color.white.opacity(0.09))

        // Text
        static let textPrimary = Color(light: Color(hex: "0A0A0A"), dark: Color(hex: "FAFAFA"))
        static let textSecondary = Color(light: Color(hex: "66667A"), dark: Color(hex: "A4A4A4"))
        static let textTertiary = Color(light: Color(hex: "9093A0"), dark: Color(hex: "696969"))

        // Accents
        static let accentBlue = Color(hex: "3A8BFF")
        static let accentGreen = Color(hex: "7AB953")
        static let accentRed = Color(hex: "E95049")
        static let accentOrange = Color(hex: "E0B03C")
        static let readyHigh = Color(hex: "7AB953")
        static let readyModerate = Color(hex: "E0B03C")
        static let readyLow = Color(hex: "E95049")
        static let destructive = Color(hex: "D4183D")

        // Device brand colors
        static let garminBlue = Color(hex: "007ACC")
        static let amazfitOrange = Color(hex: "FF6B00")

        // Borders + controls
        static let borderLight = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.09))
        static let borderMedium = Color(light: Color.black.opacity(0.14), dark: Color.white.opacity(0.16))
        static let inputBackground = Color(light: Color(hex: "F3F3F5"), dark: Color(hex: "1F1F1F"))
        static let chipBackground = Color(light: Color(hex: "ECECF0"), dark: Color.white.opacity(0.09))
        static let accentBackground = Color(light: Color(hex: "ECECF0"), dark: Color.white.opacity(0.09))
        static let primary = Color(light: Color(hex: "030213"), dark: Color(hex: "FFFFFF"))
        static let primaryForeground = Color(light: Color(hex: "FFFFFF"), dark: Color(hex: "1F1F1F"))
    }

    // MARK: - Typography
    struct Typography {
        // Display
        static let largeTitle = Font.geist(24, .semibold)
        static let title1 = Font.geist(22, .semibold)
        static let title2 = Font.geist(17, .semibold)
        static let title3 = Font.geist(14, .semibold)

        // Body
        static let body = Font.geist(13, .regular)
        static let bodyBold = Font.geist(13, .medium)
        static let caption = Font.geist(12, .regular)
        static let captionBold = Font.geist(12, .medium)
        static let footnote = Font.geistMono(11, .regular)
        static let label = Font.geistMono(10, .medium)
        static let mono = Font.geistMono(12, .medium)

        // CSS-aligned text styles
        static let afH1 = Font.geist(22, .semibold)
        static let afH2 = Font.geist(17, .semibold)
        static let afH3 = Font.geist(14, .semibold)
        static let afBody = Font.geist(13, .regular)
        static let afMuted = Font.geist(13, .regular)
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

// MARK: - Geist font registration + helpers
extension Theme {
    enum Fonts {
        enum Family {
            case geist
            case geistMono
        }

        private static let fontFiles = [
            "Geist-Regular.ttf",
            "Geist-Medium.ttf",
            "Geist-SemiBold.ttf",
            "Geist-Bold.ttf",
            "GeistMono-Regular.ttf",
            "GeistMono-Medium.ttf",
            "GeistMono-SemiBold.ttf",
            "GeistMono-Bold.ttf"
        ]

        private static var didAttemptRegistration = false

        static let allPostScriptNames = fontFiles.map { $0.replacingOccurrences(of: ".ttf", with: "") }

        static func postScriptName(family: Family, weight: Font.Weight) -> String {
            let prefix: String
            switch family {
            case .geist: prefix = "Geist"
            case .geistMono: prefix = "GeistMono"
            }
            return "\(prefix)-\(fontWeightName(for: weight))"
        }

        static func ensureRegistered() {
            guard !didAttemptRegistration else { return }
            didAttemptRegistration = true

            for filename in fontFiles {
                guard UIFont(name: filename.replacingOccurrences(of: ".ttf", with: ""), size: 12) == nil else {
                    continue
                }
                registerFont(named: filename)
            }
        }

        static func areLoaded() -> Bool {
            ensureRegistered()
            return allPostScriptNames.allSatisfy { UIFont(name: $0, size: 12) != nil }
        }

        static func assertLoaded() {
            #if DEBUG
            guard areLoaded() else {
                assertionFailure("Geist fonts failed to load. Check UIAppFonts filenames and Font.custom PostScript names: \(allPostScriptNames.joined(separator: ", "))")
                return
            }
            #else
            _ = areLoaded()
            #endif
        }

        private static func fontWeightName(for weight: Font.Weight) -> String {
            if weight == .bold || weight == .heavy || weight == .black {
                return "Bold"
            }
            if weight == .semibold {
                return "SemiBold"
            }
            if weight == .medium {
                return "Medium"
            }
            return "Regular"
        }

        private static func registerFont(named filename: String) {
            let candidateBundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
            let candidateURLs = candidateBundles.flatMap { bundle -> [URL] in
                [
                    bundle.url(forResource: filename, withExtension: nil),
                    bundle.url(forResource: filename, withExtension: nil, subdirectory: "Fonts")
                ].compactMap { $0 }
            }

            for url in candidateURLs {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                if UIFont(name: filename.replacingOccurrences(of: ".ttf", with: ""), size: 12) != nil {
                    return
                }
            }
        }
    }

    struct Ready {
        enum Level {
            case high
            case moderate
            case low
        }

        static func level(for value: Int) -> Level {
            if value >= 70 { return .high }
            if value >= 45 { return .moderate }
            return .low
        }

        static func color(for value: Int) -> Color {
            switch level(for: value) {
            case .high: return Colors.readyHigh
            case .moderate: return Colors.readyModerate
            case .low: return Colors.readyLow
            }
        }

        static func label(for value: Int) -> String {
            switch level(for: value) {
            case .high: return "Ready"
            case .moderate: return "Moderate"
            case .low: return "Recover"
            }
        }
    }
}

extension Font {
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Theme.Fonts.assertLoaded()
        return .custom(Theme.Fonts.postScriptName(family: .geist, weight: weight), size: size)
    }

    static func geistMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Theme.Fonts.assertLoaded()
        return .custom(Theme.Fonts.postScriptName(family: .geistMono, weight: weight), size: size)
    }
}

// MARK: - Text styles
struct AFTextStyleModifier: ViewModifier {
    enum Style {
        case h1
        case h2
        case h3
        case body
        case muted
    }

    let style: Style

    func body(content: Content) -> some View {
        switch style {
        case .h1:
            content
                .font(Theme.Typography.afH1)
                .lineSpacing(0)
                .foregroundColor(Theme.Colors.textPrimary)
        case .h2:
            content
                .font(Theme.Typography.afH2)
                .foregroundColor(Theme.Colors.textPrimary)
        case .h3:
            content
                .font(Theme.Typography.afH3)
                .foregroundColor(Theme.Colors.textPrimary)
        case .body:
            content
                .font(Theme.Typography.afBody)
                .lineSpacing(4)
                .foregroundColor(Theme.Colors.textPrimary)
        case .muted:
            content
                .font(Theme.Typography.afMuted)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}

extension View {
    func afH1() -> some View { modifier(AFTextStyleModifier(style: .h1)) }
    func afH2() -> some View { modifier(AFTextStyleModifier(style: .h2)) }
    func afH3() -> some View { modifier(AFTextStyleModifier(style: .h3)) }
    func afBody() -> some View { modifier(AFTextStyleModifier(style: .body)) }
    func afMuted() -> some View { modifier(AFTextStyleModifier(style: .muted)) }
}

// MARK: - Core primitives
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
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AFChip: View {
    let text: String
    var outline = false

    var body: some View {
        Text(text)
            .font(Theme.Typography.footnote.weight(.medium))
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

enum AFButtonSize {
    case sm
    case md
    case lg
    case xl

    var font: Font {
        switch self {
        case .sm: return .ddDisplay(12, weight: .bold)
        case .md: return .ddDisplay(13, weight: .bold)
        case .lg: return .ddDisplay(15, weight: .bold)
        case .xl: return .ddDisplay(16, weight: .bold)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .sm: return 12
        case .md: return 16
        case .lg: return 20
        case .xl: return 24
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .sm: return 6
        case .md: return 10
        case .lg: return 14
        case .xl: return 18
        }
    }
}

struct AFPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var size: AFButtonSize = .md
    var isWide = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundColor(DailyDriver.ink)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(maxWidth: isWide ? .infinity : nil)
            .background(DailyDriver.lime)
            .clipShape(Capsule(style: .continuous))
            .ddLimeGlow()
            .opacity(isEnabled ? 1 : 0.52)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct AFGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var size: AFButtonSize = .md
    var isWide = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundColor(DailyDriver.foreground)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(maxWidth: isWide ? .infinity : nil)
            .background(configuration.isPressed ? DailyDriver.card2 : Color.clear)
            .overlay(Capsule(style: .continuous).stroke(DailyDriver.borderStrong, lineWidth: 1))
            .clipShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.52)
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
                    .ddDisplayText(20, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }
}

extension AFTopBar where Left == AFBackChevron {
    /// Convenience init for screens with a standard back chevron on the left.
    /// Centralizes the "Back" accessibility label/identifier so every consumer
    /// gets it for free (AMA-1621). Pass a screen-scoped identifier when two
    /// AFTopBar screens may stack (e.g. "af_topbar_back_settings").
    init(
        title: String? = nil,
        subtitle: String? = nil,
        backIdentifier: String = "af_topbar_back",
        backAction: @escaping () -> Void,
        @ViewBuilder right: () -> Right
    ) {
        self.title = title
        self.subtitle = subtitle
        self.left = AFBackChevron(identifier: backIdentifier, action: backAction)
        self.right = right()
    }
}

extension AFTopBar where Right == AFTopBarSkipButton {
    /// Convenience init for screens with a Skip button on the right.
    /// Centralizes the styling and accessibility identifier so consumers
    /// don't repeat the per-screen Button/font/color/identifier boilerplate
    /// (AMA-1647). When `skipAction` is nil, no button renders — useful
    /// for screens that conditionally allow skipping.
    init(
        title: String? = nil,
        subtitle: String? = nil,
        skipIdentifier: String = "af_topbar_skip",
        skipAction: (() -> Void)?,
        @ViewBuilder left: () -> Left
    ) {
        self.title = title
        self.subtitle = subtitle
        self.left = left()
        self.right = AFTopBarSkipButton(identifier: skipIdentifier, action: skipAction)
    }
}

struct AFTopBarSkipButton: View {
    let identifier: String
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button("Skip", action: action)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .accessibilityIdentifier(identifier)
        }
    }
}

struct AFBackChevron: View {
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
        }
        .accessibilityLabel("Back")
        .accessibilityIdentifier(identifier)
    }
}

struct AFReadinessRing: View {
    let value: Int
    var size: CGFloat = 76
    var stroke: CGFloat = 6

    private var clampedValue: Int {
        min(max(value, 0), 100)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.borderLight, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: CGFloat(clampedValue) / 100)
                .stroke(
                    Theme.Ready.color(for: clampedValue),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(clampedValue)")
                    .font(Font.geistMono(size * 0.32, .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                AFLabel(text: "Readiness")
                    .font(Font.geistMono(8, .medium))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Missing primitives
struct AFSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    var label: (Option) -> String

    init(
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    init(options: [Option], selection: Binding<Option>) where Option: CustomStringConvertible {
        self.init(options: options, selection: selection) { $0.description }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(Font.geist(12, .medium))
                        .foregroundColor(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? Theme.Colors.surfaceElevated : Color.clear)
                        .clipShape(Capsule())
                        .shadow(color: isSelected ? Color.black.opacity(0.06) : .clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.Colors.inputBackground)
        .clipShape(Capsule())
    }
}

struct AFSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.Colors.primary : Theme.Colors.borderMedium)
                    .frame(width: 36, height: 20)
                Circle()
                    .fill(isOn ? Theme.Colors.background : Color.white)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .frame(width: 36, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

struct AFProgressBar: View {
    let progress: Double

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.inputBackground)
                Capsule()
                    .fill(Theme.Colors.textPrimary)
                    .frame(width: proxy.size.width * clampedProgress)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .accessibilityValue("\(Int(clampedProgress * 100)) percent")
    }
}

struct AFRPEGrid: View {
    @Binding var selection: Int?
    var range: ClosedRange<Int> = 1...10

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
            ForEach(Array(range), id: \.self) { value in
                let isSelected = value == selection
                Button {
                    selection = value
                } label: {
                    Text("\(value)")
                        .font(Theme.Typography.mono)
                        .foregroundColor(isSelected ? Theme.Colors.primaryForeground : Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(isSelected ? Theme.Colors.primary : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? Theme.Colors.primary : Theme.Colors.borderMedium, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("RPE \(value)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct AFBottomSheet<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Theme.Colors.borderMedium)
                .frame(width: 36, height: 4)
                .accessibilityHidden(true)

            if let title {
                Text(title)
                    .afH2()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            content
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.surfaceElevated)
        .foregroundColor(Theme.Colors.textPrimary)
    }
}

extension View {
    func afBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented) {
            AFBottomSheet(content: content)
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
                .presentationBackground(Theme.Colors.surfaceElevated)
        }
    }
}

struct AFInput: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var accessibilityIdentifier: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .focused($isFocused)
        .font(Theme.Typography.body)
        .foregroundColor(Theme.Colors.textPrimary)
        .tint(Theme.Colors.readyHigh)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isFocused ? Theme.Colors.surfaceElevated : Theme.Colors.inputBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm, style: .continuous)
                .stroke(isFocused ? Theme.Colors.borderMedium : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm, style: .continuous))
        .accessibilityIdentifier(accessibilityIdentifier ?? "af_input")
    }
}

struct AFDot: View {
    let level: Theme.Ready.Level

    init(level: Theme.Ready.Level) {
        self.level = level
    }

    init(value: Int) {
        self.level = Theme.Ready.level(for: value)
    }

    private var color: Color {
        switch level {
        case .high: return Theme.Colors.readyHigh
        case .moderate: return Theme.Colors.readyModerate
        case .low: return Theme.Colors.readyLow
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.18), radius: 0, x: 0, y: 0)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 3)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Color Extension
extension Color {
    init(light: Color, dark: Color) {
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

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

// MARK: - Previews
#if DEBUG
private struct AFPrimitivePreview: View {
    @State private var segment = "Week"
    @State private var isSwitchOn = true
    @State private var rpe: Int? = 7
    @State private var input = "Geist + lime tokens"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AFTopBar(
                    title: "Design system",
                    subtitle: "Lime + Geist + light/dark",
                    backAction: {},
                    right: { AFChip(text: "AMA-1991") }
                )
                .padding(.horizontal, -Theme.Spacing.lg)

                Text("Foundation primitives").afH1()
                Text("All controls inherit dynamic tokens and bundled Geist fonts.").afMuted()

                AFCard {
                    VStack(alignment: .leading, spacing: 12) {
                        AFLabel(text: "Readiness")
                        HStack(spacing: 12) {
                            AFReadinessRing(value: 82, size: 86)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { AFDot(level: .high); Text("Ready").afBody() }
                                HStack { AFDot(level: .moderate); Text("Moderate").afBody() }
                                HStack { AFDot(level: .low); Text("Recover").afBody() }
                            }
                        }
                    }
                }

                AFSegmentedControl(options: ["Day", "Week", "Month"], selection: $segment)
                AFSwitch(isOn: $isSwitchOn)
                AFProgressBar(progress: 0.68)
                AFRPEGrid(selection: $rpe)
                AFInput(placeholder: "Workout name", text: $input)

                AFBottomSheet(title: "Bottom sheet") {
                    Text("Sheet content uses the elevated surface token and native detents when presented.")
                        .afBody()
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xl, style: .continuous))

                HStack {
                    Button("Small") {}
                        .buttonStyle(AFPrimaryButtonStyle(size: .sm, isWide: false))
                    Button("Medium") {}
                        .buttonStyle(AFGhostButtonStyle(size: .md, isWide: false))
                    Button("Large") {}
                        .buttonStyle(AFPrimaryButtonStyle(size: .lg, isWide: false))
                }

                HStack {
                    AFChip(text: "Filled")
                    AFChip(text: "Outline", outline: true)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
    }
}

#Preview("AF primitives — light") {
    AFPrimitivePreview()
        .preferredColorScheme(.light)
}

#Preview("AF primitives — dark") {
    AFPrimitivePreview()
        .preferredColorScheme(.dark)
}
#endif
