//
//  WatchRemoteView.swift
//  AmakaFlowWatch Watch App
//
//  Remote control view for controlling iPhone workout
//

import SwiftUI
import Combine

// MARK: - Demo Mode State
class DemoModeState: ObservableObject {
    static let shared = DemoModeState()

    @Published var isEnabled = false
    @Published var currentScreen = 0

    let totalScreens = 5

    // Demo screen types: 0=idle, 1=rep-based with weight, 2=timed, 3=paused, 4=complete
    var demoWorkoutState: WatchWorkoutState? {
        guard isEnabled else { return nil }

        switch currentScreen {
        case 1: // Rep-based step with weight input (AMA-286 demo)
            return WorkoutState(
                stateVersion: 1,
                workoutId: "demo-1",
                workoutName: "Demo Workout",
                phase: .running,
                stepIndex: 1,
                stepCount: 7,
                stepName: "Bench Press",
                stepType: .reps,
                remainingMs: nil,
                roundInfo: nil,
                targetReps: 10,
                lastCommandAck: nil,
                setNumber: 2,
                totalSets: 4,
                suggestedWeight: 135,
                weightUnit: "lbs"
            )
        case 2: // Timed step (Warm Up)
            return WorkoutState(
                stateVersion: 1,
                workoutId: "demo-1",
                workoutName: "Demo Workout",
                phase: .running,
                stepIndex: 0,
                stepCount: 7,
                stepName: "Warm Up",
                stepType: .timed,
                remainingMs: 295000, // 4:55
                roundInfo: nil,
                lastCommandAck: nil
            )
        case 3: // Paused state
            return WorkoutState(
                stateVersion: 1,
                workoutId: "demo-1",
                workoutName: "Demo Workout",
                phase: .paused,
                stepIndex: 1,
                stepCount: 7,
                stepName: "Bench Press",
                stepType: .reps,
                remainingMs: nil,
                roundInfo: nil,
                lastCommandAck: nil,
                setNumber: 2,
                totalSets: 4,
                suggestedWeight: 135,
                weightUnit: "lbs"
            )
        case 4: // Complete
            return WorkoutState(
                stateVersion: 1,
                workoutId: "demo-1",
                workoutName: "Demo Workout",
                phase: .ended,
                stepIndex: 6,
                stepCount: 7,
                stepName: "Cool Down",
                stepType: .reps,
                remainingMs: nil,
                roundInfo: nil,
                lastCommandAck: nil
            )
        default: // 0 = idle
            return nil
        }
    }

    func toggle() {
        isEnabled.toggle()
        if isEnabled {
            currentScreen = 0
        }
    }

    func nextScreen() {
        currentScreen = (currentScreen + 1) % totalScreens
    }
}

struct WatchRemoteView: View {
    @ObservedObject var bridge: WatchConnectivityBridge
    @StateObject private var demoState = DemoModeState.shared
    @Environment(\.dismiss) private var dismiss

    // Timeout for loading state - after 5 seconds, show disconnected view
    @State private var loadingTimedOut = false
    @State private var controlsPage: Int = 0

    // Computed state that uses demo state when in demo mode
    private var displayState: WatchWorkoutState? {
        if demoState.isEnabled {
            return demoState.demoWorkoutState
        }
        return bridge.workoutState
    }

    private var showComplete: Bool {
        demoState.isEnabled && demoState.currentScreen == 4
    }

    @ViewBuilder
    private var content: some View {
        if !bridge.isSessionActivated && !demoState.isEnabled && !loadingTimedOut {
            // Show loading while WCSession is activating (with timeout)
            loadingView
        } else if showComplete {
            completeView
        } else if let state = displayState, state.isResting {
            // Wrap rest view in horizontal pager
            TabView(selection: $controlsPage) {
                restView(state: state)
                    .tag(0)
                controlsPanelView(state: state)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .id("rest-\(state.stepIndex)-\(state.stateVersion)")
        } else if let state = displayState, state.isActive {
            // Wrap active view in horizontal pager
            TabView(selection: $controlsPage) {
                activeWorkoutView(state: state)
                    .tag(0)
                controlsPanelView(state: state)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .id("active-\(state.stepIndex)-\(state.stateVersion)")
        } else if !demoState.isEnabled && !bridge.isPhoneReachable && bridge.workoutState == nil {
            disconnectedView
        } else {
            idleView
        }
    }

    var body: some View {
        content
            .id("remote-\(bridge.workoutState?.stateVersion ?? 0)-\(bridge.workoutState?.stepIndex ?? -1)")
            .onChange(of: bridge.workoutState?.stateVersion) { oldVersion, newVersion in
                print("⌚️ VIEW: stateVersion changed \(oldVersion ?? 0) → \(newVersion ?? 0), stepIndex=\(bridge.workoutState?.stepIndex ?? -1)")
            }
            .onChange(of: bridge.workoutState?.stepIndex) { oldStep, newStep in
                print("⌚️ VIEW: stepIndex changed \(oldStep ?? -1) → \(newStep ?? -1)")
            }
            .onChange(of: bridge.isSessionActivated) { _, activated in
                print("⌚️ VIEW: isSessionActivated changed to \(activated)")
            }
            .onChange(of: bridge.isPhoneReachable) { _, reachable in
                print("⌚️ VIEW: isPhoneReachable changed to \(reachable)")
            }
            .overlay(alignment: .bottom) {
            // Demo mode controls at bottom
            if demoState.isEnabled {
                HStack(spacing: 20) {
                    Button {
                        demoState.nextScreen()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.yellow)

                    Text("DEMO \(demoState.currentScreen + 1)/\(demoState.totalScreens)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.yellow)

                    Button {
                        withAnimation {
                            demoState.toggle()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .padding(.bottom, 4)
            }
        }
        .onAppear {
            print("⌚️ VIEW onAppear: isSessionActivated=\(bridge.isSessionActivated), isPhoneReachable=\(bridge.isPhoneReachable), workoutState=\(bridge.workoutState != nil ? "exists" : "nil")")
            if !demoState.isEnabled {
                bridge.requestCurrentState()
            }

            // Set a timeout for loading state - if session doesn't activate in 5 seconds, proceed anyway
            if !bridge.isSessionActivated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if !bridge.isSessionActivated {
                        print("⌚️ VIEW: Loading timeout - session not activated after 5s")
                        loadingTimedOut = true
                    }
                }
            }
        }
    }

    // MARK: - Active Workout View

    @ViewBuilder
    private func activeWorkoutView(state: WatchWorkoutState) -> some View {
        // AMA-286: Show weight input for reps steps with set information
        if state.stepType == .reps, let setNumber = state.setNumber, let totalSets = state.totalSets {
            weightInputView(state: state, setNumber: setNumber, totalSets: totalSets)
        } else {
            standardWorkoutView(state: state)
        }
    }

    // MARK: - Weight Input View (AMA-286)

    @ViewBuilder
    private func weightInputView(state: WatchWorkoutState, setNumber: Int, totalSets: Int) -> some View {
        WeightInputWatchView(
            exerciseName: state.stepName,
            setNumber: setNumber,
            totalSets: totalSets,
            suggestedWeight: state.suggestedWeight,
            weightUnit: state.weightUnit ?? "lbs",
            onLogSet: { weight, unit in
                // Send set log to iPhone and advance to next step
                bridge.sendSetLog(
                    exerciseIndex: state.stepIndex,
                    setNumber: setNumber,
                    weight: weight,
                    unit: unit
                )
            },
            onSkipWeight: {
                // Skip weight (log nil) and advance
                bridge.sendSetLog(
                    exerciseIndex: state.stepIndex,
                    setNumber: setNumber,
                    weight: nil,
                    unit: nil
                )
            }
        )
    }

    // MARK: - Standard Workout View (non-weight steps)

    @ViewBuilder
    private func standardWorkoutView(state: WatchWorkoutState) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                // Connection warning if phone not reachable (compact)
                if !bridge.isPhoneReachable {
                    HStack(spacing: 2) {
                        Image(systemName: "iphone.slash")
                        Text("Open iPhone app")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                }

                // Heart Rate Display (when available)
                if bridge.heartRate > 0 || demoState.isEnabled {
                    heartRateView
                }

                // Step name (primary focus)
                Text(state.stepName)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                // Timer (large and prominent) for timed steps
                if state.isTimedStep {
                    Text(state.formattedTime)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(state.isPaused ? .orange : .primary)
                } else if let reps = state.targetReps, reps > 0 {
                    // Reps display for rep-based steps (without set tracking)
                    Text("\(reps) reps")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }

                // Progress and step count inline
                HStack {
                    ProgressView(value: state.progress)
                        .tint(.blue)
                    Text("\(state.stepIndex + 1)/\(state.stepCount)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)

                // Round info (if available)
                if let roundInfo = state.roundInfo {
                    Text(roundInfo)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Controls - always visible
                controlsView(state: state)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Rest View

    @ViewBuilder
    private func restView(state: WatchWorkoutState) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                // Rest title
                Text("Rest")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.blue)

                // Manual rest message
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                    Text("Tap when ready")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                // Progress
                HStack {
                    ProgressView(value: state.progress)
                        .tint(.blue)
                    Text("\(state.stepIndex + 1)/\(state.stepCount)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)

                // Continue button
                Button {
                    bridge.sendCommand(.skipRest)
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Continue")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Heart Rate View

    private var heartRateView: some View {
        HStack(spacing: 8) {
            // Heart rate
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                Text(demoState.isEnabled ? "142" : "\(Int(bridge.heartRate))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            // Calories (if available)
            if bridge.activeCalories > 0 || demoState.isEnabled {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text(demoState.isEnabled ? "87" : "\(Int(bridge.activeCalories))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Controls (Simplified - just navigation)

    @ViewBuilder
    private func controlsView(state: WatchWorkoutState) -> some View {
        HStack(spacing: 20) {
            // Previous (smaller)
            Button {
                bridge.sendCommand(.previousStep)
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
                    .foregroundColor(state.stepIndex == 0 ? .gray : .primary)
            }
            .buttonStyle(.plain)
            .disabled(state.stepIndex == 0)

            // Next (prominent - primary action)
            Button {
                bridge.sendCommand(.nextStep)
            } label: {
                Image(systemName: state.stepIndex >= state.stepCount - 1 ? "checkmark" : "forward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(state.stepIndex >= state.stepCount - 1 ? Color.green : Color.blue)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Controls Panel (swipe-left to reveal)

    @ViewBuilder
    private func controlsPanelView(state: WatchWorkoutState) -> some View {
        VStack(spacing: 16) {
            // Swipe hint
            Text("Swipe right to go back")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Pause/Resume button
            Button {
                if state.isPaused {
                    bridge.sendCommand(.resume)
                } else {
                    bridge.sendCommand(.pause)
                }
                // Return to main view after action
                withAnimation {
                    controlsPage = 0
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 32))
                    Text(state.isPaused ? "Resume" : "Pause")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: 100, height: 70)
                .background(state.isPaused ? Color.green : Color.orange)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)

            // End Workout button
            Button {
                bridge.sendCommand(.end)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                    Text("End Workout")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.red)
                .frame(width: 100, height: 56)
                .background(Color.red.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.95))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Disconnected View

    private var disconnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.slash")
                .font(.largeTitle)
                .foregroundColor(.gray)

            Text("iPhone Not Connected")
                .font(.headline)

            Text("Make sure the AmakaFlow app is open on your iPhone")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Retry") {
                    bridge.requestCurrentState()
                }
                .buttonStyle(.bordered)

                Button("Demo") {
                    withAnimation {
                        demoState.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .tint(.yellow)
            }
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
                .foregroundColor(.blue)

            Text("No Active Workout")
                .font(.headline)

            Text("Start a workout on your iPhone to control it from here")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Refresh") {
                    bridge.requestCurrentState()
                }
                .buttonStyle(.bordered)

                Button("Demo") {
                    withAnimation {
                        demoState.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .tint(.yellow)
            }
        }
    }

    // MARK: - Complete View (Demo mode only)

    private var completeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)

            Text("Complete!")
                .font(.title2)
                .fontWeight(.bold)

            Text("Cool Down")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Great workout!")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Compact Remote View (for Now Playing style)

struct CompactRemoteView: View {
    @ObservedObject var bridge: WatchConnectivityBridge

    var body: some View {
        if let state = bridge.workoutState, state.isActive {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.stepName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if state.isTimedStep {
                        Text(state.formattedTime)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundColor(state.isPaused ? .orange : .secondary)
                    }
                }

                Spacer()

                Button {
                    if state.isPaused {
                        bridge.sendCommand(.resume)
                    } else {
                        bridge.sendCommand(.pause)
                    }
                } label: {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
    }
}

#Preview("Active Workout") {
    let bridge = WatchConnectivityBridge.shared
    return WatchRemoteView(bridge: bridge)
}

#Preview("Disconnected") {
    let bridge = WatchConnectivityBridge.shared
    return WatchRemoteView(bridge: bridge)
}
