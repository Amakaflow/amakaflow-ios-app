//
//  WorkoutCompletionViewModel.swift
//  AmakaFlow
//
//  View model for workout completion summary screen
//

import Foundation
import Combine

@MainActor
class WorkoutCompletionViewModel: ObservableObject {
    // Workout info
    let workoutName: String
    let durationSeconds: Int
    let deviceMode: DevicePreference

    // Health metrics
    let calories: Int?
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let heartRateSamples: [HeartRateSample]

    // State
    @Published var showComingSoonToast: Bool = false

    // Callbacks
    var onDismiss: (() -> Void)?

    init(
        workoutName: String,
        durationSeconds: Int,
        deviceMode: DevicePreference,
        calories: Int?,
        avgHeartRate: Int?,
        maxHeartRate: Int?,
        heartRateSamples: [HeartRateSample],
        onDismiss: (() -> Void)?
    ) {
        self.workoutName = workoutName
        self.durationSeconds = durationSeconds
        self.deviceMode = deviceMode
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.heartRateSamples = heartRateSamples
        self.onDismiss = onDismiss
    }

    // MARK: - Computed Properties

    var formattedDuration: String {
        let hours = durationSeconds / 3600
        let mins = (durationSeconds % 3600) / 60
        let secs = durationSeconds % 60

        if hours > 0 {
            return "\(hours)h \(mins)m \(secs)s"
        }
        return "\(mins)m \(secs)s"
    }

    var hasHeartRateData: Bool {
        avgHeartRate != nil || !heartRateSamples.isEmpty
    }

    var calculatedAvgHeartRate: Int? {
        // Use provided avgHeartRate if available
        if let avgHR = avgHeartRate {
            return avgHR
        }

        // Otherwise calculate from samples
        guard !heartRateSamples.isEmpty else { return nil }
        let sum = heartRateSamples.reduce(0) { $0 + $1.value }
        return sum / heartRateSamples.count
    }

    var calculatedMaxHeartRate: Int? {
        // Use provided maxHeartRate if available
        if let maxHR = maxHeartRate {
            return maxHR
        }

        // Otherwise calculate from samples
        return heartRateSamples.map { $0.value }.max()
    }

    // MARK: - Actions

    func onViewDetails() {
        showComingSoonToast = true

        // Auto-dismiss toast after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showComingSoonToast = false
        }
    }

    func onDone() {
        onDismiss?()
    }
}
