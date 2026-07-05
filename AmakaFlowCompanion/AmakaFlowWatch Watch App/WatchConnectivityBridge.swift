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

    // AMA-1150: DayState ViewModel for routing push messages
    weak var dayStateViewModel: DayStateViewModel?

    // AMA-297: WorkoutManager for routing phone→watch workout deliveries.
    // Weak to avoid a retain cycle: WatchConnectivityBridge holds WatchWorkoutManager;
    // WatchWorkoutManager does NOT hold the bridge.
    weak var workoutManager: WatchWorkoutManager?

    private(set) var session: WCSession?
    // Track multiple in-flight commands so rapid sends don't clobber each other
    private var pendingCommandIds: Set<String> = []
    private var healthManager = HealthKitWorkoutManager.shared
    private var hrUpdateTimer: Timer?

    // AMA-1150: Per-request callbacks keyed by requestId — prevents a second request
    // from clobbering the first caller's completion (the single-slot bug).
    private typealias DayStatePendingRequest = (callback: (Result<DayState, Error>) -> Void, createdAt: Date)
    private typealias CoachPendingRequest = (callback: (Result<CoachResponse, Error>) -> Void, createdAt: Date)
    private var pendingDayStateCallbacks: [String: DayStatePendingRequest] = [:]
    private var pendingCoachCallbacks: [String: CoachPendingRequest] = [:]
    private static let requestTimeoutSeconds: TimeInterval = 30

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

        // Register for health updates (addHeartRateHandler appends — no single-slot clobber)
        setupHealthKitBindings()
    }

    // MARK: - HealthKit Integration

    private func setupHealthKitBindings() {
        healthManager.addHeartRateHandler { [weak self] hr, calories in
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
            Task { @MainActor [weak self] in
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
        pendingCommandIds.insert(commandId)
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

    // MARK: - DayState Communication (AMA-1150)

    /// Request today's DayState from the phone.
    /// The phone acks immediately to avoid WCSession reply-handler timeout, then
    /// pushes the actual result via a "dayStateResponse" message that includes the
    /// requestId so the correct callback can be resolved.
    func sendDayStateRequest(completion: @escaping (Result<DayState, Error>) -> Void) {
        guard let session = session, session.isReachable else {
            print("⌚️ Phone not reachable, cannot request day state")
            completion(.failure(WatchConnectivityBridgeError.phoneNotReachable))
            return
        }

        let requestId = UUID().uuidString
        pendingDayStateCallbacks[requestId] = (completion, Date())
        scheduleDayStateTimeout(for: requestId)

        session.sendMessage(
            ["action": DayStateAction.requestDayState.rawValue, "requestId": requestId],
            replyHandler: { _ in
                // Phone acked: the real data arrives via dayStateResponse message
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    print("⌚️ Failed to request day state: \(error)")
                    self?.pendingDayStateCallbacks[requestId]?.callback(.failure(error))
                    self?.pendingDayStateCallbacks.removeValue(forKey: requestId)
                }
            }
        )

        print("⌚️ Sent day state request (id=\(requestId))")
    }

    /// Ask the AI coach a question via the phone bridge.
    /// Same ack-fast-then-push pattern as sendDayStateRequest.
    func sendCoachRequest(question: String, completion: @escaping (Result<CoachResponse, Error>) -> Void) {
        guard let session = session, session.isReachable else {
            print("⌚️ Phone not reachable, cannot ask coach")
            completion(.failure(WatchConnectivityBridgeError.phoneNotReachable))
            return
        }

        let requestId = UUID().uuidString
        pendingCoachCallbacks[requestId] = (completion, Date())
        scheduleCoachTimeout(for: requestId)

        session.sendMessage(
            [
                "action": DayStateAction.requestCoachAnswer.rawValue,
                "question": question,
                "requestId": requestId
            ],
            replyHandler: { _ in
                // Phone acked: the real answer arrives via coachResponse message
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    print("⌚️ Failed to send coach request: \(error)")
                    self?.pendingCoachCallbacks[requestId]?.callback(.failure(error))
                    self?.pendingCoachCallbacks.removeValue(forKey: requestId)
                }
            }
        )

        print("⌚️ Sent coach question: \(question) (id=\(requestId))")
    }

    private func scheduleDayStateTimeout(for requestId: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.requestTimeoutSeconds) { [weak self] in
            Task { @MainActor in
                guard let self, let pendingRequest = self.pendingDayStateCallbacks[requestId] else { return }
                let timeoutError = WatchConnectivityBridgeError.commandFailed("Day state request timed out")
                print("⌚️ Day state request timed out (id=\(requestId), age=\(Date().timeIntervalSince(pendingRequest.createdAt))s)")
                pendingRequest.callback(.failure(timeoutError))
                self.pendingDayStateCallbacks.removeValue(forKey: requestId)
            }
        }
    }

    private func scheduleCoachTimeout(for requestId: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.requestTimeoutSeconds) { [weak self] in
            Task { @MainActor in
                guard let self, let pendingRequest = self.pendingCoachCallbacks[requestId] else { return }
                let timeoutError = WatchConnectivityBridgeError.commandFailed("Coach request timed out")
                print("⌚️ Coach request timed out (id=\(requestId), age=\(Date().timeIntervalSince(pendingRequest.createdAt))s)")
                pendingRequest.callback(.failure(timeoutError))
                self.pendingCoachCallbacks.removeValue(forKey: requestId)
            }
        }
    }

    /// Send conflict action (adjust/keep) to the phone
    func sendConflictAction(action: String, message: String) {
        guard let session = session, session.isReachable else {
            print("⌚️ Phone not reachable, cannot send conflict action")
            return
        }

        session.sendMessage(
            [
                "action": DayStateAction.conflictAction.rawValue,
                "conflictAction": action,
                "message": message
            ],
            replyHandler: { reply in
                print("⌚️ Conflict action acknowledged: \(reply)")
            },
            errorHandler: { error in
                print("⌚️ Failed to send conflict action: \(error)")
            }
        )

        print("⌚️ Sent conflict action: \(action)")
    }

    // MARK: - DayState / Coach Response Handling (AMA-1150)

    /// Handles "dayStateResponse" messages pushed from the phone (ack-fast-then-push path).
    /// Resolves the pending callback identified by requestId, then notifies the view model.
    @MainActor
    private func handleDayStatePush(_ message: [String: Any]) {
        let requestId = message["requestId"] as? String

        // Propagate error replies from the phone instead of swallowing them
        if message["status"] as? String == "error" {
            let errorMsg = message["message"] as? String ?? "Request failed"
            let error = WatchConnectivityBridgeError.commandFailed(errorMsg)
            print("⌚️ Day state error from phone: \(errorMsg)")
            if let requestId {
                pendingDayStateCallbacks[requestId]?.callback(.failure(error))
                pendingDayStateCallbacks.removeValue(forKey: requestId)
            }
            return
        }

        guard let dayStateDict = message["dayState"] as? [String: Any] else {
            print("⌚️ Invalid day state push: missing dayState key")
            let error = WatchConnectivityBridgeError.commandFailed("Invalid response")
            if let requestId {
                pendingDayStateCallbacks[requestId]?.callback(.failure(error))
                pendingDayStateCallbacks.removeValue(forKey: requestId)
            }
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: dayStateDict)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let dayState = try decoder.decode(DayState.self, from: data)
            if let requestId {
                pendingDayStateCallbacks[requestId]?.callback(.success(dayState))
                pendingDayStateCallbacks.removeValue(forKey: requestId)
            }
            dayStateViewModel?.handleDayStateUpdate(dayState)
            print("⌚️ Received day state push update")
        } catch {
            print("⌚️ Failed to decode day state push: \(error)")
            if let requestId {
                pendingDayStateCallbacks[requestId]?.callback(.failure(error))
                pendingDayStateCallbacks.removeValue(forKey: requestId)
            }
        }
    }

    /// Handles "coachResponse" messages pushed from the phone (ack-fast-then-push path).
    @MainActor
    private func handleCoachPush(_ message: [String: Any]) {
        let requestId = message["requestId"] as? String

        if message["status"] as? String == "error" {
            let errorMsg = message["message"] as? String ?? "Request failed"
            let error = WatchConnectivityBridgeError.commandFailed(errorMsg)
            print("⌚️ Coach error from phone: \(errorMsg)")
            if let requestId {
                pendingCoachCallbacks[requestId]?.callback(.failure(error))
                pendingCoachCallbacks.removeValue(forKey: requestId)
            }
            return
        }

        guard let answer = message["answer"] as? String,
              let question = message["question"] as? String else {
            print("⌚️ Invalid coach response: missing answer or question key")
            let error = WatchConnectivityBridgeError.commandFailed("Invalid response")
            if let requestId {
                pendingCoachCallbacks[requestId]?.callback(.failure(error))
                pendingCoachCallbacks.removeValue(forKey: requestId)
            }
            return
        }

        let response = CoachResponse(answer: answer, question: question)
        if let requestId {
            pendingCoachCallbacks[requestId]?.callback(.success(response))
            pendingCoachCallbacks.removeValue(forKey: requestId)
        }
        dayStateViewModel?.handleCoachResponse(response)
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

    // AMA-297: Receive background-queued workout syncs sent via transferUserInfo.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard (userInfo["action"] as? String) == "syncWorkouts" else { return }
        Task { @MainActor in
            if let workouts = Workout.decodeFromSyncWorkoutsUserInfo(userInfo) {
                self.workoutManager?.setWorkouts(workouts)
            } else {
                print("⌚️ syncWorkouts userInfo: failed to decode workouts payload")
            }
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
        // AMA-297: Route known actions explicitly; never blanket-ack unknown actions.
        // The only phone→watch message that arrives with a replyHandler is "receiveWorkout".
        Task { @MainActor in
            guard let action = message["action"] as? String else {
                replyHandler(["status": "error", "message": "missing_action"])
                return
            }
            switch action {
            case "receiveWorkout":
                if let workout = Workout.decodeFromReceiveWorkoutMessage(message) {
                    workoutManager?.addWorkout(workout)
                    replyHandler(["status": "received"])
                } else {
                    print("⌚️ receiveWorkout (reply path): failed to decode workout payload")
                    replyHandler(["status": "error", "message": "decode_failed"])
                }
            default:
                // Route through normal message handling for any other known action
                handleMessage(message)
                // Surface unrecognised actions as errors so the phone can detect silent drops.
                replyHandler(["status": "error", "message": "unknown_action"])
            }
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

        // AMA-297: Workout delivery from phone (no-reply path)
        case "receiveWorkout":
            if let workout = Workout.decodeFromReceiveWorkoutMessage(message) {
                workoutManager?.addWorkout(workout)
            } else {
                print("⌚️ receiveWorkout: failed to decode workout payload")
            }

        // AMA-1150: DayState push messages from phone
        case DayStateAction.dayStateResponse.rawValue:
            handleDayStatePush(message)

        case DayStateAction.coachResponse.rawValue:
            handleCoachPush(message)

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

        guard pendingCommandIds.contains(commandId) else { return }
        pendingCommandIds.remove(commandId)
        if pendingCommandIds.isEmpty {
            pendingCommand = nil
        }

        if statusRaw == "success" {
            print("⌚️ Command succeeded")
        } else if let errorCode = message["errorCode"] as? String {
            print("⌚️ Command failed: \(errorCode)")
            playHaptic(.failure)
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
