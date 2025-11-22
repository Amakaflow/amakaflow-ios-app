//
//  WorkoutCard.swift
//  AmakaFlow
//
//  Reusable workout card component
//

import SwiftUI

struct WorkoutCard: View {
    let workout: Workout
    var scheduledDate: Date? = nil
    var scheduledTime: String? = nil
    let isPrimary: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(iconBackgroundColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .stroke(iconBackgroundColor.opacity(0.2), lineWidth: 1)
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 24))
                        .foregroundColor(iconBackgroundColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.name)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    
                    if let description = workout.description {
                        Text(description)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(2)
                            .padding(.bottom, 4)
                    }
                    
                    // Metadata
                    VStack(alignment: .leading, spacing: 4) {
                        // First line: Duration and Type
                        HStack(spacing: 6) {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                Text(workout.formattedDuration)
                                    .font(Theme.Typography.caption)
                                    .lineLimit(1)
                            }
                            
                            Text("•")
                                .font(.system(size: 9))
                            
                            Text(workout.sport.rawValue.capitalized)
                                .font(Theme.Typography.caption)
                                .lineLimit(1)
                        }
                        
                        // Second line: Steps
                        HStack(spacing: 3) {
                            Image(systemName: "target")
                                .font(.system(size: 11))
                            Text("\(workout.intervalCount) step\(workout.intervalCount == 1 ? "" : "s")")
                                .font(Theme.Typography.caption)
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(Theme.Colors.textSecondary)
                    
                    // Scheduled Date/Time
                    if let date = scheduledDate {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                            
                            Text(formatScheduledDate(date, time: scheduledTime))
                                .font(Theme.Typography.caption)
                        }
                        .foregroundColor(Theme.Colors.accentBlue)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 8)
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.leading, 4)
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                .stroke(borderColor, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.xl)
    }
    
    // MARK: - Helpers
    private var iconName: String {
        isPrimary ? "play.fill" : "target"
    }
    
    private var iconBackgroundColor: Color {
        isPrimary ? Theme.Colors.accentBlue : Theme.Colors.accentGreen
    }
    
    private var borderColor: Color {
        Theme.Colors.borderLight
    }
    
    private func formatScheduledDate(_ date: Date, time: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        var result = formatter.string(from: date)
        
        if let time = time {
            result += " at \(time)"
        }
        
        return result
    }
}

#Preview {
    VStack(spacing: 16) {
        WorkoutCard(
            workout: Workout(
                name: "Full Body Strength",
                sport: .strength,
                duration: 1890,
                intervals: [
                    .warmup(seconds: 300, target: nil),
                    .reps(reps: 8, name: "Squat", load: nil, restSec: 90)
                ],
                description: "Complete full body workout",
                source: .coach
            ),
            scheduledDate: Date(),
            scheduledTime: "09:00",
            isPrimary: true
        )
        
        WorkoutCard(
            workout: Workout(
                name: "Speed Work",
                sport: .running,
                duration: 2640,
                intervals: [
                    .warmup(seconds: 600, target: nil),
                    .distance(meters: 400, target: nil)
                ],
                description: "400m repeats",
                source: .coach
            ),
            isPrimary: false
        )
    }
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
