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
import UIKit

// swiftlint:disable:next type_body_length
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

    /// AMA-2383 — scripted "it writes itself" reveal (local data, ≤2s cap).
    @StateObject private var reveal: BuildRevealController

    init(
        workoutName: String,
        meta: WorkoutKitPlanMeta,
        intervalCount: Int,
        sections: [PreviewSection],
        sportLabel: String,
        prefsSummary: String?,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.workoutName = workoutName
        self.meta = meta
        self.intervalCount = intervalCount
        self.sections = sections
        self.sportLabel = sportLabel
        self.prefsSummary = prefsSummary
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _reveal = StateObject(
            wrappedValue: BuildRevealController(
                config: BuildRevealScripts.watchPreview(sections: sections)
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetTitle

            VStack(alignment: .leading, spacing: 16) {
                header

                // AMA-2383: build reveal owns the step list + CTA choreography.
                // Banded cards below still render for revealed beats so AMA-2374
                // visual parity (rest chips, open-goal amber) is preserved.
                buildStatus

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(revealedSections) { section in
                                sectionCard(section)
                                    .id(section.id)
                            }
                            Color.clear.frame(height: 1).id("wk_preview_bottom")
                        }
                        .accessibilityIdentifier("af_apple_wk_step_list")
                        .padding(.bottom, 8)

                        footer

                        Button(
                            action: {
                                guard reveal.isDone else { return }
                                onConfirm()
                            },
                            label: {
                                Text(reveal.isDone ? BuildRevealScripts.watchCTA : BuildRevealScripts.watchBuilding)
                            }
                        )
                        .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                        .disabled(!reveal.isDone)
                        .opacity(reveal.isDone ? 1 : 0.55)
                        .animation(
                            MotionTokens.easeOutQuart(duration: MotionTokens.ctaColorSettle),
                            value: reveal.isDone
                        )
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
                    .onChange(of: reveal.visibleCount) { _, _ in
                        withAnimation(MotionTokens.easeOutQuart(duration: MotionTokens.fast)) {
                            proxy.scrollTo("wk_preview_bottom", anchor: .bottom)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(DailyDriver.screenBackground)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("af_apple_wk_preview_sheet")
        .onAppear {
            reveal.playScripted(reduceMotion: UIAccessibility.isReduceMotionEnabled)
        }
    }

    /// Sections clipped to beats the controller has revealed so far.
    private var revealedSections: [PreviewSection] {
        let shown = reveal.shownBeats
        var out: [PreviewSection] = []
        var currentBand: PreviewSection?
        var currentSteps: [PreviewStep] = []

        func flush() {
            guard let band = currentBand else { return }
            out.append(
                PreviewSection(
                    accent: band.accent,
                    band: band.band,
                    tag: band.tag,
                    steps: currentSteps,
                    caption: band.caption
                )
            )
            currentBand = nil
            currentSteps = []
        }

        for beat in shown {
            switch beat.kind {
            case .band:
                flush()
                if let match = sections.first(where: { $0.band == beat.label }) {
                    currentBand = match
                    currentSteps = []
                }
            case .row:
                if let band = currentBand,
                   let step = band.steps.first(where: {
                       $0.title == beat.name && $0.detail == (beat.detail?.isEmpty == true ? nil : beat.detail)
                   }) ?? band.steps.first(where: { $0.title == beat.name }) {
                    // Avoid duplicating the same step if detail matching is fuzzy.
                    if !currentSteps.contains(where: { $0.number == step.number }) {
                        currentSteps.append(step)
                    }
                }
            default:
                break
            }
        }
        flush()
        return out
    }

    private var buildStatus: some View {
        HStack(spacing: 0) {
            Text(reveal.statusLine)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundColor(reveal.isDone ? DailyDriver.lime : DailyDriver.foregroundDim)
            if !reveal.isDone {
                Text("▍")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(DailyDriver.lime)
                    .opacity(0.9)
            }
        }
        .accessibilityIdentifier("af_apple_wk_build_status")
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
        var parts = ["NATIVE WORKOUT APP", sportLabel]
        if !compositionTags.isEmpty {
            parts.append(compositionTags.joined(separator: " + "))
        }
        parts.append("\(intervalCount) \(stepWord)")
        return parts.joined(separator: " · ")
    }

    /// AMA-2378 — `PREP` / `RAMPS` / `COOLDOWN` tokens surfaced on the header
    /// meta line only when this preview's bands actually contain them.
    private var compositionTags: [String] {
        var tags: [String] = []
        if sections.contains(where: { $0.accent == .mobility }) {
            tags.append("PREP")
        }
        if sections.contains(where: \.hasRamp) {
            tags.append("RAMPS")
        }
        if sections.contains(where: { $0.accent == .cooldown }) {
            tags.append("COOLDOWN")
        }
        return tags
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

            if let caption = section.caption {
                Text(caption)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DailyDriver.card)
                    .accessibilityIdentifier("af_apple_wk_no_warmups_caption")
            }

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
                            .foregroundColor(step.isOpenGoal ? DailyDriver.amber : DailyDriver.foregroundMuted)
                    }
                }

                Spacer(minLength: 0)

                if let restChip = step.restChip {
                    Text(restChip)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(step.isOpenRest ? DailyDriver.amber : DailyDriver.foregroundMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(step.isOpenRest ? DailyDriver.amber.opacity(0.16) : DailyDriver.card2)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(step.isOpenRest ? DailyDriver.amber.opacity(0.4) : .clear, lineWidth: 1)
                        )
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

#Preview("Multi-step mobility + skipped ramp + open goal + cooldown last") {
    // AMA-2378 Task 7 — two named mobility activities (multi-step prep), an
    // exercise with no warm-up rows (skipped ramp → amber-free caption), an
    // open-goal working set (amber "OPEN"), open rest (amber chip), and two
    // named cooldown activities composed the same way as mobility (no
    // `kind: cooldown` marker) that must still land in a trailing Cool-down
    // band, never mixed into "Mobility prep".
    let json = Data("""
    {
      "title": "Watch-ready v2 preview",
      "sportType": "traditionalStrengthTraining",
      "intervals": [
        { "kind": "work", "name": "Jump Rope", "seconds": 120 },
        { "kind": "work", "name": "World's Greatest Stretch", "reps": 5 },
        {
          "kind": "repeat",
          "reps": 3,
          "intervals": [
            { "kind": "work", "name": "Barbell back squat", "reps": 10 },
            { "kind": "rest" }
          ]
        },
        { "kind": "work", "name": "Overhead Press" },
        { "kind": "rest" },
        { "kind": "work", "name": "Foam Roll" },
        { "kind": "work", "name": "Jump Rope", "seconds": 180 }
      ]
    }
    """.utf8)
    return AppleWorkoutKitPreviewSheet(
        workoutName: "Watch-ready v2 preview",
        meta: .fallback,
        intervalCount: 7,
        sections: WorkoutKitPlanStepSummary.sections(from: json),
        sportLabel: WorkoutKitSportLabel.label(from: json),
        prefsSummary: nil,
        onConfirm: {},
        onCancel: {}
    )
    .presentationDetents([.large])
}
#endif
