//
//  WatchRemoteView.swift
//  AmakaFlowWatch Watch App
//
//  Remote control view for controlling iPhone workout
//

import SwiftUI

struct WatchRemoteView: View {
    @ObservedObject var bridge: WatchConnectivityBridge
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let state = bridge.workoutState, state.isActive {
                activeWorkoutView(state: state)
            } else if !bridge.isPhoneReachable {
                disconnectedView
            } else {
                idleView
            }
        }
        .onAppear {
            bridge.requestCurrentState()
        }
    }

    // MARK: - Active Workout View

    @ViewBuilder
    private func activeWorkoutView(state: WatchWorkoutState) -> some View {
        VStack(spacing: 8) {
            // Workout name
            Text(state.workoutName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            // Step name
            Text(state.stepName)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Timer or step info
            if state.isTimedStep {
                Text(state.formattedTime)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(state.isPaused ? .orange : .primary)
            }

            // Round info
            if let roundInfo = state.roundInfo {
                Text(roundInfo)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Progress
            ProgressView(value: state.progress)
                .tint(.blue)
                .padding(.horizontal, 8)

            Text("\(state.stepIndex + 1) of \(state.stepCount)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer(minLength: 4)

            // Controls
            controlsView(state: state)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Controls

    @ViewBuilder
    private func controlsView(state: WatchWorkoutState) -> some View {
        VStack(spacing: 8) {
            // Play/Pause + Navigation Row
            HStack(spacing: 12) {
                // Previous
                Button {
                    bridge.sendCommand(.previousStep)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(state.stepIndex == 0)

                // Play/Pause
                Button {
                    if state.isPaused {
                        bridge.sendCommand(.resume)
                    } else {
                        bridge.sendCommand(.pause)
                    }
                } label: {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(state.isPaused ? Color.green : Color.orange)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Next
                Button {
                    bridge.sendCommand(.nextStep)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(state.stepIndex >= state.stepCount - 1)
            }

            // End button
            Button {
                bridge.sendCommand(.end)
            } label: {
                Text("End")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
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

            Button("Retry") {
                bridge.requestCurrentState()
            }
            .buttonStyle(.bordered)
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

            Button("Refresh") {
                bridge.requestCurrentState()
            }
            .buttonStyle(.bordered)
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
