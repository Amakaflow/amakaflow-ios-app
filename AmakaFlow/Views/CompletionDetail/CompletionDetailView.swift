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
            VStack(spacing: 16) {
                // Header
                headerSection(detail)

                // HR Chart (if data available)
                if viewModel.hasChartData {
                    HRChartView(
                        samples: detail.heartRateSamples ?? [],
                        avgHeartRate: detail.avgHeartRate,
                        maxHeartRate: detail.maxHeartRate,
                        minHeartRate: detail.minHeartRate
                    )
                }

                // Activity Metrics (calories, steps, distance)
                if detail.hasSummaryMetrics || detail.distanceMeters != nil {
                    MetricGridView.activity(
                        calories: detail.formattedCalories,
                        steps: detail.formattedSteps,
                        distance: detail.formattedDistance
                    )
                } else {
                    // Empty state for activity metrics
                    emptyMetricsSection(
                        icon: "figure.run",
                        title: "No Activity Data",
                        message: "Activity metrics like calories, steps, and distance were not recorded for this workout."
                    )
                }

                // Heart Rate Metrics
                if detail.hasHeartRateData {
                    MetricGridView.heartRate(
                        avg: detail.avgHeartRate,
                        max: detail.maxHeartRate,
                        min: detail.minHeartRate
                    )
                }

                // HR Zones (if data available)
                if viewModel.hasZoneData {
                    HRZonesView(zones: viewModel.hrZones)
                }

                // Workout Steps (AMA-224)
                if detail.hasWorkoutSteps {
                    WorkoutStepsSection(steps: detail.flattenedSteps)
                }

                // Details Section
                detailsSection(detail)

                // Save to Library Button (for voice-added workouts)
                if viewModel.canSaveToLibrary {
                    saveToLibraryButton
                }

                // Run Again Button (AMA-237)
                if viewModel.canRerun {
                    runAgainButton
                }

                // Strava Button
                stravaButton

                Spacer(minLength: 20)
            }
            .padding()
        }
        .background(Theme.Colors.background)
    }

    // MARK: - Header Section

    private func headerSection(_ detail: WorkoutCompletionDetail) -> some View {
        VStack(spacing: 12) {
            // Workout name
            Text(detail.workoutName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // Date
            Text(detail.formattedFullDate)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Prominent duration display
            VStack(spacing: 4) {
                Text(detail.formattedDuration)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)

            // Time range (start → end)
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Text(detail.formattedStartTime)
                    .foregroundColor(.secondary)

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.caption2)

                Text(detail.resolvedEndedAt.formatted(date: .omitted, time: .shortened))
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
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
