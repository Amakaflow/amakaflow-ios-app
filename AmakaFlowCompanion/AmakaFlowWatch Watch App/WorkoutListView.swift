//
//  WorkoutListView.swift
//  AmakaFlowWatch Watch App
//
//  Main workout list view on Apple Watch
//

import SwiftUI

struct WorkoutListView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    
    var body: some View {
        NavigationStack {
            ZStack {
                if manager.workouts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        
                        Text("No Workouts")
                            .font(.headline)
                        
                        Text("Send workouts from your iPhone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(manager.workouts) { workout in
                            NavigationLink(destination: WorkoutDetailWatchView(workout: workout)) {
                                WatchWorkoutRow(workout: workout)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Workouts")
        }
    }
}

// MARK: - Watch Workout Row
struct WatchWorkoutRow: View {
    let workout: Workout
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.name)
                .font(.headline)
                .lineLimit(2)
            
            HStack(spacing: 8) {
                Label(workout.formattedDuration, systemImage: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Label(workout.sport.rawValue.capitalized, systemImage: sportIcon)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var sportIcon: String {
        switch workout.sport {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.yoga"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "figure.mixed.cardio"
        case .other: return "figure.elliptical"
        }
    }
}

// MARK: - Workout Detail (Watch)
struct WorkoutDetailWatchView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    let workout: Workout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.name)
                        .font(.headline)

                    if let description = workout.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label(workout.formattedDuration, systemImage: "clock")
                            .font(.caption2)
                        Label("\(workout.intervalCount) steps", systemImage: "target")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }

                // Intervals Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Steps")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(workout.intervals.enumerated()), id: \.offset) { index, interval in
                        WatchIntervalRow(interval: interval, number: index + 1)
                    }
                }

                // Start Button - navigates to execution view
                NavigationLink(destination: StandaloneWorkoutExecutionView(workout: workout)) {
                    Label("Start Workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Watch Interval Row
struct WatchIntervalRow: View {
    let interval: WorkoutInterval
    let number: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(intervalTitle)
                    .font(.caption)
                
                Text(intervalDuration)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.2)) // systemGray6 not available in watchOS
        .cornerRadius(8)
    }
    
    private var intervalTitle: String {
        switch interval {
        case .warmup: return "Warm Up"
        case .cooldown: return "Cool Down"
        case .time(_, let target): return target ?? "Work"
        case .reps(_, _, let name, _, _, _): return name
        case .distance: return "Run"
        case .repeat(let reps, _): return "Repeat \(reps)x"
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
        case .repeat(_, let intervals):
            return "\(intervals.count) steps"
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
    WorkoutListView()
        .environmentObject(WatchWorkoutManager())
}
