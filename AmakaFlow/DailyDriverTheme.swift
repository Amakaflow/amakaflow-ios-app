//
//  DailyDriverTheme.swift
//  AmakaFlow
//
//  Daily Driver visual language — true black, lime accent, rounded display type,
//  pill CTAs, icon chips, and bottom-sheet chrome (screens-daily-driver.jsx).
//

import SwiftUI

// MARK: - Tokens

enum DailyDriver {
    // MARK: DESIGN.md — dark theme (primary)
    static let ink = Color(hex: "0D1200")
    /// Screen background (`ddBackground` / `--bg`).
    static let screenBackground = Color(hex: "0A0A0A")
    static let backgroundSubtle = Color(hex: "121212")
    static let backgroundElevated = Color(hex: "171717")
    static let foreground = Color(hex: "FAFAFA")
    static let foregroundMuted = Color(hex: "A4A4A4")
    static let foregroundDim = Color(hex: "696969")
    static let border = Color.white.opacity(0.09)
    static let borderStrong = Color.white.opacity(0.16)
    static let inputBackground = Color(hex: "1F1F1F")
    static let lime = Color(hex: "7AB953")
    static let amber = Color(hex: "E0AF3B")
    static let coral = Color(hex: "E95048")
    static let destructive = Color(hex: "D4183D")

    // MARK: DD palette (screens-daily-driver.jsx)
    static let card = Color.white.opacity(0.055)
    static let card2 = Color.white.opacity(0.09)
    static let blue = Color(hex: "5AB8F4")
    static let orange = Color(hex: "F4A24A")
    static let purple = Color(hex: "C58AF4")
    static let red = Color(hex: "F4564A")
    static let tabBarBackground = Color(red: 16 / 255, green: 16 / 255, blue: 18 / 255).opacity(0.96)

    enum Typography {
        /// Poppins when bundled; SF Rounded acceptable until font files land.
        static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
    }
}

extension Font {
    static func ddDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        DailyDriver.Typography.display(size: size, weight: weight)
    }
}

extension View {
    func ddDisplayText(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        font(.ddDisplay(size, weight: weight))
            .kerning(-0.02 * size)
    }

    /// Lime glow for FAB + primary CTAs (DESIGN.md).
    func ddLimeGlow() -> some View {
        shadow(color: DailyDriver.lime.opacity(0.55), radius: 11, x: 0, y: 0)
            .shadow(color: Color.black.opacity(0.5), radius: 9, x: 0, y: 6)
    }

    /// Detail / pushed screens hide the global tab island + FAB (see DDDetailScreen).
    func ddSuppressFloatingChrome(_ suppress: Bool = true) -> some View {
        preference(key: SuppressDDChromeKey.self, value: suppress)
    }
}

struct SuppressDDChromeKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension EnvironmentValues {
    var suppressDDChrome: Bool {
        // Reserved for future environment-based reads.
        false
    }
}

// MARK: - Icon chip

struct DDIconChip: View {
    let systemName: String
    var background: Color = DailyDriver.card2
    var foreground: Color = .white
    var size: CGFloat = 38

    private var cornerRadius: CGFloat { max(8, size * 0.29) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(background)
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundColor(foreground)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Door row (Create sheet)

struct DDDoorRow: View {
    let icon: String
    let iconBackground: Color
    var iconForeground: Color = .white
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(iconForeground)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .ddDisplayText(14.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(DailyDriver.foregroundMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DailyDriver.card)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat tile (Profile)

struct DDStatTile: View {
    let value: String
    let label: String
    var valueColor: Color = DailyDriver.foreground
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .ddDisplayText(21, weight: .heavy)
                        .foregroundColor(valueColor)
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Week dots

struct DDWeekDots: View {
    let labels: [String]
    let activeIndices: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let active = activeIndices.contains(index)
                Text(label)
                    .ddDisplayText(10.5, weight: .bold)
                    .foregroundColor(active ? DailyDriver.ink : DailyDriver.foregroundDim)
                    .frame(width: 28, height: 28)
                    .background(active ? DailyDriver.lime : DailyDriver.card2)
                    .clipShape(Circle())
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - URL pill input

struct DDURLPillInput: View {
    @Binding var text: String
    var placeholder: String = "Paste a workout link…"
    var onPaste: (() -> Void)?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundMuted)

            TextField(placeholder, text: $text)
                .font(.system(size: 12.5))
                .foregroundColor(text.isEmpty ? DailyDriver.foregroundMuted : DailyDriver.foreground)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1)

            Button("Paste") {
                if let onPaste {
                    onPaste()
                } else if let clip = UIPasteboard.general.string {
                    text = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .ddDisplayText(11, weight: .bold)
            .foregroundColor(DailyDriver.lime)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            Capsule(style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(Capsule(style: .continuous))
    }
}

// MARK: - Import processing animation

struct DDImportProcessingView: View {
    let urlPreview: String
    @Binding var stepIndex: Int
    let steps: [String]

    @State private var spin = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 2.5)
                    .frame(width: 84, height: 84)

                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(DailyDriver.lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 84, height: 84)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)

                Circle()
                    .fill(DailyDriver.lime)
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: "link")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(DailyDriver.ink)
                    }
                    .shadow(color: DailyDriver.lime.opacity(0.35), radius: 12)
            }
            .padding(.bottom, 18)
            .onAppear { spin = true }

            Text(steps[safe: stepIndex] ?? steps.last ?? "Importing…")
                .ddDisplayText(15, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .id(stepIndex)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.35), value: stepIndex)

            Text(urlPreview)
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineLimit(1)
                .padding(.top, 4)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(DailyDriver.lime)
                        .frame(width: geo.size.width * progress)
                        .shadow(color: DailyDriver.lime.opacity(0.4), radius: 6)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 8)
            .padding(.top, 18)

            Text("STEP \(min(stepIndex + 1, steps.count)) OF \(steps.count)")
                .font(Theme.Typography.label)
                .foregroundColor(DailyDriver.foregroundDim)
                .padding(.top, 8)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
    }

    private var progress: CGFloat {
        guard !steps.isEmpty else { return 0 }
        return CGFloat(min(stepIndex + 1, steps.count)) / CGFloat(steps.count)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Bottom sheet chrome

struct DDBottomSheetChrome<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(DailyDriver.borderStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            if let title {
                Text(title)
                    .ddDisplayText(17, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            content
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(DailyDriver.backgroundElevated)
    }
}

extension View {
    func ddBottomSheet<Content: View>(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented) {
            content()
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
                .presentationBackground(DailyDriver.backgroundElevated)
        }
    }

    func ddBottomSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item) { value in
            content(value)
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
                .presentationBackground(DailyDriver.backgroundElevated)
        }
    }
}

// MARK: - Settings accordion group

struct DDSettingsGroup<Content: View>: View {
    let title: String
    let summary: String
    let icon: String
    var iconBackground: Color = DailyDriver.card2
    var defaultOpen: Bool = false
    let rowCount: Int
    @ViewBuilder let content: Content

    @State private var isOpen: Bool

    init(
        title: String,
        summary: String,
        icon: String,
        iconBackground: Color = DailyDriver.card2,
        defaultOpen: Bool = false,
        rowCount: Int,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.icon = icon
        self.iconBackground = iconBackground
        self.defaultOpen = defaultOpen
        self.rowCount = rowCount
        self.content = content()
        _isOpen = State(initialValue: defaultOpen)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 12) {
                    DDIconChip(systemName: icon, background: iconBackground, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .ddDisplayText(14.5, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                        if !isOpen {
                            Text(summary)
                                .font(.system(size: 10.5))
                                .foregroundColor(DailyDriver.foregroundMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if !isOpen {
                        Text("\(rowCount)")
                            .font(Theme.Typography.label)
                            .foregroundColor(DailyDriver.foregroundDim)
                    }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isOpen ? DailyDriver.lime : DailyDriver.foregroundDim)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(isOpen ? DailyDriver.lime.opacity(0.10) : Color.clear)
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    content
                }
                .padding(.leading, 18)
                .padding(.trailing, 14)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.35))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(DailyDriver.lime.opacity(0.28))
                        .frame(width: 2)
                        .padding(.leading, 18)
                }
            }
        }
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isOpen ? DailyDriver.lime.opacity(0.4) : DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DDSettingsRow<Trailing: View>: View {
    let icon: String
    var iconBackground: Color = DailyDriver.card2
    var titleColor: Color = DailyDriver.foreground
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            DDIconChip(systemName: icon, background: iconBackground, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(titleColor)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DailyDriver.border)
                .frame(height: 1)
        }
    }
}

// MARK: - Floating tab bar + FAB

struct DDFloatingTabBar: View {
    let selectedTab: AFTab
    let onSelect: (AFTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AFTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selectedTab == tab ? tab.activeIcon : tab.inactiveIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(selectedTab == tab ? DailyDriver.lime : DailyDriver.foregroundDim)
                        Text(tab.title)
                            .ddDisplayText(10, weight: .semibold)
                            .foregroundColor(selectedTab == tab ? DailyDriver.lime : DailyDriver.foregroundDim)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(DailyDriver.tabBarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 15, x: 0, y: 10)
        }
        .padding(.horizontal, 12)
        .accessibilityIdentifier("af_tabbar")
    }
}

struct DDCreateFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 25, weight: .semibold))
                .foregroundColor(DailyDriver.ink)
                .frame(width: 56, height: 56)
                .background(DailyDriver.lime)
                .clipShape(Circle())
                .ddLimeGlow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add workout")
        .accessibilityIdentifier("af_library_fab")
    }
}

#if DEBUG
#Preview("DD doors") {
    ScrollView {
        VStack(spacing: 10) {
            DDDoorRow(
                icon: "link",
                iconBackground: DailyDriver.lime,
                iconForeground: DailyDriver.ink,
                title: "Import from URL",
                subtitle: "Instagram, TikTok, or YouTube"
            ) {}
        }
        .padding()
    }
    .background(DailyDriver.screenBackground)
}
#endif
