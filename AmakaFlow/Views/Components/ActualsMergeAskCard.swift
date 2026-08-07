//
//  ActualsMergeAskCard.swift
//  AmakaFlow
//
//  AMA-2387: uncertain duplicate — "Same session?" (screens-actuals2.jsx).
//

import SwiftUI

struct ActualsMergeAskCard: View {
    let left: ActualsSourceRecording
    let right: ActualsSourceRecording
    var onMerge: () -> Void
    var onKeepBoth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            candidateRow(left)
            candidateRow(right)

            VStack(alignment: .leading, spacing: 0) {
                Text(ActualsCopy.mergeAskTitle)
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)

                Text(ActualsCopy.mergeAskBody)
                    .font(.system(size: 11))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                HStack(spacing: 8) {
                    Button(action: onMerge) {
                        Text(ActualsCopy.mergeAskConfirmCTA)
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(DailyDriver.lime)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(ActualsCopy.mergeAskMergeAccessibilityID)

                    Button(action: onKeepBoth) {
                        Text(ActualsCopy.mergeAskKeepBothCTA)
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(DailyDriver.card2)
                            .overlay(
                                Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(ActualsCopy.mergeAskKeepAccessibilityID)
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DailyDriver.amber.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.amber.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(ActualsCopy.mergeAskAccessibilityID)

            Text(ActualsCopy.mergeAskFooter)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }

    private func candidateRow(_ recording: ActualsSourceRecording) -> some View {
        HStack(spacing: 12) {
            DDIconChip(
                systemName: recording.provider == .strava ? "figure.run" : "applewatch",
                background: iconBackground(recording.provider),
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(metaLine(recording))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundColor(DailyDriver.borderStrong)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(0.85)
    }

    private func iconBackground(_ provider: ActualsSourceProvider) -> Color {
        switch provider {
        case .appleHealth: return DailyDriver.card2
        case .garmin: return DailyDriver.blue
        case .strava: return Color(hex: "FC4C02")
        }
    }

    private func metaLine(_ recording: ActualsSourceRecording) -> String {
        let mins = max(1, Int((recording.durationSeconds / 60).rounded()))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: recording.startDate)
        let provider = ActualsCopy.sourceDisplayName(recording.provider).uppercased()
        return "\(start) · \(mins)M · \(provider)"
    }
}

#if DEBUG
#Preview("Merge ask") {
    let start = Date()
    ActualsMergeAskCard(
        left: ActualsSourceRecording(
            id: "s1", provider: .strava, deviceKind: .phone,
            title: "Lunch Run / 8.2 km", startDate: start,
            durationSeconds: 59 * 60, distanceMeters: 8200, streamRichness: 2
        ),
        right: ActualsSourceRecording(
            id: "g1", provider: .garmin, deviceKind: .watch,
            title: "Run", startDate: start.addingTimeInterval(60),
            durationSeconds: 58 * 60, distanceMeters: 8100, streamRichness: 3
        ),
        onMerge: {},
        onKeepBoth: {}
    )
    .padding()
    .background(DailyDriver.screenBackground)
}
#endif
