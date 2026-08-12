//
//  ProfileHubView+Presentation.swift
//  AmakaFlow
//
//  AMA-2292 / AMA-2389: Profile hub presentation helpers (keeps ProfileHubView under lint caps).
//  CI trigger marker
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

// MARK: - AMA-2417 Profile training aggregates (Monday week + Strava)

enum ProfileTrainingStats {
    /// Training week starts Monday (ISO-style), independent of locale firstWeekday.
    static var mondayFirstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    /// Map BFF Strava activities into Profile's completion shape for tiles / This week.
    static func completions(
        from activities: [StravaCompletedActivityDTO],
        calendar: Calendar = mondayFirstCalendar,
        now: Date = Date()
    ) -> [WorkoutCompletion] {
        activities.compactMap { activity in
            guard let startedAt = ActualsTodayDemoFeed.resolveStartDate(
                activity,
                calendar: calendar,
                now: now
            ) else {
                return nil
            }
            let durationSeconds = max(0, activity.durationMin) * 60
            let distanceMeters: Int? = activity.distanceKm > 0
                ? Int((activity.distanceKm * 1_000).rounded())
                : nil
            return WorkoutCompletion(
                id: "strava_\(activity.stravaId)",
                workoutName: activity.name,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(TimeInterval(durationSeconds)),
                durationSeconds: durationSeconds,
                avgHeartRate: nil,
                maxHeartRate: nil,
                activeCalories: nil,
                distanceMeters: distanceMeters,
                source: .manual,
                syncedToStrava: true,
                workoutId: nil,
                originalWorkout: nil,
                isSimulated: false
            )
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    static func weekCompletions(
        from completions: [WorkoutCompletion],
        now: Date = Date(),
        calendar: Calendar = mondayFirstCalendar
    ) -> [WorkoutCompletion] {
        completions.filter {
            ActivityHistoryFilter.thisWeek.includes($0.startedAt, now: now, calendar: calendar)
        }
    }

    static func monthCompletions(
        from completions: [WorkoutCompletion],
        now: Date = Date(),
        calendar: Calendar = mondayFirstCalendar
    ) -> [WorkoutCompletion] {
        completions.filter {
            calendar.isDate($0.startedAt, equalTo: now, toGranularity: .month)
        }
    }

    static func dayStreak(
        from completions: [WorkoutCompletion],
        today: Date = Date(),
        calendar: Calendar = mondayFirstCalendar
    ) -> (current: Int, best: Int) {
        let activeDays = Set(completions.map { calendar.startOfDay(for: $0.startedAt) })
        guard !activeDays.isEmpty else { return (0, 0) }

        var current = 0
        var cursor = calendar.startOfDay(for: today)
        while activeDays.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let sortedDays = activeDays.sorted()
        var best = 0
        var run = 0
        var prior: Date?
        for day in sortedDays {
            if let prior,
               let next = calendar.date(byAdding: .day, value: 1, to: prior),
               calendar.isDate(day, inSameDayAs: next) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            prior = day
        }
        return (current, best)
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
