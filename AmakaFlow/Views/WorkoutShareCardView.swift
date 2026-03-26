//
//  WorkoutShareCardView.swift
//  AmakaFlow
//
//  Post-workout shareable card for social media.
//  Supports 9:16 (Stories) and 1:1 (square) aspect ratios.
//  AMA-1284
//

import SwiftUI

// MARK: - Card Data

struct WorkoutShareCardData {
    let workoutName: String
    let durationSeconds: Int
    let exerciseCount: Int
    let totalVolumeKg: Double
    let newPRs: [PRDetectionResult.NewPR]
    let currentStreak: Int

    var formattedDuration: String {
        let hours = durationSeconds / 3600
        let mins = (durationSeconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    var formattedVolume: String {
        if totalVolumeKg >= 1000 {
            return String(format: "%.1fk kg", totalVolumeKg / 1000)
        }
        return String(format: "%.0f kg", totalVolumeKg)
    }
}

enum ShareCardAspect {
    case stories  // 9:16
    case square   // 1:1

    var size: CGSize {
        switch self {
        case .stories: return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        }
    }

    var previewSize: CGSize {
        switch self {
        case .stories: return CGSize(width: 270, height: 480)
        case .square: return CGSize(width: 300, height: 300)
        }
    }
}

// MARK: - Share Card View

struct WorkoutShareCardView: View {
    let data: WorkoutShareCardData
    let aspect: ShareCardAspect

    private let accentPurple = Color(hex: "6C5CE7")
    private let gold = Color(hex: "FFD700")

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [Color(hex: "0D0D0F"), Color(hex: "1A1A2E"), Color(hex: "0D0D0F")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle grid pattern overlay
            GeometryReader { geo in
                Path { path in
                    let spacing: CGFloat = 40
                    for x in stride(from: 0, through: geo.size.width, by: spacing) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    for y in stride(from: 0, through: geo.size.height, by: spacing) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.03), lineWidth: 0.5)
            }

            VStack(spacing: 0) {
                Spacer()

                // Workout name
                Text(data.workoutName)
                    .font(.system(size: aspect == .stories ? 32 : 28, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("WORKOUT COMPLETE")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentPurple)
                    .tracking(2)
                    .padding(.top, 8)

                Spacer().frame(height: aspect == .stories ? 40 : 24)

                // Stats grid
                statsGrid

                // PRs section
                if !data.newPRs.isEmpty {
                    Spacer().frame(height: aspect == .stories ? 32 : 20)
                    prSection
                }

                // Streak
                if data.currentStreak > 1 {
                    Spacer().frame(height: 20)
                    streakBadge
                }

                Spacer()

                // Branding
                branding
                    .padding(.bottom, aspect == .stories ? 60 : 24)
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 16) {
            statItem(value: data.formattedDuration, label: "Duration")
            divider
            statItem(value: "\(data.exerciseCount)", label: "Exercises")
            divider
            statItem(value: data.formattedVolume, label: "Volume")
        }
        .padding(.horizontal, 24)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "9CA3AF"))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 40)
    }

    // MARK: - PR Section

    private var prSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundColor(gold)
                Text("NEW PERSONAL RECORDS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(gold)
                    .tracking(1)
            }

            ForEach(Array(data.newPRs.prefix(3).enumerated()), id: \.offset) { _, pr in
                HStack {
                    Text(pr.exerciseName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text(formatPRValue(pr))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(gold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(gold.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 24)
    }

    private func formatPRValue(_ pr: PRDetectionResult.NewPR) -> String {
        switch pr.type {
        case .heaviestWeight:
            return String(format: "%.1f kg", pr.newValue)
        case .mostReps:
            return "\(Int(pr.newValue)) reps"
        case .mostVolume:
            return String(format: "%.0f kg vol", pr.newValue)
        }
    }

    // MARK: - Streak

    private var streakBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "F97316"))
            Text("\(data.currentStreak) day streak")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: "F97316").opacity(0.15))
        .cornerRadius(20)
    }

    // MARK: - Branding

    private var branding: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accentPurple)
                .frame(width: 8, height: 8)
            Text("AmakaFlow")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "9CA3AF"))
        }
    }
}

// MARK: - Preview

#Preview("Stories") {
    WorkoutShareCardView(
        data: WorkoutShareCardData(
            workoutName: "Upper Body Strength",
            durationSeconds: 3600,
            exerciseCount: 6,
            totalVolumeKg: 4200,
            newPRs: [
                PRDetectionResult.NewPR(
                    exerciseName: "Bench Press",
                    type: .heaviestWeight,
                    oldValue: 80,
                    newValue: 85,
                    reps: 1,
                    weight: nil
                )
            ],
            currentStreak: 5
        ),
        aspect: .stories
    )
    .frame(width: 270, height: 480)
    .cornerRadius(12)
}
