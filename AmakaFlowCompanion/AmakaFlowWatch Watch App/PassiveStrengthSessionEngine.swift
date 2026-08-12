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
    /// True when HealthKit failed to start — no HK workout will be saved.
    @Published private(set) var healthCaptureFailed = false

    private let healthManager = HealthKitWorkoutManager.shared
    private var timer: Timer?
    private var heartRateHandlerToken: UUID?
    private var workoutStartDate: Date?
    private var sessionID: String = ""
    private var sessionName: String = "Strength"
    private var averageHeartRateSamples: [Double] = []
    /// Wall-clock active time: accumulated across pauses + current running segment.
    private var accumulatedActive: TimeInterval = 0
    private var runningSince: Date?
    private var activationObserver: NSObjectProtocol?

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

    /// Active elapsed from wall-clock segments (watchOS may coalesce timer ticks).
    static nonisolated func activeElapsedSeconds(
        accumulatedActive: TimeInterval,
        runningSince: Date?,
        now: Date = Date()
    ) -> Int {
        var total = accumulatedActive
        if let runningSince {
            total += now.timeIntervalSince(runningSince)
        }
        return max(0, Int(total))
    }

    deinit {
        timer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func start(sessionID: String = FreeformStrengthWorkout.make().id, name: String = "Strength") async {
        flushPendingSummariesIfNeeded()
        observeActivationIfNeeded()

        if isActive {
            await discard()
        }

        self.sessionID = sessionID
        self.sessionName = name
        elapsedSeconds = 0
        accumulatedActive = 0
        runningSince = nil
        heartRate = 0
        activeCalories = 0
        totalCalories = 0
        averageHeartRateSamples = []
        summaryQueued = false
        healthCaptureFailed = false
        workoutStartDate = Date()
        phase = .running

        removeHeartRateHandler()
        heartRateHandlerToken = healthManager.addHeartRateHandler { [weak self] bpm, active in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.heartRate = bpm
                self.activeCalories = active
                self.totalCalories = self.healthManager.totalCalories
                if bpm > 0, self.phase == .running {
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
            healthCaptureFailed = true
            removeHeartRateHandler()
            phase = .idle
            workoutStartDate = nil
            accumulatedActive = 0
            runningSince = nil
            elapsedSeconds = 0
            playHaptic(.failure)
            return
        }

        runningSince = Date()
        startElapsedTimer()
        playHaptic(.start)
    }

    func pause() {
        guard phase == .running else { return }
        if let runningSince {
            accumulatedActive += Date().timeIntervalSince(runningSince)
            self.runningSince = nil
        }
        refreshElapsedFromWallClock()
        phase = .paused
        timer?.invalidate()
        timer = nil
        healthManager.pauseSession()
        playHaptic(.stop)
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .running
        runningSince = Date()
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
        if let runningSince {
            accumulatedActive += Date().timeIntervalSince(runningSince)
            self.runningSince = nil
        }
        refreshElapsedFromWallClock()
        timer?.invalidate()
        timer = nil
        phase = .ended
        let endDate = Date()
        // Snapshot calories before HK clears them in endSession().
        activeCalories = healthManager.activeCalories
        totalCalories = healthManager.totalCalories
        heartRate = healthManager.heartRate
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
        accumulatedActive = 0
        runningSince = nil
        elapsedSeconds = 0
        heartRate = 0
        activeCalories = 0
        totalCalories = 0
        averageHeartRateSamples = []
        summaryQueued = false
        healthCaptureFailed = false
        playHaptic(.stop)
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        removeHeartRateHandler()
        phase = .idle
        elapsedSeconds = 0
        accumulatedActive = 0
        runningSince = nil
        heartRate = 0
        activeCalories = 0
        totalCalories = 0
        averageHeartRateSamples = []
        workoutStartDate = nil
        healthCaptureFailed = false
        // Keep pending queue / defaults so a failed sync can still flush later.
        summaryQueued = false
    }

    /// Retry previously failed WatchConnectivity summary transfers.
    @discardableResult
    func retrySummarySync() -> Bool {
        if summaryQueued { return true }
        let queued = flushPendingSummariesIfNeeded()
        summaryQueued = queued
        return queued
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .running else { return }
                self.refreshElapsedFromWallClock()
                self.activeCalories = self.healthManager.activeCalories
                self.totalCalories = self.healthManager.totalCalories
                self.heartRate = self.healthManager.heartRate
            }
        }
    }

    private func refreshElapsedFromWallClock() {
        elapsedSeconds = Self.activeElapsedSeconds(
            accumulatedActive: accumulatedActive,
            runningSince: runningSince
        )
    }

    private func removeHeartRateHandler() {
        if let token = heartRateHandlerToken {
            healthManager.removeHeartRateHandler(token)
            heartRateHandlerToken = nil
        }
    }

    private func observeActivationIfNeeded() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: .watchConnectivitySessionActivated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.flushPendingSummariesIfNeeded(), self.phase == .ended, !self.summaryQueued {
                    self.summaryQueued = true
                }
            }
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
            return true
        }

        PassiveStrengthPendingSummaryStore.enqueue(summary)
        print("⌚️ Passive strength summary pending (no WCSession / encode failure)")
        return false
    }

    @discardableResult
    private func flushPendingSummariesIfNeeded() -> Bool {
        var queue = PassiveStrengthPendingSummaryStore.load()
        guard !queue.isEmpty else { return false }

        PassiveStrengthPendingSummaryStore.pruneStale(&queue)

        var remaining: [StandaloneWorkoutSummary] = []
        var anyTransferred = false
        for summary in queue {
            if transferSummary(summary) {
                anyTransferred = true
            } else {
                remaining.append(summary)
            }
        }

        PassiveStrengthPendingSummaryStore.save(remaining)
        return anyTransferred && remaining.isEmpty
    }

    private func transferSummary(_ summary: StandaloneWorkoutSummary) -> Bool {
        guard let session = WatchConnectivityBridge.shared.session else {
            return false
        }
        guard session.activationState == .activated else {
            print("⌚️ WCSession not activated yet — keeping pending summary")
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

    private func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}
