//
//  EnrichmentRecoveryRow.swift
//  AmakaFlow
//
//  AMA-2336/2423 — the v1 inline recovery row shared by Rest and Transitions
//  on the watch-ready sheet. Both render identical chrome and differ only in
//  copy plus which override control expands underneath, so the card lives here
//  once (split from WorkoutEnrichmentPushSheet.swift for SwiftLint file_length).
//

import SwiftUI

struct EnrichmentRecoveryRow<Override: View>: View {
    let title: String
    let detail: String?
    /// "You removed this before" hint — the caller decides when it applies.
    let showsTombstoneHint: Bool
    let rowIdentifier: String
    let toggleIdentifier: String
    @Binding var isChecked: Bool
    @ViewBuilder var override: () -> Override

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isChecked) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .monospacedDigit()
                            .multilineTextAlignment(.leading)
                    }
                    if showsTombstoneHint {
                        Text("You removed this before — tick to add it back.")
                            .font(.system(size: 10))
                            .foregroundColor(DailyDriver.amber)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .tint(DailyDriver.lime)
            .accessibilityIdentifier(toggleIdentifier)
            .accessibilityAddTraits(isChecked ? [.isSelected] : [])

            if isChecked {
                override()
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
        .accessibilityIdentifier(rowIdentifier)
    }
}

/// Open-vs-timed segmented control plus the timed stepper, shared by the Rest
/// and Transitions rows (identical control, different copy and bounds).
struct EnrichmentRecoveryOverride: View {
    let openLabel: String
    let timedLabel: String
    let secondsRange: ClosedRange<Int>
    let openIdentifier: String
    let secondsIdentifier: String
    @Binding var isOpen: Bool
    @Binding var seconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $isOpen) {
                Text(openLabel).tag(true)
                Text(timedLabel).tag(false)
            }
            .pickerStyle(.segmented)
            .tint(DailyDriver.lime)
            .accessibilityIdentifier(openIdentifier)

            if !isOpen {
                Stepper("\(seconds)s", value: $seconds, in: secondsRange, step: 15)
                    .font(.system(size: 11))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .monospacedDigit()
                    .accessibilityIdentifier(secondsIdentifier)
            }
        }
        .padding(.leading, 28)
    }
}
