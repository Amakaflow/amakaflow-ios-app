//
//  ActualsMapToPlanView.swift
//  AmakaFlow
//
//  AMA-2387: unmatched activity → "Which workout was this?" (screens-actuals.jsx).
//

import SwiftUI

struct ActualsMapToPlanView: View {
    let activity: ActualsUnmappedActivity
    let matches: [ActualsPlanMatch]
    var onSelect: (ActualsPlanMatch) -> Void
    var onKeepAsIs: () -> Void
    var onSearchAll: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)

                statsGrid
                    .padding(.top, 12)

                askCallout
                    .padding(.top, 12)

                Text(ActualsCopy.mapBestMatchesHeader)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.top, 14)
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
                    Text(ActualsCopy.mapKeepAsIsCTA)
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
                    systemName: "figure.run",
                    background: Color(hex: "FC4C02"),
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
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: activity.startDate)
        let end = formatter.string(from: activity.endDate)
        let source = ActualsCopy.sourceDisplayName(activity.provider).uppercased()
        return "\(start) – \(end) · FROM \(source)"
    }

    // MARK: - Stats

    private var statsGrid: some View {
        HStack(spacing: 8) {
            statCell(value: distanceLabel, unit: "KM")
            statCell(value: "\(max(1, Int((activity.durationSeconds / 60).rounded())))", unit: "MIN")
            statCell(value: caloriesLabel, unit: "CAL")
            statCell(value: hrLabel, unit: "BPM")
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

    private var distanceLabel: String {
        guard let meters = activity.distanceMeters else { return "—" }
        return String(format: "%.1f", meters / 1000)
    }

    private var caloriesLabel: String {
        guard let cal = activity.calories else { return "—" }
        return "\(Int(cal.rounded()))"
    }

    private var hrLabel: String {
        guard let hr = activity.avgHR else { return "—" }
        return "\(Int(hr.rounded()))"
    }

    // MARK: - Ask + candidates

    private var askCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ActualsCopy.mapAskTitle)
                .ddDisplayText(13, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Text(ActualsCopy.mapAskBody)
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
                    Text(match.whyLine)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(match.isBest ? DailyDriver.lime : DailyDriver.amber)
                }
                Spacer(minLength: 0)
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
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
#Preview("Map to plan") {
    let start = Date()
    let activity = ActualsUnmappedActivity(
        title: "Lunch Run",
        provider: .strava,
        startDate: start,
        durationSeconds: 59 * 60,
        distanceMeters: 8200,
        calories: 677,
        avgHR: 143,
        type: .run
    )
    let candidates = [
        ActualsPlanCandidate(
            id: "1", title: "Tempo 40/20s", sourceLabel: "STRYD · 12:50 TODAY",
            scheduledStart: start.addingTimeInterval(-180),
            durationSeconds: 55 * 60, distanceMeters: 8000,
            type: .run, targetAvgHR: 145
        ),
        ActualsPlanCandidate(
            id: "2", title: "Zone 2 base run", sourceLabel: "MY WORKOUTS",
            scheduledStart: nil, durationSeconds: 60 * 60,
            distanceMeters: 8500, type: .run, targetAvgHR: 125
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
