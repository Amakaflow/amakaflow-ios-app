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
        NavigationStack {
            content
                .navigationTitle("Workout Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") {
                            dismiss()
                        }
                    }
                }
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

                // Summary Metrics
                if detail.hasSummaryMetrics {
                    MetricGridView.summary(
                        duration: detail.formattedDuration,
                        calories: detail.formattedCalories,
                        steps: detail.formattedSteps
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

                // Details Section
                detailsSection(detail)

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
        VStack(spacing: 8) {
            Text(detail.workoutName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(detail.formattedDateTime)
                .font(.subheadline)
                .foregroundColor(.secondary)
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

                detailRow(
                    icon: "calendar",
                    label: "Completed",
                    value: detail.formattedFullDate
                )

                if let distance = detail.formattedDistance {
                    detailRow(
                        icon: "map",
                        label: "Distance",
                        value: distance
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
