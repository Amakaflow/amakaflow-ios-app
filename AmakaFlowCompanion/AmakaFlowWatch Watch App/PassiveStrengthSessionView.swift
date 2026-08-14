//
//  PassiveStrengthSessionView.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 — passive free-capture UI: metrics + swipe Pause/End/Discard.
//  AMA-2428 — stacked HR/Active metrics + post-end scrollable sport picker.
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
                Text(engine.sessionDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(engine.formattedElapsedTime)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(engine.phase == .paused ? .orange : .primary)
                    .accessibilityIdentifier("af_watch_passive_strength_elapsed")

                VStack(spacing: 6) {
                    metricRow(
                        icon: "heart.fill",
                        iconColor: .red,
                        value: engine.heartRate > 0 ? "\(Int(engine.heartRate))" : "--",
                        label: "HR"
                    )
                    .accessibilityIdentifier("af_watch_passive_strength_hr")

                    metricRow(
                        icon: "flame.fill",
                        iconColor: .orange,
                        value: "\(Int(engine.activeCalories))",
                        label: "Active"
                    )
                    .accessibilityIdentifier("af_watch_passive_strength_active")
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

    private func metricRow(
        icon: String,
        iconColor: Color,
        value: String,
        label: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 22)

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)

            Spacer(minLength: 4)

            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Swipe controls

    private var controlsPanelView: some View {
        VStack(spacing: 12) {
            Text("Swipe right to go back")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            if engine.totalCalories > 0 || engine.activeCalories > 0 {
                Text("\(Int(engine.totalCalories)) total cal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("af_watch_passive_strength_total")
            }

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

    // MARK: - Complete + sport picker

    private var completeView: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)

                Text("Saved")
                    .font(.system(size: 15, weight: .bold))

                Text(engine.formattedElapsedTime)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                if engine.activeCalories > 0 || engine.totalCalories > 0 {
                    Text("\(Int(engine.activeCalories)) active · \(Int(engine.totalCalories)) total")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text("What was this?")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Scroll for more")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    ForEach(WorkoutSport.passiveSessionPickerOptions) { sport in
                        Button {
                            engine.selectSport(sport)
                        } label: {
                            HStack {
                                Text(sport.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                                if engine.selectedSport == sport {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(
                                engine.selectedSport == sport
                                    ? Color.white.opacity(0.16)
                                    : Color.white.opacity(0.06)
                            )
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("af_watch_passive_sport_\(sport.rawValue)")
                    }
                }

                if engine.summaryQueued {
                    Text("Fill in on iPhone Today")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                } else {
                    Text("Tap Done to sync to iPhone")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                Button("Done") {
                    if engine.confirmSportAndSync() {
                        engine.reset()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("af_watch_passive_strength_done")
                .padding(.top, 4)

                if !engine.summaryQueued {
                    Button("Retry sync") {
                        _ = engine.retrySummarySync()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("af_watch_passive_strength_retry_sync")
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }
}
