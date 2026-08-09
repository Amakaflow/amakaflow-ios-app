//
//  SuggestWorkoutDisplayHelpers.swift
//  AmakaFlow
//
//  AMA-2373 / AMA-2371 — display helpers extracted from SuggestWorkoutView
//  to keep file_length / type_body_length under SwiftLint (strict) limits.
//

import SwiftUI

// Internal — `SuggestWorkoutGeneratingView` also reads `.badgeText`.
extension SuggestReadinessLevel {
    var title: String {
        switch self {
        case .green: return "Ready to train"
        case .yellow: return "Proceed with care"
        case .red: return "Recovery-first day"
        case .unknown: return "Readiness unavailable"
        }
    }

    var badgeText: String {
        switch self {
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .green: return Theme.Colors.readyHigh
        case .yellow: return Theme.Colors.readyModerate
        case .red: return Theme.Colors.readyLow
        case .unknown: return Theme.Colors.textTertiary
        }
    }
}

extension WorkoutSport {
    var symbolName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.flexibility"
        case .swimming: return "figure.pool.swim"
        case .cardio, .conditioning, .mixed: return "heart.fill"
        case .other: return "figure.mixed.cardio"
        }
    }
}

struct SuggestIntervalRow: View {
    let index: Int
    let interval: WorkoutInterval

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("\(index)")
                .font(Theme.Typography.captionBold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(intervalColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(intervalName)
                    .afH3()

                if let detail = intervalDetail {
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var intervalName: String {
        switch interval {
        case .warmup: return "Warm Up"
        case .cooldown: return "Cool Down"
        case .time(_, let target): return target ?? "Timed Interval"
        case .reps(_, _, let name, _, _, _): return name
        case .distance(let meters, _): return "\(meters)m"
        case .repeat(let reps, _): return "Repeat x\(reps)"
        case .rest: return "Rest"
        }
    }

    private var intervalDetail: String? {
        switch interval {
        case .warmup(let seconds, _), .cooldown(let seconds, _), .time(let seconds, _):
            return "\(seconds / 60) min"
        case .reps(let sets, let reps, _, let load, let restSec, _):
            var parts: [String] = []
            if let sets = sets { parts.append("\(sets) sets x") }
            parts.append("\(reps) reps")
            if let load = load { parts.append("@ \(load)") }
            if let rest = restSec { parts.append("(\(rest)s rest)") }
            return parts.joined(separator: " ")
        case .distance(_, let target): return target
        case .repeat(_, let intervals): return "\(intervals.count) exercises"
        case .rest(let seconds):
            if let sec = seconds { return "\(sec)s" }
            return "Until ready"
        }
    }

    private var intervalColor: Color {
        switch interval {
        case .warmup: return .orange
        case .cooldown: return .blue
        case .reps: return Theme.Colors.accentGreen
        case .time: return Theme.Colors.accentBlue
        case .rest: return .gray
        default: return Theme.Colors.accentBlue
        }
    }
}
