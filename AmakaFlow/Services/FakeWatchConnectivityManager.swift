//
//  FakeWatchConnectivityManager.swift
//  AmakaFlow
//
//  Mock watch connectivity for UITEST automation
//

import Foundation
import WatchConnectivity

/// Fake watch connectivity manager for UITEST automation
/// Simulates watch interactions without requiring actual watch hardware
class FakeWatchConnectivityManager: NSObject, WatchSessionProviding {
    
    // MARK: - WatchSessionProviding Protocol
    
    var isSupported: Bool { true }
    var isPaired: Bool { true }
    var isWatchAppInstalled: Bool { true }
    var isComplicationEnabled: Bool { true }
    var activationState: WCSessionActivationState { .activated }
    
    private var _delegate: WatchSessionDelegate?
    var delegate: WatchSessionDelegate? {
        get { _delegate }
        set { _delegate = newValue }
    }
    
    // MARK: - Fake State Management
    
    private var fakeWorkoutState: WorkoutEngine.Phase = .idle
    private var fakeHeartRate: Int = 75
    private var fakeWorkoutData: [String: Any] = [:]
    private var fakeCompletionData: [String: Any]?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        print("[FakeWatchConnectivity] Initialized")
        setupFakeState()
    }
    
    private func setupFakeState() {
        // Simulate initial watch state
        fakeWorkoutState = .idle
        fakeHeartRate = 75 + Int.random(in: -10...10)
        
        // Notify delegate that we're "connected"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.delegate?.sessionDidBecomeInactive()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.delegate?.sessionDidActivate()
            }
        }
    }
    
    // MARK: - WatchSessionProviding Methods
    
    func activate() {
        print("[FakeWatchConnectivity] Activating fake watch session")
        // Simulate activation delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.delegate?.sessionDidActivate()
        }
    }
    
    func sendWorkout(_ workout: Workout) {
        print("[FakeWatchConnectivity] Sending fake workout: \(workout.title)")
        fakeWorkoutData = workout.toMessage()
        
        // Simulate watch receiving workout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.delegate?.session(self, didReceiveMessage: ["workout_received": true])
        }
    }
    
    func sendWorkoutPhaseUpdate(_ phase: WorkoutEngine.Phase) {
        print("[FakeWatchConnectivity] Sending fake phase update: \(phase)")
        fakeWorkoutState = phase
        
        let message: [String: Any] = [
            "phase": phase.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        delegate?.session(self, didReceiveMessage: message)
    }
    
    func sendHeartRate(_ heartRate: Int) {
        // Simulate heart rate updates with some variation
        fakeHeartRate = heartRate + Int.random(in: -5...5)
        fakeHeartRate = max(40, min(200, fakeHeartRate)) // Keep in reasonable range
        
        let message: [String: Any] = [
            "heartRate": fakeHeartRate,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        delegate?.session(self, didReceiveMessage: message)
    }
    
    func sendCompletion(_ completion: WorkoutCompletion) {
        print("[FakeWatchConnectivity] Sending fake completion")
        fakeCompletionData = completion.toMessage()
        
        let message: [String: Any] = [
            "completion": completion.toMessage(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        delegate?.session(self, didReceiveMessage: message)
    }
    
    func requestWatchWorkoutState() {
        print("[FakeWatchConnectivity] Requesting fake workout state")
        
        let message: [String: Any] = [
            "workoutState": fakeWorkoutState.rawValue,
            "heartRate": fakeHeartRate,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        delegate?.session(self, didReceiveMessage: message)
    }
    
    func updateContext(_ context: [String: Any]) {
        print("[FakeWatchConnectivity] Updating fake context: \(context)")
        // Store context for later retrieval
        for (key, value) in context {
            fakeWorkoutData[key] = value
        }
    }
    
    func getContext() -> [String: Any] {
        return fakeWorkoutData
    }
    
    // MARK: - Fake Watch Controls (for UITEST)
    
    /// Simulate watch workout start (for UITEST automation)
    func simulateWatchWorkoutStart() {
        fakeWorkoutState = .running
        sendWorkoutPhaseUpdate(.running)
        
        // Start fake heart rate updates
        startFakeHeartRateUpdates()
    }
    
    /// Simulate watch workout pause (for UITEST automation)
    func simulateWatchWorkoutPause() {
        fakeWorkoutState = .paused
        sendWorkoutPhaseUpdate(.paused)
    }
    
    /// Simulate watch workout resume (for UITEST automation)
    func simulateWatchWorkoutResume() {
        fakeWorkoutState = .running
        sendWorkoutPhaseUpdate(.running)
    }
    
    /// Simulate watch workout complete (for UITEST automation)
    func simulateWatchWorkoutComplete() {
        fakeWorkoutState = .complete
        sendWorkoutPhaseUpdate(.complete)
        stopFakeHeartRateUpdates()
    }
    
    // MARK: - Private Helpers
    
    private var heartRateTimer: Timer?
    
    private func startFakeHeartRateUpdates() {
        // Send heart rate updates every 2 seconds during workout
        heartRateTimer?.invalidate()
        heartRateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            // Simulate exercise heart rate increase
            if self.fakeWorkoutState == .running {
                self.fakeHeartRate += Int.random(in: -2...5)
                self.fakeHeartRate = max(60, min(180, self.fakeHeartRate))
                self.sendHeartRate(self.fakeHeartRate)
            }
        }
    }
    
    private func stopFakeHeartRateUpdates() {
        heartRateTimer?.invalidate()
        heartRateTimer = nil
    }
    
    deinit {
        stopFakeHeartRateUpdates()
    }
}

// MARK: - Workout Extension

extension Workout {
    func toMessage() -> [String: Any] {
        return [
            "id": id,
            "title": title,
            "duration": duration,
            "exercises": exercises.map { exercise in
                [
                    "name": exercise.name,
                    "duration": exercise.duration,
                    "type": exercise.type.rawValue
                ]
            }
        ]
    }
}

extension WorkoutCompletion {
    func toMessage() -> [String: Any] {
        return [
            "workoutId": workoutId,
            "duration": duration,
            "calories": calories,
            "heartRate": heartRate,
            "completedAt": ISO8601DateFormatter().string(from: completedAt)
        ]
    }
}