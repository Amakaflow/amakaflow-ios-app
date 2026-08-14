//
//  ActualsModeSelectView.swift
//  AmakaFlow
//
//  AMA-2426: "Log your sets" — Quick vs Set by set door (rig panel 4).
//

import SwiftUI

enum ActualsLoggingMode: Equatable {
    case quick
    case setBySet
}

struct ActualsModeSelectView: View {
    let subtitle: String
    var onSelect: (ActualsLoggingMode) -> Void
    var onBack: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onBack?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(ActualsCopy.fillInBackLabel)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

            Text(LogbookCopy.modeSelectTitle)
                .ddDisplayText(22, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 8)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.top, 4)
            }

            VStack(spacing: 12) {
                modeCard(
                    title: LogbookCopy.quickTitle,
                    subtitle: LogbookCopy.quickSubtitle,
                    highlighted: false,
                    accessibilityID: LogbookCopy.modeQuickAccessibilityID
                ) {
                    onSelect(.quick)
                }

                modeCard(
                    title: LogbookCopy.setBySetTitle,
                    subtitle: LogbookCopy.setBySetSubtitle,
                    highlighted: true,
                    accessibilityID: LogbookCopy.modeSetBySetAccessibilityID
                ) {
                    onSelect(.setBySet)
                }
            }
            .padding(.top, 20)

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .accessibilityIdentifier("af_actuals_mode_select")
    }

    private func modeCard(
        title: String,
        subtitle: String,
        highlighted: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Spacer()
                    if highlighted {
                        Text(LogbookCopy.newBadge)
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(DailyDriver.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(DailyDriver.lime)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(highlighted ? DailyDriver.lime : DailyDriver.border, lineWidth: highlighted ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}
