//
//  TodayScheduleView.swift
//  AmakaFlowWatch Watch App
//
//  Shows today's DayState: planned sessions, readiness score, next session (AMA-1150)
//  AMA-2420 — experimental Strength Start (freeform always; plan-linked when matched).
//

import SwiftUI

struct TodayScheduleView: View {
    @ObservedObject var viewModel: DayStateViewModel
    @EnvironmentObject var workoutManager: WatchWorkoutManager
    /// Bumps when phone syncs the experimental Strength auto-capture flag so Start re-evaluates.
    @State private var strengthAutoCaptureEpoch = 0

    var body: some View {
        Group {
            if viewModel.isLoading {
                ScrollView {
                    VStack(spacing: 8) {
                        loadingView
                        freeformStartSection
                    }
                    .padding(.horizontal, 4)
                }
            } else if let dayState = viewModel.dayState {
                scheduleContent(dayState)
            } else if let error = viewModel.errorMessage {
                ScrollView {
                    VStack(spacing: 8) {
                        errorView(error)
                        freeformStartSection
                    }
                    .padding(.horizontal, 4)
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        emptyStateView
                        freeformStartSection
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .onAppear {
            viewModel.requestDayState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: WatchStrengthAutoCaptureSettings.didChangeNotification
            )
        ) { _ in
            strengthAutoCaptureEpoch += 1
        }
    }

    // MARK: - Schedule Content

    @ViewBuilder
    private func scheduleContent(_ dayState: DayState) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                readinessPill(score: dayState.readinessScore, label: dayState.readinessLabel)

                // AMA-2420 — Start without calendar / Fitness plan when flag is on.
                freeformStartSection

                if dayState.sessions.isEmpty {
                    noWorkoutsView
                } else {
                    ForEach(dayState.sessions) { session in
                        sessionRow(session)
                    }
                }

                if let conflict = dayState.conflictAlert {
                    conflictBanner(conflict)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Freeform Start (no plan required)

    @ViewBuilder
    private var freeformStartSection: some View {
        // Read epoch so WC flag sync rebuilds this section.
        if WatchStrengthAutoCaptureSettings.isEnabled, strengthAutoCaptureEpoch >= 0 {
            NavigationLink(
                destination: StandaloneWorkoutExecutionView(workout: FreeformStrengthWorkout.make())
            ) {
                Label("Start strength", systemImage: "dumbbell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityIdentifier("af_watch_strength_auto_capture_start")
        }
    }

    // MARK: - Readiness Pill

    private func readinessPill(score: Int, label: ReadinessLabel) -> some View {
        HStack(spacing: 6) {
            Image(systemName: label.systemImage)
                .font(.system(size: 14))
                .foregroundColor(label.color)

            Text("\(score)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(label.color)

            Text(label.displayText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(label.color.opacity(0.15))
        .cornerRadius(16)
        .accessibilityIdentifier("readiness-pill")
    }

    // MARK: - Session Row

    private func sessionRow(_ session: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if session.isNext {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                } else if session.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                } else {
                    Circle()
                        .strokeBorder(Color.gray.opacity(0.4), lineWidth: 1)
                        .frame(width: 6, height: 6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.system(size: 13, weight: session.isNext ? .bold : .medium))
                        .lineLimit(1)
                        .foregroundColor(session.isCompleted ? .secondary : .primary)

                    HStack(spacing: 4) {
                        if let time = session.scheduledTime {
                            Text(time)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        if let duration = session.durationMinutes {
                            Text("\(duration) min")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }

            if let workout = strengthStartWorkout(for: session) {
                NavigationLink(destination: StandaloneWorkoutExecutionView(workout: workout)) {
                    Label("Start planned", systemImage: "list.bullet")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityIdentifier("af_watch_strength_auto_capture_start_plan")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(session.isNext ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .accessibilityIdentifier("session-row-\(session.id)")
    }

    /// AMA-2420 — plan-linked Start when a synced strength workout matches the session.
    private func strengthStartWorkout(for session: PlannedSession) -> Workout? {
        _ = strengthAutoCaptureEpoch
        return StrengthAutoCaptureStart.planLinkedWorkout(
            for: session,
            in: workoutManager.workouts,
            flagEnabled: WatchStrengthAutoCaptureSettings.isEnabled
        )
    }

    // MARK: - Conflict Banner

    private func conflictBanner(_ conflict: ConflictAlert) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(conflict.severity == .critical ? .red : .orange)
                Text("Conflict")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(conflict.severity == .critical ? .red : .orange)
            }

            Text(conflict.message)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .accessibilityIdentifier("conflict-banner")
    }

    // MARK: - Empty / Error / Loading States

    private var noWorkoutsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 28))
                .foregroundColor(.blue.opacity(0.6))

            Text("No workouts today")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("no-workouts-today")
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(.gray)

            Text("No schedule available")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Button("Refresh") {
                viewModel.requestDayState()
            }
            .font(.system(size: 12))
            .buttonStyle(.bordered)
        }
        .accessibilityIdentifier("empty-schedule")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28))
                .foregroundColor(.red)

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                viewModel.requestDayState()
            }
            .font(.system(size: 12))
            .buttonStyle(.bordered)
        }
        .accessibilityIdentifier("schedule-error")
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading schedule...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .accessibilityIdentifier("schedule-loading")
    }
}
