//
//  ActualsMapToPlanView.swift
//  AmakaFlow
//
//  AMA-2396 A1: Map page v3 — selectable match cards + one pinned CTA
//  that relabels (Keep-as-is ↔ Match to "<name>"). No amber explainer,
//  no floating text actions.
//

import SwiftUI

struct ActualsMapToPlanView: View {
    let activity: ActualsUnmappedActivity
    let matches: [ActualsPlanMatch]
    var onSelect: (ActualsPlanMatch) -> Void
    var onKeepAsIs: () -> Void
    var onSearchAll: () -> Void = {}
    /// Build/photo → match-save completed. Parent updates Today + pops Map.
    var onCaptureMatched: (ActualsCaptureDraft, _ alsoSavedToLibrary: Bool) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMatchID: String?
    /// Single cover state so builder/photo → match-save never races two presentations.
    @State private var capturePresentation: CapturePresentation?

    private enum CapturePresentation: Identifiable, Equatable {
        case builder
        case photo
        case matchSave(ActualsCaptureDraft)

        var id: String {
            switch self {
            case .builder: return "builder"
            case .photo: return "photo"
            case .matchSave(let draft): return "match-\(draft.id)"
            }
        }
    }

    private var selectedMatch: ActualsPlanMatch? {
        matches.first { $0.id == selectedMatchID }
    }

    private var pinnedCTALabel: String {
        ActualsMapCTAState.label(
            selectedMatchTitle: selectedMatch?.candidate.title,
            activityTitle: activity.title
        )
    }

    private var pinnedIsMatch: Bool {
        ActualsMapCTAState.isMatchSelected(selectedMatch?.candidate.title)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 10)

                    statsGrid
                        .padding(.top, 12)

                    askPrompt
                        .padding(.top, 16)

                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                        candidateRow(match, index: index + 1)
                            .padding(.bottom, 7)
                    }

                    searchAllRow
                        .padding(.bottom, 14)

                    captureSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 96)
            }

            pinnedCTA
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .fullScreenCover(item: $capturePresentation) { presentation in
            switch presentation {
            case .builder:
                BuilderV3EntryView(actualsActivity: activity) { draft in
                    capturePresentation = .matchSave(draft)
                }
                .background(DailyDriver.screenBackground.ignoresSafeArea())
                .ddSuppressFloatingChrome()
            case .photo:
                ImageImportView(actualsActivity: activity) { draft in
                    capturePresentation = .matchSave(draft)
                }
                .background(DailyDriver.screenBackground.ignoresSafeArea())
                .ddSuppressFloatingChrome()
            case .matchSave(let draft):
                ActualsMatchSaveView(
                    activity: activity,
                    draft: draft
                ) { finalDraft, alsoLibrary in
                    capturePresentation = nil
                    onCaptureMatched(finalDraft, alsoLibrary)
                    dismiss()
                }
                .background(DailyDriver.screenBackground.ignoresSafeArea())
                .ddSuppressFloatingChrome()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Today")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                DDIconChip(
                    systemName: activity.type == .strength ? "dumbbell.fill" : "figure.run",
                    background: activity.type == .strength
                        ? DailyDriver.blue
                        : DailyDriver.stravaBrand,
                    size: 34
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.title)
                        .ddDisplayText(21, weight: .heavy)
                        .foregroundColor(DailyDriver.foreground)
                    Text(activityMeta)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
            }
        }
    }

    private var activityMeta: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let weekday = formatter.string(from: activity.startDate).uppercased()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: activity.startDate)
        let end = formatter.string(from: activity.endDate)
        let source = ActualsCopy.sourceDisplayName(activity.provider).uppercased()
        return "\(weekday) · \(start) – \(end) · FROM \(source)"
    }

    // MARK: - Stats

    private var statsGrid: some View {
        HStack(spacing: 7) {
            statCell(
                value: "\(max(1, Int((activity.durationSeconds / 60).rounded())))",
                unit: "MIN"
            )
            statCell(value: caloriesLabel, unit: "CAL")
            statCell(value: hrLabel, unit: "BPM")
        }
    }

    private func statCell(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .ddDisplayText(17, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
            Text(unit)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var caloriesLabel: String {
        guard let cal = activity.calories else { return "—" }
        return "\(Int(cal.rounded()))"
    }

    private var hrLabel: String {
        guard let heartRate = activity.avgHR else { return "—" }
        return "\(Int(heartRate.rounded()))"
    }

    // MARK: - Ask + candidates + capture

    private var askPrompt: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ActualsCopy.mapAskTitle)
                .ddDisplayText(15, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Text(ActualsCopy.mapAskMono)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .padding(.bottom, 9)
        }
    }

    private var searchAllRow: some View {
        Button(action: onSearchAll) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                Text(ActualsCopy.mapSearchAllCTA)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        DailyDriver.border.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(ActualsCopy.mapCaptureSectionHeader)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)

            HStack(spacing: 8) {
                captureTile(
                    icon: "square.and.pencil",
                    iconBackground: DailyDriver.card2,
                    iconInk: .white,
                    title: ActualsCopy.mapCaptureBuildTitle,
                    subtitle: ActualsCopy.mapCaptureBuildSub,
                    accessibilityID: ActualsCopy.mapCaptureBuildAccessibilityID
                ) {
                    capturePresentation = .builder
                }
                captureTile(
                    icon: "camera.fill",
                    iconBackground: DailyDriver.purple,
                    iconInk: DailyDriver.ink,
                    title: ActualsCopy.mapCapturePhotoTitle,
                    subtitle: ActualsCopy.mapCapturePhotoSub,
                    accessibilityID: ActualsCopy.mapCapturePhotoAccessibilityID
                ) {
                    capturePresentation = .photo
                }
            }
        }
    }

    private func captureTile(
        icon: String,
        iconBackground: Color,
        iconInk: Color,
        title: String,
        subtitle: String,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                DDIconChip(
                    systemName: icon,
                    background: iconBackground,
                    foreground: iconInk,
                    size: 30
                )
                Text(title)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .padding(.top, 7)
                Text(subtitle)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }

    private func candidateRow(_ match: ActualsPlanMatch, index: Int) -> some View {
        let selected = selectedMatchID == match.id
        return Button {
            selectedMatchID = selected ? nil : match.id
        } label: {
            HStack(spacing: 11) {
                DDIconChip(
                    systemName: "dumbbell.fill",
                    background: DailyDriver.card2,
                    size: 32
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.candidate.title)
                        .ddDisplayText(13.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text("\(match.candidate.sourceLabel) · \(match.whyLine)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(match.isBest ? DailyDriver.lime : DailyDriver.amber)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .stroke(DailyDriver.border.opacity(0.9), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                        .opacity(selected ? 0 : 1)
                    if selected {
                        Circle()
                            .fill(DailyDriver.lime)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DailyDriver.ink)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? DailyDriver.lime : DailyDriver.border,
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(ActualsCopy.mapCandidateAccessibilityID(index))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Pinned CTA

    private var pinnedCTA: some View {
        Button {
            if let selectedMatch {
                onSelect(selectedMatch)
                dismiss()
            } else {
                onKeepAsIs()
                dismiss()
            }
        } label: {
            Text(pinnedCTALabel)
                .ddDisplayText(14, weight: .bold)
                .foregroundColor(pinnedIsMatch ? DailyDriver.ink : DailyDriver.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    pinnedIsMatch
                        ? DailyDriver.lime
                        : Color(red: 20 / 255, green: 20 / 255, blue: 22 / 255).opacity(0.95)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            pinnedIsMatch ? Color.clear : DailyDriver.border.opacity(0.9),
                            lineWidth: 1
                        )
                )
                .clipShape(Capsule(style: .continuous))
                .shadow(
                    color: pinnedIsMatch
                        ? DailyDriver.lime.opacity(0.45)
                        : Color.black.opacity(0.55),
                    radius: pinnedIsMatch ? 14 : 12,
                    y: pinnedIsMatch ? 0 : 8
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            pinnedIsMatch
                ? ActualsCopy.mapPinnedCTAAccessibilityID
                : ActualsCopy.mapKeepAsIsAccessibilityID
        )
    }
}

#if DEBUG
#Preview("Map to plan v3") {
    let start = Date()
    let activity = ActualsUnmappedActivity(
        title: "Erg cardio",
        provider: .strava,
        startDate: start,
        durationSeconds: 101 * 60,
        distanceMeters: nil,
        calories: nil,
        avgHR: nil,
        type: .other
    )
    let candidates = [
        ActualsPlanCandidate(
            id: "1", title: "Lower body — posterior", sourceLabel: "MY WORKOUTS",
            scheduledStart: start.addingTimeInterval(-180),
            durationSeconds: 48 * 60, distanceMeters: nil,
            type: .strength, targetAvgHR: nil
        ),
        ActualsPlanCandidate(
            id: "2", title: "Engine builder — 30 min", sourceLabel: "MY WORKOUTS",
            scheduledStart: nil,
            durationSeconds: 30 * 60, distanceMeters: nil,
            type: .other, targetAvgHR: nil
        )
    ]
    let matches = ActualsPlanMatcher.rank(activity: activity, candidates: candidates)
    ActualsMapToPlanView(
        activity: activity,
        matches: matches,
        onSelect: { _ in },
        onKeepAsIs: {}
    )
}
#endif
