//
//  PassiveStrengthSessionEngine.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 — passive free-capture strength session (no set/rest/crown).
//  AMA-2428 — post-end sport selection (AmakaFlow sport; HK type unchanged).
//

import Combine
import Foundation
import HealthKit
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
    /// AMA-2428 — athlete-chosen sport after End (defaults to Strength).
    @Published private(set) var selectedSport: WorkoutSport = .strength

    private let healthManager = HealthKitWorkoutManager.shared
    private var timer: Timer?
    private var heartRateHandlerToken: UUID?
    private var workoutStartDate: Date?
    private var workoutEndDate: Date?
    private var sessionID: String = ""
    private var averageHeartRateSamples: [Double] = []
    /// Wall-clock active time: accumulated across pauses + current running segment.
    private var accumulatedActive: TimeInterval = 0
    private var runningSince: Date?
    private var activationObserver: NSObjectProtocol?

    var formattedElapsedTime: String {
        Self.formatElapsed(seconds: elapsedSeconds)
    }

    var sessionDisplayName: String {
        selectedSport.displayName
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

    /// Resolve wire sport → Strength fallback for unknowns (AMA-2428).
    static nonisolated func resolvedSport(from raw: String?) -> WorkoutSport {
        WorkoutSport.resolveWireValue(raw)
    }

    deinit {
        timer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func start(sessionID: String = FreeformStrengthWorkout.make().id, name: String = "Strength") async {
        _ = PassiveStrengthSummaryTransfer.flushPending()
        observeActivationIfNeeded()

        if isActive {
            await discard()
        }

        self.sessionID = sessionID
        // Freeform HK session stays Strength; athlete reclassifies after End (AMA-2428).
        // `name` kept for call-site compatibility with freeform Start.
        selectedSport = .strength
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
        workoutEndDate = nil
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
            workoutEndDate = nil
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
        workoutEndDate = endDate
        // Snapshot calories before HK clears them in endSession().
        activeCalories = healthManager.activeCalories
        totalCalories = healthManager.totalCalories
        heartRate = healthManager.heartRate
        await healthManager.endSession()
        removeHeartRateHandler()
        playHaptic(.success)
        // Delay WC transfer until athlete confirms sport on Done (still persist pending).
        persistPendingSummary(endDate: endDate)
        summaryQueued = false
    }

    /// AMA-2428 — pick Strength / Mixed / … after End; updates pending summary.
    func selectSport(_ sport: WorkoutSport) {
        selectedSport = sport
        guard phase == .ended, let endDate = workoutEndDate else { return }
        persistPendingSummary(endDate: endDate)
        summaryQueued = false
    }

    /// Confirm sport and queue WatchConnectivity transfer.
    @discardableResult
    func confirmSportAndSync() -> Bool {
        guard phase == .ended, let endDate = workoutEndDate else { return summaryQueued }
        persistPendingSummary(endDate: endDate)
        let transferredIDs = PassiveStrengthSummaryTransfer.flushPending()
        if transferredIDs.contains(sessionID) {
            summaryQueued = true
            return true
        }
        summaryQueued = transferCurrentSummary(endDate: endDate)
        return summaryQueued
    }

    func discard() async {
        timer?.invalidate()
        timer = nil
        phase = .idle
        await healthManager.discardSession()
        removeHeartRateHandler()
        workoutStartDate = nil
        workoutEndDate = nil
        accumulatedActive = 0
        runningSince = nil
        elapsedSeconds = 0
        heartRate = 0
        activeCalories = 0
        totalCalories = 0
        averageHeartRateSamples = []
        summaryQueued = false
        healthCaptureFailed = false
        selectedSport = .strength
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
        workoutEndDate = nil
        healthCaptureFailed = false
        selectedSport = .strength
        // Keep pending queue / defaults so a failed sync can still flush later.
        summaryQueued = false
    }

    /// Retry previously failed WatchConnectivity summary transfers.
    @discardableResult
    func retrySummarySync() -> Bool {
        if summaryQueued { return true }
        if phase == .ended, let endDate = workoutEndDate {
            persistPendingSummary(endDate: endDate)
            let transferredIDs = PassiveStrengthSummaryTransfer.flushPending()
            if transferredIDs.contains(sessionID) {
                summaryQueued = true
                return true
            }
            summaryQueued = transferCurrentSummary(endDate: endDate)
            return summaryQueued
        }
        _ = PassiveStrengthSummaryTransfer.flushPending()
        summaryQueued = PassiveStrengthPendingSummaryStore.load().isEmpty
        return summaryQueued
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
                let transferredIDs = PassiveStrengthSummaryTransfer.flushPending()
                if self.phase == .ended, !self.summaryQueued, transferredIDs.contains(self.sessionID) {
                    self.summaryQueued = true
                }
            }
        }
    }

    private func persistPendingSummary(endDate: Date) {
        guard let summary = currentSummary(endDate: endDate) else { return }
        PassiveStrengthSummaryTransfer.persistPending(summary)
    }

    @discardableResult
    private func transferCurrentSummary(endDate: Date) -> Bool {
        guard let summary = currentSummary(endDate: endDate) else { return false }
        return PassiveStrengthSummaryTransfer.transferCurrent(summary)
    }

    private func currentSummary(endDate: Date) -> StandaloneWorkoutSummary? {
        PassiveStrengthSummaryTransfer.makeSummary(
            from: PassiveStrengthSummaryTransfer.Snapshot(
                sessionID: sessionID,
                selectedSport: selectedSport,
                startDate: workoutStartDate,
                endDate: endDate,
                elapsedSeconds: elapsedSeconds,
                totalCalories: totalCalories,
                activeCalories: activeCalories,
                averageHeartRateSamples: averageHeartRateSamples
            )
        )
    }

    private func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}
