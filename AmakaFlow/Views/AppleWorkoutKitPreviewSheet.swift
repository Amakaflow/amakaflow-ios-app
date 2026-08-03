//
//  AppleWorkoutKitPreviewSheet.swift
//  AmakaFlow
//
//  AMA-2351 / AMA-2360 — preview mapper composition + step list before schedule.
//  AMA-2371 — Runna-style banded step cards on DailyDriver chrome; rest is a
//  chip, not a monospace dump line, and mapper jargon is demoted off this sheet.
//

import SwiftUI

struct AppleWorkoutKitPreviewSheet: View {
    let workoutName: String
    let meta: WorkoutKitPlanMeta
    let intervalCount: Int
    let sections: [PreviewSection]
    let sportLabel: String
    let prefsSummary: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            backRow
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

    private var backRow: some View {
        HStack {
            Button(action: onCancel) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_apple_wk_preview_back")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DDIconChip(systemName: "applewatch", background: DailyDriver.lime, foreground: DailyDriver.ink, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("To your Apple Watch")
                        .ddDisplayText(19, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(workoutName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Text(metaLine)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundColor(DailyDriver.foregroundDim)
                .accessibilityIdentifier("af_apple_wk_composition_line")
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
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(2)

            // Only surface the live summary once it's actually customized —
            // the unset copy reads "Mapper sport defaults", which this sheet
            // must never show (demoted in favor of the pointer above).
            if !prefsSummary.localizedCaseInsensitiveContains("mapper") {
                Text(prefsSummary)
                    .font(.system(size: 10))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .accessibilityIdentifier("af_apple_wk_prefs_summary")
            }
        }
    }

    private func sectionCard(_ section: PreviewSection) -> some View {
        let accent = section.kind.accentColor
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(section.band)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(accent)
                if let tag = section.tag {
                    Text(tag)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DailyDriver.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accent)
                        .clipShape(Capsule(style: .continuous))
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(section.steps) { step in
                    stepRow(step, accent: accent)
                }
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 13)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepRow(_ step: PreviewStep, accent: Color) -> some View {
        HStack(spacing: 10) {
            if let restChip = step.restChip {
                Text(restChip)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(DailyDriver.card2)
                    .clipShape(Capsule(style: .continuous))
                    .accessibilityIdentifier("af_apple_wk_rest_chip")
            } else {
                Text("\(step.number)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.ink)
                    .frame(width: 20, height: 20)
                    .background(accent.opacity(0.85))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(DailyDriver.foreground)
                    if let detail = step.detail {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundColor(DailyDriver.foregroundMuted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private extension PreviewBandKind {
    var accentColor: Color {
        switch self {
        case .warmup: return DailyDriver.amber
        case .work: return DailyDriver.lime
        case .cooldown: return DailyDriver.blue
        }
    }
}

#if DEBUG
#Preview("Strength · warm-up + repeat") {
    let json = Data("""
    {
      "title": "Full Body Strength",
      "sportType": "traditionalStrengthTraining",
      "intervals": [
        { "kind": "warmup", "seconds": 300 },
        {
          "kind": "repeat",
          "reps": 3,
          "intervals": [
            { "kind": "work", "name": "Barbell Back Squat", "reps": 8 },
            { "kind": "rest", "seconds": 60 }
          ]
        },
        { "kind": "cooldown", "seconds": 120 }
      ]
    }
    """.utf8)
    return AppleWorkoutKitPreviewSheet(
        workoutName: "Full Body Strength",
        meta: .fallback,
        intervalCount: 3,
        sections: WorkoutKitPlanStepSummary.sections(from: json),
        sportLabel: WorkoutKitSportLabel.label(from: json),
        prefsSummary: "Mapper sport defaults (not customized)",
        onConfirm: {},
        onCancel: {}
    )
    .presentationDetents([.large])
}
#endif
