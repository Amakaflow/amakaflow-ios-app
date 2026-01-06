//
//  IntervalRow.swift
//  AmakaFlow
//
//  Individual interval row component
//

import SwiftUI
import UIKit

struct IntervalRow: View {
    let interval: WorkoutInterval
    let stepNumber: Int
    let isLast: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                // Step number badge
                Text("\(stepNumber)")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.Colors.surfaceElevated)
                    .overlay(
                        Circle()
                            .stroke(Theme.Colors.borderMedium, lineWidth: 1)
                    )
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    // Interval Type & Main Info
                    HStack(spacing: 8) {
                        Image(systemName: intervalIcon)
                            .font(.system(size: 14))
                            .foregroundColor(intervalColor)
                        
                        Text(intervalTitle)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                        
                        Spacer()
                        
                        Text(intervalDuration)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .frame(height: 20)
                    
                    // Additional Details
                    HStack(spacing: 8) {
                        if let details = intervalDetails {
                            Text(details)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        
                        // Follow-Along Link Button
                        if let followAlongUrl = getFollowAlongUrl() {
                            Button(action: {
                                openInstagram(followAlongUrl: followAlongUrl)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.system(size: 12))
                                    Text("Watch")
                                        .font(Theme.Typography.caption)
                                }
                                .foregroundColor(Theme.Colors.accentBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.accentBlue.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.leading, 22)
                    .frame(height: 16, alignment: .leading)
                    
                    // Nested Intervals (for repeat type)
                    if case .repeat(_, let intervals) = interval {
                        VStack(spacing: 8) {
                            ForEach(Array(intervals.enumerated()), id: \.offset) { index, subInterval in
                                NestedIntervalRow(interval: subInterval)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.leading, 22)
                    }
                }
                .frame(minHeight: 44) // Consistent minimum height for main content
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .frame(minHeight: 60) // Consistent minimum height for entire row
            
            if !isLast {
                Divider()
                    .background(Theme.Colors.borderLight)
                    .padding(.leading, 60)
            }
        }
    }
    
    // MARK: - Helper Functions
    private func getFollowAlongUrl() -> String? {
        if case .reps(_, _, _, _, _, let followAlongUrl) = interval {
            return followAlongUrl
        }
        return nil
    }
    
    private func openInstagram(followAlongUrl: String) {
        // Try to open Instagram app first, fallback to web
        let instagramAppUrl = "instagram://"
        let instagramWebUrl = followAlongUrl
        
        if let appUrl = URL(string: instagramAppUrl),
           UIApplication.shared.canOpenURL(appUrl) {
            // Open Instagram app
            UIApplication.shared.open(appUrl)
        } else if let webUrl = URL(string: instagramWebUrl) {
            // Open in Safari
            UIApplication.shared.open(webUrl)
        }
    }
    
    // MARK: - Computed Properties
    private var intervalIcon: String {
        switch interval {
        case .warmup: return "flame"
        case .cooldown: return "wind"
        case .time: return "clock"
        case .reps: return "arrow.clockwise"
        case .distance: return "location"
        case .repeat: return "repeat"
        case .rest: return "pause.circle.fill"
        }
    }
    
    private var intervalColor: Color {
        switch interval {
        case .warmup: return .orange
        case .cooldown: return .blue
        case .time: return Theme.Colors.accentBlue
        case .reps: return Theme.Colors.accentGreen
        case .distance: return .purple
        case .repeat: return .yellow
        case .rest: return .gray
        }
    }
    
    private var intervalTitle: String {
        switch interval {
        case .warmup: return "Warm Up"
        case .cooldown: return "Cool Down"
        case .time(_, let target):
            return target ?? "Work"
        case .reps(_, _, let name, _, _, _):
            return name
        case .distance:
            return "Run"
        case .repeat(let reps, _):
            return "Repeat \(reps)x"
        case .rest:
            return "Rest"
        }
    }
    
    private var intervalDuration: String {
        switch interval {
        case .warmup(let seconds, _), .cooldown(let seconds, _), .time(let seconds, _):
            return WorkoutHelpers.formatDuration(seconds: seconds)
        case .reps(_, let reps, _, _, _, _):
            return "\(reps) reps"
        case .distance(let meters, _):
            return WorkoutHelpers.formatDistance(meters: meters)
        case .repeat(_, let intervals):
            // Calculate total time for repeat block
            let totalSeconds = intervals.reduce(0) { total, interval in
                switch interval {
                case .warmup(let s, _), .cooldown(let s, _), .time(let s, _):
                    return total + s
                case .reps(_, _, _, _, let rest, _):
                    return total + (rest ?? 0)
                case .rest(let s):
                    return total + (s ?? 0)
                default:
                    return total
                }
            }
            return WorkoutHelpers.formatDuration(seconds: totalSeconds)
        case .rest(let seconds):
            if let secs = seconds {
                return WorkoutHelpers.formatDuration(seconds: secs)
            } else {
                return "Tap when ready"
            }
        }
    }
    
    private var intervalDetails: String? {
        switch interval {
        case .warmup(_, let target), .cooldown(_, let target), .time(_, let target), .distance(_, let target):
            return target
        case .reps(_, _, _, let load, let restSec, _):
            var details: [String] = []
            if let load = load {
                details.append("Load: \(load)")
            }
            if let rest = restSec {
                details.append("Rest: \(WorkoutHelpers.formatDuration(seconds: rest))")
            }
            return details.isEmpty ? nil : details.joined(separator: " • ")
        case .repeat:
            return nil
        case .rest:
            return nil
        }
    }
}

// MARK: - Nested Interval Row
struct NestedIntervalRow: View {
    let interval: WorkoutInterval
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.Colors.textSecondary)
                .frame(width: 4, height: 4)
            
            HStack {
                Text(intervalTitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Spacer()
                
                Text(intervalDuration)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 8)
        .background(Theme.Colors.surfaceElevated)
        .cornerRadius(Theme.CornerRadius.sm)
    }
    
    private var intervalTitle: String {
        switch interval {
        case .warmup: return "Warm Up"
        case .cooldown: return "Cool Down"
        case .time(_, let target): return target ?? "Work"
        case .reps(_, _, let name, _, _, _): return name
        case .distance: return "Run"
        case .repeat: return "Repeat"
        case .rest: return "Rest"
        }
    }

    private var intervalDuration: String {
        switch interval {
        case .warmup(let seconds, _), .cooldown(let seconds, _), .time(let seconds, _):
            return WorkoutHelpers.formatDuration(seconds: seconds)
        case .reps(_, let reps, _, _, _, _):
            return "\(reps) reps"
        case .distance(let meters, _):
            return WorkoutHelpers.formatDistance(meters: meters)
        case .repeat(let reps, _):
            return "\(reps)x"
        case .rest(let seconds):
            if let secs = seconds {
                return WorkoutHelpers.formatDuration(seconds: secs)
            } else {
                return "Tap when ready"
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        IntervalRow(
            interval: .warmup(seconds: 300, target: nil),
            stepNumber: 1,
            isLast: false
        )
        
        IntervalRow(
            interval: .reps(sets: 3, reps: 8, name: "Squat", load: "80% 1RM", restSec: 90, followAlongUrl: nil),
            stepNumber: 2,
            isLast: false
        )

        IntervalRow(
            interval: .repeat(reps: 3, intervals: [
                .reps(sets: nil, reps: 10, name: "Push Up", load: nil, restSec: 60, followAlongUrl: nil),
                .time(seconds: 60, target: "Rest")
            ]),
            stepNumber: 3,
            isLast: true
        )
    }
    .background(Theme.Colors.surface)
    .cornerRadius(Theme.CornerRadius.xl)
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
