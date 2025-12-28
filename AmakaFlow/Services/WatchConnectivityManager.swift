//
//  WatchConnectivityManager.swift
//  AmakaFlow
//
//  Manages communication between iPhone and Apple Watch
//

import Foundation
import WatchConnectivity
import Combine

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isWatchAppInstalled = false
    @Published var isWatchReachable = false
    @Published var lastError: Error?

    // Health metrics received from watch
    @Published var watchHeartRate: Double = 0
    @Published var watchActiveCalories: Double = 0
    @Published var lastHealthUpdate: Date?

    // Standalone workout summaries from watch
    @Published var lastStandaloneWorkoutSummary: StandaloneWorkoutSummary?

    private var session: WCSession?

    override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
        }
    }
    
    func activate() {
        session?.activate()
    }
    
    // MARK: - Send Workout to Watch
    @MainActor
    func sendWorkout(_ workout: Workout) async {
        guard let session = session else {
            print("⌚️ WatchConnectivity not supported on this device")
            lastError = WatchConnectivityError.sessionNotAvailable
            return
        }
        
        guard session.activationState == .activated else {
            print("⌚️ WatchConnectivity session not activated. Status: \(session.activationState.rawValue)")
            lastError = WatchConnectivityError.sessionNotAvailable
            return
        }
        
        guard session.isWatchAppInstalled else {
            print("⌚️ Watch app is not installed. Please install the watch app first.")
            lastError = WatchConnectivityError.watchNotReachable
            return
        }
        
        guard session.isReachable else {
            print("⌚️ Watch is not reachable. Make sure your watch is nearby and unlocked.")
            lastError = WatchConnectivityError.watchNotReachable
            return
        }
        
        do {
            // Encode workout to JSON
            let encoder = JSONEncoder()
            let workoutData = try encoder.encode(workout)
            
            guard let workoutDict = try JSONSerialization.jsonObject(with: workoutData) as? [String: Any] else {
                throw WatchConnectivityError.encodingFailed
            }
            
            // Send to watch
            session.sendMessage(
                ["action": "receiveWorkout", "workout": workoutDict],
                replyHandler: { reply in
                    print("⌚️ Watch received workout: \(reply)")
                },
                errorHandler: { error in
                    print("⌚️ Failed to send workout: \(error.localizedDescription)")
                    Task { @MainActor in
                        self.lastError = error
                    }
                }
            )
            
            print("⌚️ Sent workout to watch: \(workout.name)")
        } catch {
            print("⌚️ Failed to encode workout: \(error.localizedDescription)")
            lastError = error
        }
    }
    
    // MARK: - Transfer Large Data (for syncing multiple workouts)
    func transferWorkouts(_ workouts: [Workout]) {
        guard let session = session else { return }

        do {
            let encoder = JSONEncoder()
            let workoutsData = try encoder.encode(workouts)

            guard let workoutsArray = try JSONSerialization.jsonObject(with: workoutsData) as? [[String: Any]] else {
                throw WatchConnectivityError.encodingFailed
            }

            session.transferUserInfo(["action": "syncWorkouts", "workouts": workoutsArray])
            print("⌚️ Transferring \(workouts.count) workouts to watch")
        } catch {
            print("⌚️ Failed to transfer workouts: \(error.localizedDescription)")
            lastError = error
        }
    }

    // MARK: - State Broadcasting (Phone → Watch)

    func sendState(_ state: WorkoutState) {
        guard let session = session else { return }

        do {
            let data = try JSONEncoder().encode(state)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            // Always update applicationContext (persists even when app is backgrounded)
            try? session.updateApplicationContext(["action": "stateUpdate", "state": dict])

            // Also send message if reachable (for immediate updates)
            if session.isReachable {
                session.sendMessage(
                    ["action": "stateUpdate", "state": dict],
                    replyHandler: nil,
                    errorHandler: { error in
                        print("⌚️ Failed to send state message: \(error)")
                    }
                )
            }
        } catch {
            print("⌚️ Failed to encode state: \(error)")
        }
    }

    func sendAck(_ ack: CommandAck) {
        guard let session = session, session.isReachable else { return }

        session.sendMessage(
            [
                "action": "commandAck",
                "commandId": ack.commandId,
                "status": ack.status.rawValue,
                "errorCode": ack.errorCode as Any
            ],
            replyHandler: nil,
            errorHandler: { error in
                print("⌚️ Failed to send ACK: \(error)")
            }
        )
    }
}

    // MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isWatchReachable = session.isReachable
            
            if let error = error {
                print("⌚️ WCSession activation failed: \(error.localizedDescription)")
                self.lastError = error
            } else {
                switch activationState {
                case .activated:
                    print("⌚️ WCSession activated successfully")
                    if !session.isWatchAppInstalled {
                        print("⌚️ Note: Watch app is not installed (this is normal during development)")
                    } else if !session.isPaired {
                        print("⌚️ Note: Watch is not paired (this is normal if using simulator)")
                    }
                case .notActivated:
                    print("⌚️ WCSession not activated")
                case .inactive:
                    print("⌚️ WCSession inactive")
                @unknown default:
                    print("⌚️ WCSession activation state: \(activationState.rawValue)")
                }
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("⌚️ WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("⌚️ WCSession deactivated")
        // Reactivate session
        session.activate()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
            print("⌚️ Watch reachability changed: \(session.isReachable)")
        }
    }
    
    // Receive messages from Watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("⌚️ Received message from watch: \(message)")

        if let action = message["action"] as? String {
            switch action {
            case "requestWorkouts":
                // Watch is requesting workout list
                replyHandler(["status": "workouts_available"])

            case "workoutCompleted":
                // Watch completed a workout
                if let workoutId = message["workoutId"] as? String {
                    print("⌚️ Workout completed on watch: \(workoutId)")
                }
                replyHandler(["status": "acknowledged"])

            case "command":
                // Remote control command from watch
                if let command = message["command"] as? String,
                   let commandId = message["commandId"] as? String {
                    Task { @MainActor in
                        WorkoutEngine.shared.handleRemoteCommand(command, commandId: commandId)
                    }
                    replyHandler(["status": "received"])
                } else {
                    replyHandler(["status": "invalid_command"])
                }

            case "requestState":
                // Watch is requesting current workout state
                Task { @MainActor in
                    let engine = WorkoutEngine.shared
                    if engine.isActive {
                        // Send current state to watch
                        engine.sendStateToWatch()
                        replyHandler(["status": "state_available"])
                    } else {
                        replyHandler(["status": "no_active_workout"])
                    }
                }

            case "healthMetrics":
                // Health metrics from watch (heart rate, calories)
                handleHealthMetrics(message)
                replyHandler(["status": "received"])

            case "workoutSummary":
                // Standalone workout summary from watch
                handleWorkoutSummary(message)
                replyHandler(["status": "received"])

            default:
                replyHandler(["status": "unknown_action"])
            }
        }
    }

    // Also handle messages without reply handler
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let action = message["action"] as? String {
            switch action {
            case "healthMetrics":
                handleHealthMetrics(message)
            case "workoutSummary":
                handleWorkoutSummary(message)
            default:
                break
            }
        }
    }

    private func handleHealthMetrics(_ message: [String: Any]) {
        DispatchQueue.main.async {
            if let hr = message["heartRate"] as? Double {
                self.watchHeartRate = hr
            }
            if let calories = message["activeCalories"] as? Double {
                self.watchActiveCalories = calories
            }
            self.lastHealthUpdate = Date()
            print("❤️ Received from watch - HR: \(Int(self.watchHeartRate)) bpm, Cal: \(Int(self.watchActiveCalories))")
        }
    }

    func clearHealthMetrics() {
        watchHeartRate = 0
        watchActiveCalories = 0
        lastHealthUpdate = nil
    }

    private func handleWorkoutSummary(_ message: [String: Any]) {
        guard let summaryDict = message["summary"] as? [String: Any] else {
            print("⌚️ Invalid workout summary message")
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: summaryDict)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let summary = try decoder.decode(StandaloneWorkoutSummary.self, from: data)

            DispatchQueue.main.async {
                self.lastStandaloneWorkoutSummary = summary
                print("⌚️ Received standalone workout summary: \(summary.workoutName)")
                print("   Duration: \(summary.durationSeconds)s, Calories: \(Int(summary.totalCalories))")
                if let avgHR = summary.averageHeartRate {
                    print("   Avg HR: \(Int(avgHR)) bpm")
                }
            }

            // Post to backend API
            Task { @MainActor in
                do {
                    _ = try await WorkoutCompletionService.shared.postWatchWorkoutCompletion(summary: summary)
                    print("⌚️ Watch workout completion posted to API")
                } catch {
                    print("⌚️ Failed to post watch workout completion: \(error)")
                    // WorkoutCompletionService will queue for retry if network unavailable
                }
            }

        } catch {
            print("⌚️ Failed to decode workout summary: \(error)")
        }
    }
}

// MARK: - Standalone Workout Summary (from Watch)
struct StandaloneWorkoutSummary: Codable {
    let workoutId: String
    let workoutName: String
    let startDate: Date
    let endDate: Date
    let durationSeconds: Int
    let totalCalories: Double
    let averageHeartRate: Double?
    let completedSteps: Int
    let totalSteps: Int
}

// MARK: - Errors
enum WatchConnectivityError: LocalizedError {
    case watchNotReachable
    case encodingFailed
    case sessionNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .watchNotReachable:
            return "Apple Watch is not reachable. Make sure your watch is nearby and the app is open."
        case .encodingFailed:
            return "Failed to encode workout data."
        case .sessionNotAvailable:
            return "Watch connectivity is not available."
        }
    }
}
