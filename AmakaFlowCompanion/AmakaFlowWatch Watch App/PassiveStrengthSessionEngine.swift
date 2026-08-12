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

    private let healthManager = HealthKitWorkoutManager.shared
    private var timer: Timer?
    private var heartRateHandlerToken: UUID?
    private var workoutStartDate: Date?
    private var sessionID: String = ""
    private var sessionName: String = "Strength"
    private var averageHeartRateSamples: [Double] = []

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var isActive: Bool {
        phase == .running || phase == .paused
    }

    func start(sessionID: String = FreeformStrengthWorkout.make().id, name: String = "Strength") async {
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
        workoutStartDate = Date()
        phase = .running

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
        sendSummaryToPhone(endDate: endDate)
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

    private func sendSummaryToPhone(endDate: Date) {
        guard let startDate = workoutStartDate else { return }

        let avgHeartRate: Double? = averageHeartRateSamples.isEmpty
            ? nil
            : averageHeartRateSamples.reduce(0, +) / Double(averageHeartRateSamples.count)

        let summary = StandaloneWorkoutSummary(
            workoutId: sessionID,
            workoutName: sessionName,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: max(0, Int(endDate.timeIntervalSince(startDate))),
            totalCalories: totalCalories > 0 ? totalCalories : activeCalories,
            averageHeartRate: avgHeartRate,
            completedSteps: 0,
            totalSteps: 0,
            setLogs: nil
        )

        guard let session = WatchConnectivityBridge.shared.session else {
            print("⌚️ No WCSession, can't queue passive strength summary")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summary)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            session.transferUserInfo(["action": "workoutSummary", "summary": dict])
            print("⌚️ Passive strength summary queued (workoutId=\(sessionID))")
        } catch {
            print("⌚️ Failed to encode passive strength summary: \(error)")
        }
    }

    private func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}
