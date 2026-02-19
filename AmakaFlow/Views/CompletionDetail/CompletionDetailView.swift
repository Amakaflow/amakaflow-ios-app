//
//  CompletionDetailView.swift
//  AmakaFlow
//
//  Detailed view of a single workout completion with HR chart and metrics
//

import SwiftUI

struct CompletionDetailView: View {
    @StateObject private var viewModel: CompletionDetailViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(completionId: String) {
        _viewModel = StateObject(wrappedValue: CompletionDetailViewModel(completionId: completionId))
    }

    // MARK: - Body

    var body: some View {
        content
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadDetail()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .overlay {
                if viewModel.showStravaToast {
                    stravaToast
                }
                if viewModel.showSaveToast {
                    saveToast
                }
            }
            // Run Again fullScreenCover - placed here (not on button) to prevent @State reset
            // when view hierarchy changes during workout playback (AMA-240 fix)
            .fullScreenCover(isPresented: $viewModel.showWorkoutPlayer) {
                WorkoutPlayerView()
                    .onDisappear {
                        // Clear the workout reference when player is dismissed
                        viewModel.workoutToRerun = nil
                    }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingView
        } else if let errorMessage = viewModel.errorMessage {
            errorView(errorMessage)
        } else if let detail = viewModel.detail {
            detailScrollView(detail)
        } else {
            emptyView
        }
    }

    // MARK: - Detail Content

    private func detailScrollView(_ detail: WorkoutCompletionDetail) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header with completion badge and stats (AMA-292)
                headerSection(detail)

                // Heart Rate Chart Section (compact design matching target)
                heartRateSection(detail)

                // Activity metrics (AMA-275)
                if detail.hasSummaryMetrics {
                    activitySection(detail)
                }

                // Execution Log (AMA-292) - shows actual workout execution with weights
                // Always show ExecutionLogSection - uses mock data if no real execution log
                ExecutionLogSection(
                    intervals: detail.hasExecutionLog ? detail.executionIntervals : ExecutionLogSection.sampleIntervals,
                    summary: detail.hasExecutionLog ? detail.executionSummary : ExecutionLogSection.sampleSummary
                )

                // Source and Strava info
                sourceInfoSection(detail)

                // Save to Library Button (for voice-added workouts)
                if viewModel.canSaveToLibrary {
                    saveToLibraryButton
                }

                // Run Again Button (AMA-237)
                if viewModel.canRerun {
                    runAgainButton
                }

                // Sync to Strava Button (AMA-275)
                stravaButton

                // Edit Workout Button
                editWorkoutButton

                // Done Button (AMA-275)
                doneButton

                Spacer(minLength: 20)
            }
            .padding()
        }
        .background(Theme.Colors.background)
    }

    // MARK: - Heart Rate Section (Compact design)

    private func heartRateSection(_ detail: WorkoutCompletionDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: HEART RATE + stats
            HStack {
                Text("HEART RATE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                if let avg = detail.avgHeartRate {
                    Text("\(avg)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("avg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let max = detail.maxHeartRate {
                    Text("\(max)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.leading, 8)
                    Text("max")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Chart (if data available)
            if viewModel.hasChartData {
                HRChartView(
                    samples: detail.heartRateSamples ?? [],
                    avgHeartRate: detail.avgHeartRate,
                    maxHeartRate: detail.maxHeartRate,
                    minHeartRate: detail.minHeartRate
                )
                .frame(height: 80)
            } else {
                // Placeholder chart area
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.1))
                    .frame(height: 60)
                    .overlay(
                        Text("No heart rate data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
            }
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Activity Section

    private func activitySection(_ detail: WorkoutCompletionDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVITY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            HStack(spacing: 0) {
                statItem(value: detail.formattedCalories ?? "—", label: "CAL", color: .primary)
                Spacer()
                statItem(value: detail.formattedSteps ?? "—", label: "STEPS", color: .primary)
                Spacer()
                statItem(value: detail.formattedDistance ?? "—", label: "DIST", color: .primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
        .accessibilityIdentifier("activity_section")
    }

    // MARK: - Source Info Section

    private func sourceInfoSection(_ detail: WorkoutCompletionDetail) -> some View {
        VStack(spacing: 12) {
            // Source row
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .foregroundColor(.secondary)
                Text("Source")
                    .foregroundColor(.secondary)
                Spacer()
                Text(detail.source.displayName)
                    .foregroundColor(.primary)
            }
            .font(.subheadline)

            // Strava row
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                Text("Strava")
                    .foregroundColor(.secondary)
                Spacer()
                if detail.isSyncedToStrava {
                    Text("Synced")
                        .foregroundColor(.green)
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Text("Not synced")
                        .foregroundColor(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Edit Workout Button

    private var editWorkoutButton: some View {
        Button(action: {
            // TODO: Implement edit workout
        }) {
            HStack {
                Image(systemName: "pencil")
                Text("Edit Workout")
            }
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.Colors.surface)
            .cornerRadius(12)
        }
    }

    // MARK: - Header Section (Updated to match target design AMA-292)

    private func headerSection(_ detail: WorkoutCompletionDetail) -> some View {
        // Get execution summary (use mock if no real data)
        let summary = detail.hasExecutionLog ? detail.executionSummary : ExecutionLogSection.sampleSummary
        let completionPct = Int(summary?.completionPercentage ?? 100)
        let totalSets = summary?.totalSets ?? 0
        let skippedSets = summary?.setsSkipped ?? 0

        return VStack(spacing: 12) {
            // Top row: Name + Completion Badge
            HStack(alignment: .top) {
                // Left: Name and date
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.workoutName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text(detail.formattedFullDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Right: Completion percentage badge
                completionBadge(percentage: completionPct)
            }

            // Large duration display
            HStack {
                Text(detail.formattedDuration)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }

            // Time range
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Text("\(detail.formattedStartTime) → \(detail.resolvedEndedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            // Stats row: SETS, SKIPPED, CAL, AVG HR
            HStack(spacing: 0) {
                statItem(value: "\(totalSets)", label: "SETS", color: Theme.Colors.accentGreen)
                Spacer()
                statItem(value: "\(skippedSets)", label: "SKIPPED", color: .orange)
                Spacer()
                statItem(value: detail.formattedCalories ?? "—", label: "CAL", color: .primary)
                Spacer()
                statItem(value: detail.avgHeartRate.map { "\($0)" } ?? "—", label: "AVG HR", color: .primary)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Completion Badge

    private func completionBadge(percentage: Int) -> some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                .frame(width: 56, height: 56)

            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat(percentage) / 100)
                .stroke(
                    percentage >= 75 ? Color.green : (percentage >= 50 ? Color.orange : Color.red),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))

            // Percentage text
            VStack(spacing: 0) {
                Text("\(percentage)%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(percentage >= 75 ? .green : (percentage >= 50 ? .orange : .red))
                Text("COMPLETE")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Stat Item

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 50)
    }

    // MARK: - Empty Metrics Section

    private func emptyMetricsSection(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Details Section

    private func detailsSection(_ detail: WorkoutCompletionDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                detailRow(
                    icon: detail.source.iconName,
                    label: "Source",
                    value: detail.deviceInfo?.displayName ?? detail.source.displayName
                )

                if detail.isSyncedToStrava {
                    detailRow(
                        icon: "checkmark.circle.fill",
                        label: "Strava",
                        value: "Synced",
                        valueColor: .green
                    )
                }
            }
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    private func detailRow(icon: String, label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .foregroundColor(valueColor)
        }
        .font(.subheadline)
    }

    // MARK: - Run Again Button (AMA-237)

    private var runAgainButton: some View {
        Button {
            viewModel.rerunWorkout()
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("Run Again")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.Colors.accentGreen)
            .cornerRadius(12)
        }
        // Note: fullScreenCover moved to main body to prevent @State reset when view hierarchy changes
    }

    // MARK: - Save to Library Button

    private var saveToLibraryButton: some View {
        Button {
            Task {
                await viewModel.saveToLibrary()
            }
        } label: {
            HStack {
                if viewModel.isSavingToLibrary {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                }
                Text(viewModel.isSavingToLibrary ? "Saving..." : "Save to My Workouts")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.Colors.accentBlue)
            .cornerRadius(12)
        }
        .disabled(viewModel.isSavingToLibrary)
    }

    // MARK: - Strava Button

    private var stravaButton: some View {
        Button {
            Task {
                await viewModel.syncToStrava()
            }
        } label: {
            HStack {
                Image(systemName: viewModel.canSyncToStrava ? "arrow.up.circle" : "link")
                Text(viewModel.stravaButtonText)
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.orange)
            .cornerRadius(12)
        }
        .disabled(!viewModel.canSyncToStrava)
        .accessibilityIdentifier("strava_button")
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button("Done") {
            dismiss()
        }
        .font(.headline)
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
        .accessibilityIdentifier("completion_done_button")
    }

    // MARK: - Strava Toast

    private var stravaToast: some View {
        VStack {
            Spacer()

            Text(viewModel.stravaToastMessage)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .padding(.bottom, 50)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut, value: viewModel.showStravaToast)
    }

    // MARK: - Save Toast

    private var saveToast: some View {
        VStack {
            Spacer()

            HStack {
                Image(systemName: viewModel.saveToastMessage.contains("Failed") ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(viewModel.saveToastMessage.contains("Failed") ? .red : .green)
                Text(viewModel.saveToastMessage)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            .padding(.bottom, 50)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut, value: viewModel.showSaveToast)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading workout details...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task {
                    await viewModel.loadDetail()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("Workout not found")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}

// MARK: - Preview

#Preview {
    CompletionDetailView(completionId: "sample-id")
}
