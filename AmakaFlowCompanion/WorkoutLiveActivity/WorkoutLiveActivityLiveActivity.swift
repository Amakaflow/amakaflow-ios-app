//
//  WorkoutLiveActivityLiveActivity.swift
//  WorkoutLiveActivity
//
//  Live Activity UI for Dynamic Island and Lock Screen
//
//  NOTE: WorkoutActivityAttributes is imported from the shared file
//  that is added to both the main app and widget extension targets.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget

struct WorkoutLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
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
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
            .widgetURL(URL(string: "amakaflow://workout"))
            .keylineTint(Color.blue)
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Left: Step info
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.workoutName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(context.state.stepName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)

                if let roundInfo = context.state.roundInfo {
                    Text(roundInfo)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Right: Timer or step count
            VStack(alignment: .trailing, spacing: 4) {
                if context.state.isTimedStep {
                    Text(context.state.formattedTime)
                        .font(.title)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(context.state.isPaused ? .orange : .primary)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                }

                Text("\(context.state.stepIndex)/\(context.state.stepCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.8))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Compact Views (Pill form)

struct CompactLeadingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
            .foregroundColor(context.state.isPaused ? .orange : .blue)
    }
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        if context.state.isTimedStep {
            Text(context.state.formattedTime)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(context.state.isPaused ? .orange : .white)
        } else {
            Text("\(context.state.stepIndex)/\(context.state.stepCount)")
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Minimal View (Single cutout)

struct MinimalView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
            .foregroundColor(context.state.isPaused ? .orange : .blue)
    }
}

// MARK: - Expanded Views

struct ExpandedLeadingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: context.state.isPaused ? "pause.circle.fill" : "play.circle.fill")
                .font(.title2)
                .foregroundColor(context.state.isPaused ? .orange : .green)

            Text(context.state.isPaused ? "Paused" : "Active")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct ExpandedTrailingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if context.state.isTimedStep {
                Text(context.state.formattedTime)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
            } else {
                Image(systemName: "arrow.forward.circle")
                    .font(.title2)
            }

            Text("\(context.state.stepIndex)/\(context.state.stepCount)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct ExpandedCenterView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(spacing: 2) {
            Text(context.state.stepName)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
        }
    }
}

struct ExpandedBottomView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * context.state.progressPercent, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(context.attributes.workoutName)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                if let roundInfo = context.state.roundInfo {
                    Text(roundInfo)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Previews

extension WorkoutActivityAttributes {
    fileprivate static var preview: WorkoutActivityAttributes {
        WorkoutActivityAttributes(workoutId: "preview", workoutName: "Morning HIIT")
    }
}

extension WorkoutActivityAttributes.ContentState {
    fileprivate static var running: WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phase: "running",
            stepName: "Jumping Jacks",
            stepIndex: 3,
            stepCount: 12,
            remainingSeconds: 45,
            stepType: "timed",
            roundInfo: "Round 2/4"
        )
    }

    fileprivate static var paused: WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phase: "paused",
            stepName: "Burpees",
            stepIndex: 5,
            stepCount: 12,
            remainingSeconds: 30,
            stepType: "timed",
            roundInfo: nil
        )
    }

    fileprivate static var reps: WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phase: "running",
            stepName: "Push-ups x 15",
            stepIndex: 7,
            stepCount: 12,
            remainingSeconds: 0,
            stepType: "reps",
            roundInfo: "Round 3/4"
        )
    }
}

#Preview("Notification", as: .content, using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivityLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState.running
    WorkoutActivityAttributes.ContentState.paused
    WorkoutActivityAttributes.ContentState.reps
}
