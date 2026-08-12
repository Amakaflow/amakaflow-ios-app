//
//  PassiveStrengthSessionView.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 — passive free-capture UI: metrics + swipe Pause/End/Discard.
//

import SwiftUI

struct PassiveStrengthSessionView: View {
    @StateObject private var engine = PassiveStrengthSessionEngine()
    @Environment(\.dismiss) private var dismiss

    @State private var showCountdown = true
    @State private var didRequestStart = false
    @State private var controlsPage = 0
    @State private var showEndConfirmation = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        Group {
            if showCountdown && engine.phase == .idle {
                WorkoutCountdownView(isPresented: $showCountdown) {
                    Task {
                        guard !didRequestStart else { return }
                        didRequestStart = true
                        await engine.start()
                    }
                }
            } else if engine.phase == .ended {
                completeView
            } else if engine.isActive {
                TabView(selection: $controlsPage) {
                    metricsView
                        .tag(0)
                    controlsPanelView
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else if !showCountdown {
                ProgressView("Starting...")
                    .task {
                        guard !didRequestStart else { return }
                        didRequestStart = true
                        await engine.start()
                    }
            }
        }
        .navigationBarBackButtonHidden(engine.isActive || showCountdown)
        .confirmationDialog(
            "End Workout?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive) {
                Task {
                    await engine.end()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Discard Workout?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                Task {
                    await engine.discard()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: engine.healthCaptureFailed) { _, failed in
            guard failed else { return }
            dismiss()
        }
        .onDisappear {
            // Avoid orphaning an HKWorkoutSession if the view is popped mid-session.
            guard engine.isActive else { return }
            Task { await engine.end() }
        }
    }

    // MARK: - Metrics (main page)

    private var metricsView: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Strength")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(engine.formattedElapsedTime)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(engine.phase == .paused ? .orange : .primary)
                    .accessibilityIdentifier("af_watch_passive_strength_elapsed")

                HStack(spacing: 10) {
                    metricPill(
                        icon: "heart.fill",
                        iconColor: .red,
                        value: engine.heartRate > 0 ? "\(Int(engine.heartRate))" : "--",
                        label: "HR"
                    )
                    metricPill(
                        icon: "flame.fill",
                        iconColor: .orange,
                        value: "\(Int(engine.activeCalories))",
                        label: "Active"
                    )
                    metricPill(
                        icon: "flame",
                        iconColor: .yellow,
                        value: "\(Int(engine.totalCalories))",
                        label: "Total"
                    )
                }

                if engine.phase == .paused {
                    Text("Paused")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                }

                Text("Swipe for controls")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }

    private func metricPill(
        icon: String,
        iconColor: Color,
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Swipe controls

    private var controlsPanelView: some View {
        VStack(spacing: 12) {
            Text("Swipe right to go back")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Button {
                engine.togglePlayPause()
                withAnimation {
                    controlsPage = 0
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: engine.phase == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 28))
                    Text(engine.phase == .paused ? "Resume" : "Pause")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: 100, height: 64)
                .background(engine.phase == .paused ? Color.green : Color.orange)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_watch_passive_strength_pause")

            Button {
                showEndConfirmation = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                    Text("End")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.green)
                .frame(width: 100, height: 52)
                .background(Color.green.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_watch_passive_strength_end")

            Button {
                showDiscardConfirmation = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20))
                    Text("Discard")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.red)
                .frame(width: 100, height: 52)
                .background(Color.red.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_watch_passive_strength_discard")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.95))
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 10) {
            Image(systemName: engine.summaryQueued ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(engine.summaryQueued ? .green : .orange)

            Text(engine.summaryQueued ? "Saved" : "Saved on Watch")
                .font(.title3)
                .fontWeight(.bold)

            Text(engine.formattedElapsedTime)
                .font(.headline)
                .monospacedDigit()

            if engine.activeCalories > 0 || engine.totalCalories > 0 {
                Text("\(Int(engine.activeCalories)) active · \(Int(engine.totalCalories)) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if engine.summaryQueued {
                Text("Fill in on iPhone Today")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("iPhone sync pending — open AmakaFlow nearby")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry sync") {
                    _ = engine.retrySummarySync()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("af_watch_passive_strength_retry_sync")
            }

            Button("Done") {
                engine.reset()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("af_watch_passive_strength_done")
        }
        .padding()
    }
}
