//
//  WatchItemDeliveredStepsOverlay.swift
//  AmakaFlow
//
//  AMA-2388: read-only delivered-steps peek (Strava pattern) — delivered copy
//  watermark; edits below don't change this until Replace.
//

import SwiftUI

struct WatchItemDeliveredStepsOverlay: View {
    let stepCount: Int
    let sections: [PreviewSection]
    var onClose: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                DailyDriver.screenBackground.opacity(0.72)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .onTapGesture(perform: onClose)

                VStack(spacing: 0) {
                    Capsule()
                        // tokens.css `.af-sheet-handle` → `--border-str` (dark)
                        .fill(DailyDriver.borderStrong)
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .accessibilityHidden(true)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(WatchItemCopy.stepsOverlayTitle(count: stepCount))
                            .ddDisplayText(16, weight: .heavy)
                            .foregroundColor(DailyDriver.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(WatchItemCopy.stepsOverlayClose, action: onClose)
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("af_watchitem_steps_close")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                    Text(WatchItemCopy.stepsWatermark)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(sections) { section in
                                band(section)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                    }
                }
                .frame(maxHeight: geo.size.height * 0.86)
                .background(DailyDriver.playerDockBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        // Modal for the whole overlay (panel + scrim), not only the panel.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(WatchItemCopy.stepsOverlayTitle(count: stepCount))
        .accessibilityIdentifier("af_watchitem_steps_overlay")
    }

    private func band(_ section: PreviewSection) -> some View {
        let color = bandColor(section.accent)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(section.band.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                Spacer(minLength: 0)
                // AMA-2390 — surface Circuit "N ROUNDS" like Apple preview header.
                if let tag = section.tag, !tag.isEmpty {
                    Text(tag.uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DailyDriver.card)
            .overlay(alignment: .leading) {
                Rectangle().fill(color).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            ForEach(section.steps) { step in
                HStack(spacing: 10) {
                    Text(stepNumberLabel(step.number))
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .frame(width: 28, alignment: .leading)
                    Text(stepLine(step))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(DailyDriver.foreground)
                    Spacer(minLength: 0)
                    if let restChip = step.restChip, !restChip.isEmpty {
                        Text(restChip)
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)
                    }
                }
                .padding(.vertical, 8)
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DailyDriver.border)
                        .frame(height: 1)
                }
            }
        }
    }

    private func stepNumberLabel(_ number: Int) -> String {
        "\(number)"
    }

    private func stepLine(_ step: PreviewStep) -> String {
        if let detail = step.detail, !detail.isEmpty {
            return "\(step.title) — \(detail)"
        }
        return step.title
    }

    private func bandColor(_ accent: PreviewBandAccent) -> Color {
        switch accent {
        case .mobility: return DailyDriver.blue
        case .work: return DailyDriver.lime
        case .cooldown: return DailyDriver.amber
        }
    }
}
