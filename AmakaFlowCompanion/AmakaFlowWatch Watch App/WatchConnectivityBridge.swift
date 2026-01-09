//
//  WatchConnectivityBridge.swift
//  AmakaFlowWatch Watch App
//
//  Handles WatchConnectivity communication with iPhone for remote control
//

import Combine
import Foundation
import WatchConnectivity
import WatchKit

@MainActor
final class WatchConnectivityBridge: NSObject, ObservableObject {
    static let shared = WatchConnectivityBridge()

    // MARK: - Published State

    @Published private(set) var isSessionActivated = false
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var workoutState: WatchWorkoutState?
    @Published private(set) var lastError: Error?
    @Published private(set) var pendingCommand: String?

    // Health metrics from HealthKit
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0

    private(set) var session: WCSession?
    private var pendingCommandId: String?
    private var healthManager = HealthKitWorkoutManager.shared
    private var hrUpdateTimer: Timer?

    private override init() {
        super.init()

        print("⌚️ WatchConnectivityBridge init: WCSession.isSupported() = \(WCSession.isSupported())")

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            print("⌚️ WatchConnectivityBridge init: WCSession activation requested")
        } else {
            // WCSession not supported - mark as activated but with error state
            print("⌚️ WatchConnectivityBridge init: WCSession NOT supported!")
            isSessionActivated = true  // Allow view to proceed, will show disconnected
        }

        // Subscribe to health updates
        setupHealthKitBindings()
    }

    // MARK: - HealthKit Integration

    private func setupHealthKitBindings() {
        healthManager.onHeartRateUpdate = { [weak self] hr, calories in
            Task { @MainActor in
                self?.heartRate = hr
                self?.activeCalories = calories
            }
        }
    }

    func startHealthSession() async {
        do {
            try await healthManager.startSession()
            startHRStreaming()
        } catch {
            print("⌚️ Failed to start health session: \(error)")
        }
    }

    func endHealthSession() async {
        stopHRStreaming()
        await healthManager.endSession()
        heartRate = 0
        activeCalories = 0
    }

    private func startHRStreaming() {
        // Send HR updates to phone every 5 seconds
        hrUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendHealthMetricsToPhone()
            }
        }
    }

    private func stopHRStreaming() {
        hrUpdateTimer?.invalidate()
        hrUpdateTimer = nil
    }

    func sendHealthMetricsToPhone() {
        guard let session = session, session.isReachable else { return }
        guard healthManager.isSessionActive else { return }

        session.sendMessage(
            [
                "action": "healthMetrics",
                "heartRate": heartRate,
                "activeCalories": activeCalories,
                "timestamp": Date().timeIntervalSince1970
            ],
            replyHandler: nil,
            errorHandler: { error in
                print("⌚️ Failed to send health metrics: \(error)")
            }
        )
    }

    // MARK: - Connection Status

    var isConnected: Bool {
        guard let session = session else { return false }
        return session.activationState == .activated && session.isReachable
    }

    // MARK: - Send Commands

    func sendCommand(_ command: WatchRemoteCommand) {
        guard let session = session, session.isReachable else {
            print("⌚️ Phone not reachable, cannot send command")
            lastError = WatchConnectivityBridgeError.phoneNotReachable
            playHaptic(.failure)
            return
        }

        let commandId = UUID().uuidString
        pendingCommandId = commandId
        pendingCommand = command.rawValue

        session.sendMessage(
            [
                "action": "command",
                "command": command.rawValue,
                "commandId": commandId
            ],
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.pendingCommand = nil
                    if reply["status"] as? String == "received" {
                        print("⌚️ Command acknowledged: \(command.rawValue)")
                        self?.playHaptic(.success)
                    }
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    print("⌚️ Failed to send command: \(error)")
                    self?.lastError = error
                    self?.pendingCommand = nil
                    self?.playHaptic(.failure)
                }
            }
        )

        print("⌚️ Sent command: \(command.rawValue)")
    }

    // MARK: - Send Set Log (AMA-286)

    /// Send weight log for a set to iPhone
    /// - Parameters:
    ///   - exerciseIndex: Index of the exercise in the workout
    ///   - setNumber: Set number (1-based)
    ///   - weight: Weight used (nil if skipped)
    ///   - unit: Weight unit ("lbs" or "kg")
    func sendSetLog(exerciseIndex: Int, setNumber: Int, weight: Double?, unit: String?) {
        guard let session = session, session.isReachable else {
            print("⌚️ Phone not reachable, cannot send set log")
            lastError = WatchConnectivityBridgeError.phoneNotReachable
            playHaptic(.failure)
            return
        }

        var message: [String: Any] = [
            "action": "logSet",
            "exerciseIndex": exerciseIndex,
            "setNumber": setNumber
        ]

        if let weight = weight {
            message["weight"] = weight
        }
        if let unit = unit {
            message["unit"] = unit
        }

        session.sendMessage(
            message,
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    if reply["status"] as? String == "received" {
                        print("⌚️ Set log acknowledged")
                        self?.playHaptic(.success)
                    }
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    print("⌚️ Failed to send set log: \(error)")
                    self?.lastError = error
                    self?.playHaptic(.failure)
                }
            }
        )

        print("⌚️ Sent set log: exercise=\(exerciseIndex), set=\(setNumber), weight=\(weight ?? 0) \(unit ?? "")")
    }

    // MARK: - Request State

    func requestCurrentState() {
        guard let session = session else {
            print("⌚️ No WCSession available")
            return
        }

        // Always check cached applicationContext first
        let context = session.receivedApplicationContext
        if !context.isEmpty && workoutState == nil {
            print("⌚️ Loading state from applicationContext")
            handleMessage(context)
        }

        // If phone is reachable, request fresh state
        if session.isReachable {
            session.sendMessage(
                ["action": "requestState"],
                replyHandler: { reply in
                    print("⌚️ State request response: \(reply)")
                },
                errorHandler: { error in
                    print("⌚️ Failed to request state: \(error)")
                }
            )
        } else {
            print("⌚️ Phone not reachable, using cached state only")
        }
    }

    // MARK: - Haptic Feedback

    func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    // MARK: - Clear State

    func clearWorkoutState() {
        workoutState = nil
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isSessionActivated = true

            if let error = error {
                print("⌚️ WCSession activation failed: \(error.localizedDescription)")
                self.lastError = error
            } else {
                print("⌚️ WCSession activated on watch: \(activationState.rawValue)")
                self.isPhoneReachable = session.isReachable

                // Check applicationContext for cached state (works even if phone is backgrounded)
                let context = session.receivedApplicationContext
                if !context.isEmpty {
                    print("⌚️ Found cached applicationContext")
                    self.handleMessage(context)
                }

                // Also request fresh state if phone is reachable
                if session.isReachable {
                    self.requestCurrentState()
                }
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            print("⌚️ Received applicationContext update")
            self.handleMessage(applicationContext)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            let reachable = session.isReachable
            print("⌚️ Phone reachability changed: \(reachable)")
            self.isPhoneReachable = reachable

            // Request state when phone becomes reachable
            if reachable {
                self.requestCurrentState()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in
            handleMessage(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            handleMessage(message)
            replyHandler(["status": "received"])
        }
    }

    @MainActor
    private func handleMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }

        switch action {
        case "stateUpdate":
            handleStateUpdate(message)

        case "commandAck":
            handleCommandAck(message)

        case "cleared":
            // applicationContext was cleared (workout is running, state sent via message only)
            // No action needed - this prevents phantom "Open on iPhone" card
            print("⌚️ Received cleared applicationContext (workout running)")

        default:
            print("⌚️ Unknown action: \(action)")
        }
    }

    @MainActor
    private func handleStateUpdate(_ message: [String: Any]) {
        guard let stateDict = message["state"] as? [String: Any] else {
            print("⌚️ Invalid state update message")
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: stateDict)
            let state = try JSONDecoder().decode(WatchWorkoutState.self, from: data)
            let previousPhase = workoutState?.phase
            let previousStepIndex = workoutState?.stepIndex
            let previousVersion = workoutState?.stateVersion ?? 0

            // Explicitly notify SwiftUI observers before updating
            objectWillChange.send()
            workoutState = state

            print("⌚️ STATE UPDATE: version \(previousVersion) → \(state.stateVersion), step \(previousStepIndex ?? -1) → \(state.stepIndex), phase=\(state.phase.rawValue), name='\(state.stepName)'")

            // Log if this is a meaningful change that should trigger view update
            if previousVersion != state.stateVersion || previousStepIndex != state.stepIndex || previousPhase != state.phase {
                print("⌚️ VIEW SHOULD REFRESH: version/step/phase changed")
            }

            // Haptic feedback for phase changes
            // NOTE: We do NOT start HKWorkoutSession here for remote control mode.
            // Starting an HKWorkoutSession on Watch when controlling an iPhone workout
            // causes watchOS to show a phantom "Open on iPhone" card (AMA-223).
            // Health tracking should only happen for standalone workouts via StandaloneWorkoutEngine.
            if previousPhase != state.phase {
                switch state.phase {
                case .running:
                    playHaptic(.start)
                case .paused:
                    playHaptic(.stop)
                case .ended:
                    playHaptic(.success)
                case .idle:
                    break
                case .resting:
                    // Haptic for entering rest phase
                    playHaptic(.stop)
                }
            }

            // Haptic for step changes
            if let prevStep = previousStepIndex, prevStep != state.stepIndex {
                playHaptic(.click)
            }

        } catch {
            print("⌚️ Failed to decode state: \(error)")
        }
    }

    @MainActor
    private func handleCommandAck(_ message: [String: Any]) {
        guard let commandId = message["commandId"] as? String,
              let statusRaw = message["status"] as? String else {
            return
        }

        if commandId == pendingCommandId {
            pendingCommand = nil
            pendingCommandId = nil

            if statusRaw == "success" {
                print("⌚️ Command succeeded")
            } else if let errorCode = message["errorCode"] as? String {
                print("⌚️ Command failed: \(errorCode)")
                playHaptic(.failure)
            }
        }
    }
}

// MARK: - Errors

enum WatchConnectivityBridgeError: LocalizedError {
    case phoneNotReachable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .phoneNotReachable:
            return "iPhone is not reachable"
        case .commandFailed(let reason):
            return "Command failed: \(reason)"
        }
    }
}
