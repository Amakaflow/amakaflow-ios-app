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

    @Published private(set) var isPhoneReachable = false
    @Published private(set) var workoutState: WatchWorkoutState?
    @Published private(set) var lastError: Error?
    @Published private(set) var pendingCommand: String?

    private var session: WCSession?
    private var pendingCommandId: String?

    private override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
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
            workoutState = state
            print("⌚️ Received state update: \(state.stepName), phase: \(state.phase.rawValue)")

            // Haptic feedback for phase changes
            if let previous = previousPhase, previous != state.phase {
                switch state.phase {
                case .running:
                    playHaptic(.start)
                case .paused:
                    playHaptic(.stop)
                case .ended:
                    playHaptic(.success)
                case .idle:
                    break
                }
            }

            // Haptic for step changes
            if let previousStep = workoutState?.stepIndex,
               previousStep != state.stepIndex {
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
