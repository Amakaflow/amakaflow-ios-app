//
//  AppleWorkoutKitPreviewSheet.swift
//  AmakaFlow
//
//  AMA-2351 / AMA-2360 — preview mapper composition + step list before schedule.
//  AMA-2371 — Runna-style banded step cards on DailyDriver chrome; rest is a
//  chip, not a monospace dump line, and mapper jargon is demoted off this sheet.
//  AMA-2374 — exercise-named band headers + rest chips on the right of each row
//  (parity with `SDWatchSteps` / AMA-2369 redesign).
//

import SwiftUI

struct AppleWorkoutKitPreviewSheet: View {
    let workoutName: String
    let meta: WorkoutKitPlanMeta
    let intervalCount: Int
    let sections: [PreviewSection]
    let sportLabel: String
    /// `nil` when prefs are unset — the sheet must never render the
    /// "Mapper sport defaults" copy that backs the unset state (AMA-2371
    /// final review I1). Passing the intent instead of sniffing the
    /// rendered string keeps that rule expressed once, in the prefs store.
    let prefsSummary: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            sheetTitle

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sections) { section in
                            sectionCard(section)
                        }
                    }
                    .accessibilityIdentifier("af_apple_wk_step_list")

                    footer

                    Button(action: onConfirm) {
                        Text("Schedule on the watch")
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                    .accessibilityIdentifier("af_apple_wk_preview_confirm")

                    Button(action: onCancel) {
                        Text("Back")
                            .ddDisplayText(12.5, weight: .bold)
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_apple_wk_preview_back")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(DailyDriver.screenBackground)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("af_apple_wk_preview_sheet")
    }

    private var sheetTitle: some View {
        HStack {
            Text("To your Apple Watch")
                .ddDisplayText(17, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close preview")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 11) {
            DDIconChip(systemName: "applewatch", background: DailyDriver.card2, foreground: DailyDriver.foreground, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(workoutName)
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .lineLimit(2)
                Text(metaLine)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(DailyDriver.foregroundDim)
                    .accessibilityIdentifier("af_apple_wk_composition_line")
            }
            Spacer(minLength: 0)
        }
    }

    private var metaLine: String {
        let stepWord = intervalCount == 1 ? "STEP" : "STEPS"
        return "NATIVE WORKOUT APP · \(sportLabel) · \(intervalCount) \(stepWord)"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Display settings use the strength defaults — change them per device in Settings › Connected wearables.")
                .font(.system(size: 10.5))
                .foregroundColor(DailyDriver.foregroundDim)
                .lineSpacing(2)

            // Only surface the live summary once it's actually customized —
            // callers pass `nil` for the unset case (AppleWatchDeliveryPrefsStore
            // .hasConfigured == false), so the "Mapper sport defaults" jargon
            // this sheet must never show never reaches this view at all.
            if let prefsSummary {
                Text(prefsSummary)
                    .font(.system(size: 10))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .accessibilityIdentifier("af_apple_wk_prefs_summary")
            }
        }
    }

    private func sectionCard(_ section: PreviewSection) -> some View {
        let accent = section.accent.accentColor
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(section.band)
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(accent)
                Spacer(minLength: 0)
                if let tag = section.tag {
                    Text(tag)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.16))
            .overlay(
                Rectangle()
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(section.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step, showDivider: index > 0)
                }
            }
            .padding(.horizontal, 12)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
    }

    private func stepRow(_ step: PreviewStep, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            if showDivider {
                DailyDriver.border.frame(height: 1)
            }
            HStack(alignment: .center, spacing: 10) {
                Text("\(step.number)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(width: 16, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .ddDisplayText(13, weight: .semibold)
                        .foregroundColor(DailyDriver.foreground)
                    if let detail = step.detail {
                        Text(detail)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(DailyDriver.foregroundMuted)
                    }
                }

                Spacer(minLength: 0)

                if let restChip = step.restChip {
                    Text(restChip)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DailyDriver.card2)
                        .clipShape(Capsule(style: .continuous))
                        .accessibilityIdentifier("af_apple_wk_rest_chip")
                }
            }
            .padding(.vertical, 10)
        }
    }
}

private extension PreviewBandAccent {
    var accentColor: Color {
        switch self {
        case .mobility: return DailyDriver.mobilityBand
        case .work: return DailyDriver.lime
        case .cooldown: return DailyDriver.blue
        }
    }
}

#if DEBUG
#Preview("Strength · mobility + warm-ups + work") {
    let json = Data("""
    {
      "title": "Test Apple workout",
      "sportType": "traditionalStrengthTraining",
      "intervals": [
        { "kind": "work", "name": "Jump Rope", "seconds": 120 },
        { "kind": "work", "name": "WU · Barbell back squat", "reps": 8 },
        { "kind": "rest" },
        { "kind": "work", "name": "WU · Barbell back squat", "reps": 5 },
        { "kind": "rest" },
        {
          "kind": "repeat",
          "reps": 3,
          "intervals": [
            { "kind": "work", "name": "Barbell back squat", "reps": 10 },
            { "kind": "rest" }
          ]
        }
      ]
    }
    """.utf8)
    return AppleWorkoutKitPreviewSheet(
        workoutName: "Test Apple workout",
        meta: .fallback,
        intervalCount: 6,
        sections: WorkoutKitPlanStepSummary.sections(from: json),
        sportLabel: WorkoutKitSportLabel.label(from: json),
        prefsSummary: nil,
        onConfirm: {},
        onCancel: {}
    )
    .presentationDetents([.large])
}
#endif
