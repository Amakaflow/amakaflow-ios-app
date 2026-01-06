//
//  VoiceWorkoutReviewView.swift
//  AmakaFlow
//
//  View for reviewing and editing parsed workout before logging to history (AMA-5)
//

import SwiftUI

struct VoiceWorkoutReviewView: View {
    @ObservedObject var viewModel: VoiceWorkoutViewModel
    @State private var showingEditName = false
    @State private var editedName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Confidence indicator
                if viewModel.confidence < 0.9 {
                    confidenceAlert
                }

                // Workout header
                workoutHeader

                // Completion details (when did you finish, how long)
                completionDetailsSection

                // Intervals list
                if let workout = viewModel.workout {
                    intervalsSection(workout.intervals)
                }

                // Suggestions
                if !viewModel.suggestions.isEmpty {
                    suggestionsSection
                }

                Spacer(minLength: 100)
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .alert("Edit Workout Name", isPresented: $showingEditName) {
            TextField("Workout name", text: $editedName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                viewModel.updateWorkoutName(editedName)
            }
        }
    }

    // MARK: - Confidence Alert

    private var confidenceAlert: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.confidenceDescription)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Please review the workout details carefully")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Workout Header

    private var workoutHeader: some View {
        VStack(spacing: 16) {
            // Name with edit button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.workout?.name ?? "Untitled Workout")
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 8) {
                        Image(systemName: sportIcon)
                            .foregroundColor(Theme.Colors.accentBlue)
                        Text(viewModel.workout?.sport.rawValue.capitalized ?? "Cardio")
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text(viewModel.workout?.formattedDuration ?? "0m")
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }

                Spacer()

                Button {
                    editedName = viewModel.workout?.name ?? ""
                    showingEditName = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }
            .padding()
            .background(Theme.Colors.surface)
            .cornerRadius(12)
        }
    }

    private var sportIcon: String {
        switch viewModel.workout?.sport {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.flexibility"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "heart.fill"
        default: return "sportscourt"
        }
    }

    // MARK: - Completion Details Section

    private var completionDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Completion Details")
                .font(.headline)

            // Duration picker
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(Theme.Colors.accentBlue)
                    .frame(width: 24)

                Text("Duration")
                    .font(.subheadline)

                Spacer()

                Picker("Duration", selection: $viewModel.completedDurationMinutes) {
                    ForEach([5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 75, 90, 120], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.vertical, 4)

            Divider()

            // Completed at time picker
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(Theme.Colors.accentGreen)
                    .frame(width: 24)

                Text("Completed")
                    .font(.subheadline)

                Spacer()

                DatePicker(
                    "",
                    selection: $viewModel.completedAt,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
            }
            .padding(.vertical, 4)
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Intervals Section

    private func intervalsSection(_ intervals: [WorkoutInterval]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workout Steps")
                    .font(.headline)

                Spacer()

                Text("\(countIntervals(intervals)) steps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(Array(intervals.enumerated()), id: \.offset) { index, interval in
                    IntervalRowView(index: index + 1, interval: interval)
                }
            }
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    private func countIntervals(_ intervals: [WorkoutInterval]) -> Int {
        var count = 0
        for interval in intervals {
            switch interval {
            case .repeat(let reps, let subIntervals):
                count += reps * countIntervals(subIntervals)
            default:
                count += 1
            }
        }
        return count
    }

    // MARK: - Suggestions Section

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(.headline)

            ForEach(viewModel.suggestions, id: \.self) { suggestion in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)

                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }
}

// MARK: - Interval Row View

private struct IntervalRowView: View {
    let index: Int
    let interval: WorkoutInterval

    var body: some View {
        HStack(spacing: 12) {
            // Index badge
            Text("\(index)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(iconColor)
                .clipShape(Circle())

            // Icon
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch interval {
        case .warmup: return "flame"
        case .cooldown: return "snowflake"
        case .time: return "timer"
        case .reps: return "dumbbell.fill"
        case .distance: return "location"
        case .repeat: return "arrow.clockwise"
        case .rest: return "pause.circle.fill"
        }
    }

    private var iconColor: Color {
        switch interval {
        case .warmup: return .orange
        case .cooldown: return .blue
        case .time: return .green
        case .reps: return .purple
        case .distance: return .cyan
        case .repeat: return .indigo
        case .rest: return .gray
        }
    }

    private var title: String {
        switch interval {
        case .warmup: return "Warm Up"
        case .cooldown: return "Cool Down"
        case .time: return "Timed Interval"
        case .reps(_, _, let name, _, _, _): return name
        case .distance: return "Distance"
        case .repeat(let reps, _): return "Repeat \(reps)x"
        case .rest: return "Rest"
        }
    }

    private var detail: String {
        switch interval {
        case .warmup(let seconds, let target):
            return formatTime(seconds) + (target.map { " • \($0)" } ?? "")
        case .cooldown(let seconds, let target):
            return formatTime(seconds) + (target.map { " • \($0)" } ?? "")
        case .time(let seconds, let target):
            return formatTime(seconds) + (target.map { " • \($0)" } ?? "")
        case .reps(let sets, let reps, _, let load, let rest, _):
            var parts: [String] = []
            if let s = sets {
                parts.append("\(s) sets × \(reps) reps")
            } else {
                parts.append("\(reps) reps")
            }
            if let l = load { parts.append(l) }
            if let r = rest { parts.append("Rest: \(r)s") }
            return parts.joined(separator: " • ")
        case .distance(let meters, let target):
            return WorkoutHelpers.formatDistance(meters: meters) + (target.map { " • \($0)" } ?? "")
        case .repeat(_, let subIntervals):
            return "\(subIntervals.count) exercises per round"
        case .rest(let seconds):
            if let secs = seconds {
                return formatTime(secs)
            } else {
                return "Tap when ready"
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        if seconds >= 60 {
            let min = seconds / 60
            let sec = seconds % 60
            return sec > 0 ? "\(min)m \(sec)s" : "\(min) min"
        } else {
            return "\(seconds) sec"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VoiceWorkoutReviewView(viewModel: VoiceWorkoutViewModel())
            .navigationTitle("Review Workout")
    }
}
