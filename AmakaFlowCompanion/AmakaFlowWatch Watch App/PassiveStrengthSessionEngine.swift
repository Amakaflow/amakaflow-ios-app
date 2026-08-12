//
//  PassiveStrengthSessionEngine.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 — passive free-capture strength session (no set/rest/crown).
//

import Combine
import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

@MainActor
final class PassiveStrengthSessionEngine: ObservableObject {
    enum Phase: String {
        case idle
        case running
        case paused
        case ended
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var totalCalories: Double = 0
    /// True when the completion summary was queued to the phone via WatchConnectivity.
    @Published private(set) var summaryQueued = false

    private let healthManager = HealthKitWorkoutManager.shared
    private var timer: Timer?
    private var heartRateHandlerToken: UUID?
    private var workoutStartDate: Date?
    private var sessionID: String = ""
    private var sessionName: String = "Strength"
    private var averageHeartRateSamples: [Double] = []
    private var pendingSummary: StandaloneWorkoutSummary?

    private static let pendingSummaryDefaultsKey = "ama2420_pending_passive_strength_summary"

    var formattedElapsedTime: String {
        Self.formatElapsed(seconds: elapsedSeconds)
    }

    var isActive: Bool {
        phase == .running || phase == .paused
    }

    static nonisolated func formatElapsed(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let remainder = clamped % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    deinit {
        timer?.invalidate()
    }

    func start(sessionID: String = FreeformStrengthWorkout.make().id, name: String = "Strength") async {
        flushPendingSummaryIfNeeded()

        if isActive {
            await discard()
        }

        self.sessionID = sessionID
        self.sessionName = name
        elapsedSeconds = 0
        heartRate = 0
        activeCalories = 0
        totalCalories = 0
        averageHeartRateSamples = []
        summaryQueued = false
        pendingSummary = nil
        workoutStartDate = Date()
        phase = .running

        removeHeartRateHandler()
        heartRateHandlerToken = healthManager.addHeartRateHandler { [weak self] bpm, active in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.heartRate = bpm
                self.activeCalories = active
                self.totalCalories = self.healthManager.totalCalories
                if bpm > 0 {
                    self.averageHeartRateSamples.append(bpm)
                }
            }
        }

        do {
            try await healthManager.startSession(
                activityType: HKWorkoutActivityMapping.activityType(for: .strength)
            )
        } catch {
            print("⌚️ Passive strength HK start failed: \(error)")
        }

        startElapsedTimer()
        playHaptic(.start)
    }

    func pause() {
        guard phase == .running else { return }
        phase = .paused
        timer?.invalidate()
        timer = nil
        healthManager.pauseSession()
        playHaptic(.stop)
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .running
        healthManager.resumeSession()
        startElapsedTimer()
        playHaptic(.start)
    }

    func togglePlayPause() {
        switch phase {
        case .running: pause()
        case .paused: resume()
        case .idle, .ended: break
        }
    }

    func end() async {
        guard isActive else { return }
        timer?.invalidate()
        timer = nil
        phase = .ended
        let endDate = Date()
        await healthManager.endSession()
        removeHeartRateHandler()
        playHaptic(.success)
        summaryQueued = queueSummaryToPhone(endDate: endDate)
    }

    func discard() async {
        timer?.invalidate()
        timer = nil
        phase = .idle
        await healthManager.discardSession()
        removeHeartRateHandler()
        workoutStartDate = nil
        elapsedSeconds = 0
        heartRate = 0
        activeCalories = 0
        totalCalories = 0
        averageHeartRateSamples = []
        summaryQueued = false
        pendingSummary = nil
        playHaptic(.stop)
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        removeHeartRateHandler()
        phase = .idle
        elapsedSeconds = 0
        heartRate = 0
        activeCalories = 0
        totalCalories = 0
        averageHeartRateSamples = []
        workoutStartDate = nil
        // Keep pendingSummary / defaults so a failed sync can still flush later.
        summaryQueued = false
    }

    /// Retry a previously failed WatchConnectivity summary transfer.
    @discardableResult
    func retrySummarySync() -> Bool {
        if summaryQueued { return true }
        let queued = flushPendingSummaryIfNeeded()
        summaryQueued = queued
        return queued
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .running else { return }
                self.elapsedSeconds += 1
                self.activeCalories = self.healthManager.activeCalories
                self.totalCalories = self.healthManager.totalCalories
                self.heartRate = self.healthManager.heartRate
            }
        }
    }

    private func removeHeartRateHandler() {
        if let token = heartRateHandlerToken {
            healthManager.removeHeartRateHandler(token)
            heartRateHandlerToken = nil
        }
    }

    @discardableResult
    private func queueSummaryToPhone(endDate: Date) -> Bool {
        guard let startDate = workoutStartDate else { return false }

        let avgHeartRate: Double? = averageHeartRateSamples.isEmpty
            ? nil
            : averageHeartRateSamples.reduce(0, +) / Double(averageHeartRateSamples.count)

        // Use active elapsed (excludes pause) so phone duration matches Watch display.
        let summary = StandaloneWorkoutSummary(
            workoutId: sessionID,
            workoutName: sessionName,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: max(0, elapsedSeconds),
            totalCalories: totalCalories > 0 ? totalCalories : activeCalories,
            averageHeartRate: avgHeartRate,
            completedSteps: 0,
            totalSteps: 0,
            setLogs: nil
        )

        if transferSummary(summary) {
            clearPendingSummary()
            return true
        }

        pendingSummary = summary
        persistPendingSummary(summary)
        print("⌚️ Passive strength summary pending (no WCSession / encode failure)")
        return false
    }

    @discardableResult
    private func flushPendingSummaryIfNeeded() -> Bool {
        let candidate = pendingSummary ?? loadPendingSummaryFromDefaults()
        guard let summary = candidate else { return false }
        if transferSummary(summary) {
            clearPendingSummary()
            return true
        }
        pendingSummary = summary
        return false
    }

    private func transferSummary(_ summary: StandaloneWorkoutSummary) -> Bool {
        guard let session = WatchConnectivityBridge.shared.session else {
            return false
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summary)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            session.transferUserInfo(["action": "workoutSummary", "summary": dict])
            print("⌚️ Passive strength summary queued (workoutId=\(summary.workoutId))")
            return true
        } catch {
            print("⌚️ Failed to encode passive strength summary: \(error)")
            return false
        }
    }

    private func persistPendingSummary(_ summary: StandaloneWorkoutSummary) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summary)
            UserDefaults.standard.set(data, forKey: Self.pendingSummaryDefaultsKey)
        } catch {
            print("⌚️ Failed to persist pending passive summary: \(error)")
        }
    }

    private func loadPendingSummaryFromDefaults() -> StandaloneWorkoutSummary? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingSummaryDefaultsKey) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(StandaloneWorkoutSummary.self, from: data)
        } catch {
            print("⌚️ Failed to load pending passive summary: \(error)")
            return nil
        }
    }

    private func clearPendingSummary() {
        pendingSummary = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingSummaryDefaultsKey)
    }

    private func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}
