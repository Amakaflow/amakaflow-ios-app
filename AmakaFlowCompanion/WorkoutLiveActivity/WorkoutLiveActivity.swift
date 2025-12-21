//
//  WorkoutLiveActivity.swift
//  WorkoutLiveActivity
//
//  Live Activity widget for workout tracking on Dynamic Island and Lock Screen
//

import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock Screen Banner
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Region (long press)
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                // Compact Left (pill)
                CompactLeadingView(context: context)
            } compactTrailing: {
                // Compact Right (pill)
                CompactTrailingView(context: context)
            } minimal: {
                // Minimal (when other activity present)
                MinimalView(context: context)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Progress Circle
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: context.state.progressPercent)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(context.state.stepIndex)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.stepName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(context.attributes.workoutName)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)

                    if let roundInfo = context.state.roundInfo {
                        Text("•")
                            .foregroundColor(.white.opacity(0.5))
                        Text(roundInfo)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            Spacer()

            // Timer or Step indicator
            if context.state.isTimedStep {
                Text(context.state.formattedTime)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            } else {
                VStack(spacing: 0) {
                    Text("\(context.state.stepIndex)")
                        .font(.system(size: 18, weight: .bold))
                    Text("of \(context.state.stepCount)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }
}

// MARK: - Dynamic Island Compact Views

struct CompactLeadingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                .font(.system(size: 12))
        }
        .foregroundColor(.white)
    }
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        if context.state.isTimedStep {
            Text(context.state.formattedTime)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        } else {
            Text("\(context.state.stepIndex)/\(context.state.stepCount)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

struct MinimalView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: context.state.progressPercent)
                .stroke(Color.blue, lineWidth: 2)
                .rotationEffect(.degrees(-90))

            Image(systemName: "figure.run")
                .font(.system(size: 10))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Dynamic Island Expanded Views

struct ExpandedLeadingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.3))
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 20))
                .foregroundColor(.blue)
        }
        .frame(width: 44, height: 44)
    }
}

struct ExpandedTrailingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        if context.state.isTimedStep {
            Text(context.state.formattedTime)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        } else {
            VStack(spacing: 0) {
                Text("\(context.state.stepIndex)")
                    .font(.system(size: 24, weight: .bold))
                Text("of \(context.state.stepCount)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            .foregroundColor(.white)
        }
    }
}

struct ExpandedCenterView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(spacing: 2) {
            Text(context.state.stepName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            if let roundInfo = context.state.roundInfo {
                Text(roundInfo)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

struct ExpandedBottomView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        // Progress bar
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.blue)
                    .frame(width: geo.size.width * context.state.progressPercent, height: 4)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 8)
    }
}

// MARK: - Preview Provider

#Preview("Lock Screen", as: .content, using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState.running
    WorkoutActivityAttributes.ContentState.paused
}

extension WorkoutActivityAttributes {
    static var preview: WorkoutActivityAttributes {
        WorkoutActivityAttributes(workoutId: "preview", workoutName: "Morning Strength")
    }
}

extension WorkoutActivityAttributes.ContentState {
    static var running: WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phase: "running",
            stepName: "Squats",
            stepIndex: 3,
            stepCount: 12,
            remainingSeconds: 45,
            stepType: "timed",
            roundInfo: "Round 2/4"
        )
    }

    static var paused: WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phase: "paused",
            stepName: "Rest",
            stepIndex: 5,
            stepCount: 12,
            remainingSeconds: 30,
            stepType: "timed",
            roundInfo: nil
        )
    }
}
