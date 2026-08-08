//
//  ActualsTeachCard.swift
//  AmakaFlow
//
//  AMA-2387: Today empty-state teaching card when no sync source has ever been connected.
//

import SwiftUI

struct ActualsTeachCard: View {
    var onConnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                overlappingSourceChips
                    .padding(.bottom, 14)

                Text(ActualsCopy.teachHeadline)
                    .ddDisplayText(17, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(ActualsCopy.teachSubhead)
                    .font(.system(size: 11.5))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, 8)

                Button(action: onConnect) {
                    Text(ActualsCopy.teachCTA)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(DailyDriver.lime)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .accessibilityIdentifier("af_actuals_connect_cta")

                Text(ActualsCopy.teachTrustLine)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(ActualsCopy.teachCardAccessibilityID)

            Text(ActualsCopy.teachManualAlt)
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    private var overlappingSourceChips: some View {
        HStack(spacing: 0) {
            sourceChip(systemImage: "applewatch", background: DailyDriver.card2)
            sourceChip(systemImage: "applewatch", background: DailyDriver.blue)
                .padding(.leading, -10)
            sourceChip(systemImage: "figure.run", background: Color(red: 252 / 255, green: 76 / 255, blue: 2 / 255))
                .padding(.leading, -10)
        }
    }

    private func sourceChip(systemImage: String, background: Color) -> some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: 40, height: 40)
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

#if DEBUG
#Preview("Actuals teach card") {
    ActualsTeachCard {}
        .padding(18)
        .background(DailyDriver.screenBackground)
        .preferredColorScheme(.dark)
}
#endif
