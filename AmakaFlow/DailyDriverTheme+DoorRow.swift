//
//  DailyDriverTheme+DoorRow.swift
//  AmakaFlow
//
//  Create-sheet door row — kept out of DailyDriverTheme.swift for file_length.
//

import SwiftUI

// MARK: - Door row (Create sheet)

struct DDDoorRow<Trailing: View>: View {
    let icon: String
    let iconBackground: Color
    var iconForeground: Color = .white
    let title: String
    let subtitle: String
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String,
        iconBackground: Color,
        iconForeground: Color = .white,
        title: String,
        subtitle: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconBackground = iconBackground
        self.iconForeground = iconForeground
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.trailing = trailing
    }

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
                trailing()
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
