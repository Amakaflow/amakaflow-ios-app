//
//  WorkoutDetailAnatomy.swift
//  AmakaFlow
//
//  AMA-2395 — the canonical workout-detail anatomy, built once and rendered by
//  BOTH the saved detail (`UnifiedWorkoutDetailView`) and the pre-save previews
//  (social import confirm, AI draft, photo draft). Build once, use in both:
//  create-from-photo inherits the same anatomy for free.
//
//  Zones: TIME card (Ladder TOTAL/ACTIVE split) · FROM THE CREATOR collapsed
//  caption · semantic band sections with modality chips and one prescription
//  grammar.
//

import SwiftUI

// MARK: - Modality chip

/// Replaces the universal dumbbell. Colours follow the shared AMA-2393
/// classifier: cardio blue · lift purple · bodyweight amber · unknown neutral.
struct WorkoutModalityChip: View {
    let modality: WorkoutModality
    let exerciseName: String
    var size: CGFloat = 32

    var body: some View {
        DDIconChip(
            systemName: symbolName,
            background: tint.opacity(0.26),
            foreground: tint,
            size: size
        )
    }

    private var tint: Color {
        switch modality {
        case .cardioMachine, .run: return DailyDriver.blue
        case .lift: return DailyDriver.purple
        case .bodyweight: return DailyDriver.amber
        case .unknown: return DailyDriver.foregroundMuted
        }
    }

    /// Machine-specific where we know the machine, so a Ski Erg and a bike
    /// aren't the same picture.
    private var symbolName: String {
        switch modality {
        case .cardioMachine:
            switch WorkoutSportHonesty.machineKindKey(forName: exerciseName) {
            case "bike": return "figure.indoor.cycle"
            case "row": return "figure.rower"
            case "ski": return "figure.skiing.crosscountry"
            case "treadmill": return "figure.run"
            case "elliptical": return "figure.elliptical"
            case "stair": return "figure.stair.stepper"
            default: return "figure.mixed.cardio"
            }
        case .run: return "figure.run"
        case .lift: return "dumbbell.fill"
        case .bodyweight: return "bolt.fill"
        case .unknown: return "dumbbell.fill"
        }
    }
}

// MARK: - TIME card

/// Ladder-style TOTAL / ACTIVE split — the estimator made visible, with the
/// basis spelled out underneath so the number is never a black box.
struct WorkoutTimeCardView: View {
    let estimate: WorkoutDurationEstimate
    /// Appended to the basis note when the caption told us the creator's time.
    var creatorTimeNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                cell(
                    value: estimate.totalLabel,
                    caption: estimate.totalSublabel,
                    tint: DailyDriver.lime,
                    identifier: "af_detail_time_total"
                )

                Rectangle()
                    .fill(DailyDriver.border)
                    .frame(width: 1, height: 34)

                cell(
                    value: estimate.activeLabel,
                    caption: estimate.activeNote,
                    tint: DailyDriver.foreground,
                    identifier: "af_detail_time_active"
                )
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(basisLine)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("af_detail_time_basis")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("af_detail_time_card")
    }

    private var basisLine: String {
        guard let creatorTimeNote, !creatorTimeNote.isEmpty else { return estimate.basisNote }
        return "\(estimate.basisNote) · CREATOR'S TIME: \(creatorTimeNote)"
    }

    private func cell(value: String, caption: String, tint: Color, identifier: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .ddDisplayText(19, weight: .heavy)
                .foregroundColor(tint)
            Text(caption)
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - FROM THE CREATOR

/// The caption, collapsed to two lines with hashtags and CTAs held back until
/// More. It is never the page body, and the stored caption is never rewritten.
struct WorkoutCreatorNoteCard: View {
    let title: String
    let rawText: String
    @State private var isExpanded = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(DailyDriver.foregroundDim)

                Text(isExpanded ? WorkoutCaptionPresentation.expanded(rawText)
                                : WorkoutCaptionPresentation.collapsed(rawText))
                    .font(.system(size: 11.5))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .lineSpacing(3)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("af_detail_creator_note_text")

                if showsToggle {
                    Text(isExpanded ? "Less" : "More")
                        .ddDisplayText(11, weight: .bold)
                        .foregroundColor(DailyDriver.lime)
                        .accessibilityIdentifier("af_detail_creator_note_toggle")
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("af_detail_creator_note")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    /// Only offer More when there is genuinely more — a short clean caption
    /// gets no dead control.
    private var showsToggle: Bool {
        WorkoutCaptionPresentation.hasHiddenDetail(rawText)
            || WorkoutCaptionPresentation.collapsed(rawText).count > 90
    }
}

// MARK: - Semantic band section

/// 3px coloured left band + mono title + right-aligned subtotal, then the rows
/// in one card. Same anatomy as the watch preview, so pre-save and saved match.
struct WorkoutBandSectionView: View {
    let band: WorkoutBand
    let index: Int
    var onSelect: ((Exercise) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if band.hasHeader { header }
            rowsCard
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("af_detail_section_\(index)")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(band.title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundColor(bandColor)
            Spacer(minLength: 0)
            if band.seconds > 0 {
                Text(band.timeLabel)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(DailyDriver.card)
        .clipShape(
            .rect(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 10, topTrailingRadius: 10)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(bandColor)
                .frame(width: 3)
        }
    }

    private var rowsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(band.rows.enumerated()), id: \.element.id) { offset, row in
                rowView(row, position: offset)
                if offset < band.rows.count - 1 {
                    Divider().overlay(DailyDriver.border)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 2)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func rowView(_ row: WorkoutBandRow, position: Int) -> some View {
        Button {
            if let exercise = row.exercise { onSelect?(exercise) }
        } label: {
            HStack(spacing: 11) {
                WorkoutModalityChip(modality: row.modality, exerciseName: row.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .ddDisplayText(13.5, weight: .semibold)
                        .foregroundColor(DailyDriver.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.prescription)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.exercise == nil || onSelect == nil)
        .accessibilityElement(children: .combine)
        // Position-scoped: a circuit can legitimately repeat a movement.
        .accessibilityIdentifier(
            "af_detail_row_\(WorkoutBandSectionView.identifierSlug(row.name))_\(index)_\(position)"
        )
    }

    private var bandColor: Color {
        switch band.kind {
        case .warmUp: return DailyDriver.amber
        case .work: return DailyDriver.lime
        case .conditioning: return DailyDriver.blue
        case .cooldown: return DailyDriver.foregroundDim
        }
    }

    /// Stable, entity-scoped a11y id — `af_detail_row_ski_erg`.
    static func identifierSlug(_ name: String) -> String {
        let lowered = name.lowercased()
        let cleaned = lowered.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "_",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

// MARK: - Whole structure

/// The full band list — one call site for detail and preview alike.
struct WorkoutBandListView: View {
    let bands: [WorkoutBand]
    var onSelect: ((Exercise) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                WorkoutBandSectionView(band: band, index: index, onSelect: onSelect)
            }
        }
        .accessibilityIdentifier("af_detail_sections")
    }
}
