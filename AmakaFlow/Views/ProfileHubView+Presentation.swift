//
//  ProfileHubView+Presentation.swift
//  AmakaFlow
//
//  AMA-2292 / AMA-2389: Profile hub presentation helpers (keeps ProfileHubView under lint caps).
//

import SwiftUI

extension WorkoutCompletion {
    var profileIconName: String {
        if distanceMeters != nil { return "figure.run" }
        if workoutName.localizedCaseInsensitiveContains("amrap") { return "bolt.fill" }
        return "figure.cooldown"
    }

    var profileIconBackground: Color {
        if distanceMeters != nil { return DailyDriver.blue }
        if workoutName.localizedCaseInsensitiveContains("amrap") { return DailyDriver.purple }
        return DailyDriver.blue
    }

    /// Prefer distance only when positive so value + unit stay aligned.
    private var hasPositiveDistance: Bool {
        if let distanceMeters, distanceMeters > 0 { return true }
        return false
    }

    var profileBigValue: String {
        if hasPositiveDistance, let distanceMeters {
            return String(format: "%.1f", Double(distanceMeters) / 1000.0)
        }
        // Match profileMetaLine — never show 0 for a completed sub-minute session.
        let minutes = max(1, durationSeconds / 60)
        return "\(minutes)"
    }

    var profileUnitLabel: String {
        hasPositiveDistance ? "KM" : "MIN"
    }

    var profileMetaLine: String {
        let day = startedAt.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let minutes = max(1, durationSeconds / 60)
        let duration: String
        if minutes >= 60 {
            duration = "\(minutes / 60)H \(minutes % 60)M"
        } else {
            duration = "\(minutes) MIN"
        }
        var parts = [day, duration]
        if let heartRate = avgHeartRate {
            parts.append("\(heartRate) BPM")
        }
        switch source {
        case .garmin: parts.append("GARMIN")
        case .appleWatch: parts.append("APPLE WATCH")
        case .phone: parts.append("ON PHONE")
        case .manual: break
        }
        if isSyncedToStrava, source != .garmin {
            parts.append("STRAVA")
        }
        return parts.joined(separator: " · ")
    }
}

struct ProfileThisWeekSection: View {
    let entries: [WorkoutCompletion]
    @Binding var weekExpanded: Bool
    let onSelectRow: () -> Void

    var body: some View {
        let shown = weekExpanded ? entries : Array(entries.prefix(3))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week")
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Spacer()
                if entries.count > 3 {
                    Button(weekExpanded ? "Show less" : "See all (\(entries.count))") {
                        weekExpanded.toggle()
                    }
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
                }
            }

            if shown.isEmpty {
                Text("No sessions yet this week.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(shown) { completion in
                    Button(action: onSelectRow) {
                        HStack(spacing: 12) {
                            DDIconChip(
                                systemName: completion.profileIconName,
                                background: completion.profileIconBackground,
                                size: 34
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.workoutName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(DailyDriver.foreground)
                                    .lineLimit(1)
                                Text(completion.profileMetaLine)
                                    .font(.system(size: 10))
                                    .foregroundColor(DailyDriver.foregroundDim)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(completion.profileBigValue)
                                    .ddDisplayText(18, weight: .heavy)
                                    .foregroundColor(DailyDriver.foreground)
                                Text(completion.profileUnitLabel)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(DailyDriver.foregroundDim)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DailyDriver.foregroundDim)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(DailyDriver.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(DailyDriver.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Profile hub") {
    ProfileHubView(
        navigateToSyncDashboard: .constant(false),
        path: .constant(NavigationPath())
    )
    .environmentObject(PairingService.shared)
}
#endif
