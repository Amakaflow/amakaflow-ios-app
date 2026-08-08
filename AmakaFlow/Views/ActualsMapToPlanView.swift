//
//  ActualsMapToPlanView.swift
//  AmakaFlow
//
//  AMA-2387: unmatched activity → "Which workout was this?" + Map v2 capture.
//  Builder / photo / match-save are presented here (item-based covers) so the
//  first tap never lands on an empty fullScreenCover.
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
    @State private var showCaptureBuilder = false
    @State private var showCapturePhoto = false
    @State private var matchSaveDraft: ActualsCaptureDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)

                statsGrid
                    .padding(.top, 12)

                askCallout
                    .padding(.top, 12)

                captureSection
                    .padding(.top, 14)

                Text(matches.isEmpty ? ActualsCopy.mapOrMatchHeader : ActualsCopy.mapBestMatchesHeader)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    candidateRow(match, index: index + 1)
                        .padding(.bottom, 8)
                }

                Button(action: onSearchAll) {
                    Text(ActualsCopy.mapSearchAllCTA)
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Button(action: {
                    onKeepAsIs()
                    dismiss()
                }) {
                    Text(ActualsCopy.mapKeepAsNamedCTA(title: activity.title))
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.foregroundDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(ActualsCopy.mapKeepAsIsAccessibilityID)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        // Item/isPresented covers always have `activity` in scope — no empty if-let.
        .fullScreenCover(isPresented: $showCaptureBuilder) {
            BuilderV3EntryView(
                actualsActivity: activity,
                onCaptureComplete: { draft in
                    showCaptureBuilder = false
                    // Let the builder cover dismiss, then present match-save.
                    DispatchQueue.main.async {
                        matchSaveDraft = draft
                    }
                }
            )
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .ddSuppressFloatingChrome()
        }
        .fullScreenCover(isPresented: $showCapturePhoto) {
            ImageImportView(
                actualsActivity: activity,
                onCaptureComplete: { draft in
                    showCapturePhoto = false
                    DispatchQueue.main.async {
                        matchSaveDraft = draft
                    }
                }
            )
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .ddSuppressFloatingChrome()
        }
        .fullScreenCover(item: $matchSaveDraft) { draft in
            ActualsMatchSaveView(
                activity: activity,
                draft: draft,
                onComplete: { finalDraft, alsoLibrary in
                    matchSaveDraft = nil
                    onCaptureMatched(finalDraft, alsoLibrary)
                    dismiss()
                }
            )
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .ddSuppressFloatingChrome()
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
                        : Color(hex: "FC4C02"),
                    size: 34
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.title)
                        .ddDisplayText(22, weight: .heavy)
                        .foregroundColor(DailyDriver.foreground)
                    Text(activityMeta)
                        .font(.system(size: 9, design: .monospaced))
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
        HStack(spacing: 8) {
            statCell(
                value: "\(max(1, Int((activity.durationSeconds / 60).rounded())))",
                unit: "MIN"
            )
            statCell(value: caloriesLabel, unit: "CAL")
            statCell(value: hrLabel, unit: "BPM")
            statCell(value: movesLabel, unit: "MOVES")
        }
    }

    private func statCell(value: String, unit: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .ddDisplayText(19, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
            Text(unit)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
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
        guard let hr = activity.avgHR else { return "—" }
        return "\(Int(hr.rounded()))"
    }

    private var movesLabel: String { "—" }

    // MARK: - Ask + capture + candidates

    private var askCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ActualsCopy.mapAskTitle)
                .ddDisplayText(13, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Text(matches.isEmpty ? ActualsCopy.mapAskBodyNoMatch : ActualsCopy.mapAskBody)
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.amber.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.amber.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ActualsCopy.mapCaptureSectionHeader)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)

            DDDoorRow(
                icon: "square.and.pencil",
                iconBackground: DailyDriver.card2,
                title: ActualsCopy.mapCaptureBuildTitle,
                subtitle: ActualsCopy.mapCaptureBuildSub
            ) {
                showCaptureBuilder = true
            }
            .accessibilityIdentifier(ActualsCopy.mapCaptureBuildAccessibilityID)

            DDDoorRow(
                icon: "camera.fill",
                iconBackground: DailyDriver.purple,
                title: ActualsCopy.mapCapturePhotoTitle,
                subtitle: ActualsCopy.mapCapturePhotoSub
            ) {
                showCapturePhoto = true
            }
            .accessibilityIdentifier(ActualsCopy.mapCapturePhotoAccessibilityID)
        }
    }

    private func candidateRow(_ match: ActualsPlanMatch, index: Int) -> some View {
        Button {
            onSelect(match)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                DDIconChip(
                    systemName: "figure.run",
                    background: DailyDriver.card2,
                    size: 32
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.candidate.title)
                        .ddDisplayText(13.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(match.candidate.sourceLabel)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(1)
                    Text(match.whyLine)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(match.isBest ? DailyDriver.lime : DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        match.isBest ? DailyDriver.lime.opacity(0.45) : DailyDriver.border,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(ActualsCopy.mapCandidateAccessibilityID(index))
    }
}

#if DEBUG
#Preview("Map to plan v2") {
    let start = Date()
    let activity = ActualsUnmappedActivity(
        title: "Gym session",
        provider: .garmin,
        startDate: start,
        durationSeconds: 44 * 60,
        distanceMeters: nil,
        calories: 486,
        avgHR: 151,
        type: .strength
    )
    let candidates = [
        ActualsPlanCandidate(
            id: "1", title: "Lower body — posterior", sourceLabel: "MY WORKOUTS",
            scheduledStart: start.addingTimeInterval(-180),
            durationSeconds: 48 * 60, distanceMeters: nil,
            type: .strength, targetAvgHR: nil
        ),
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
