//
//  DDActivityDetailView.swift
//  AmakaFlow
//
//  Completed-activity detail — Daily Driver layout (dd-activity-dark.png).
//

import SwiftUI

struct DDActivityDetailView: View {
    @ObservedObject var viewModel: CompletionDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(completionId: String) {
        _viewModel = ObservedObject(wrappedValue: CompletionDetailViewModel(completionId: completionId))
    }

    init(viewModel: CompletionDetailViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()

            Group {
                if viewModel.isLoading {
                    ProgressView().tint(DailyDriver.lime)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding()
                } else if let detail = viewModel.detail {
                    detailScroll(detail)
                }
            }

            if viewModel.detail != nil, !viewModel.isLoading, showMappingActions {
                DDDualActionBar(
                    primaryTitle: "Map to a workout",
                    secondaryTitle: "Add details manually",
                    primaryAction: { viewModel.showingMapSheet = true },
                    secondaryAction: { viewModel.showingEnrichSheet = true }
                )
            }
        }
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .task { await viewModel.loadDetail() }
        .sheet(isPresented: $viewModel.showingMapSheet) {
            CompletionDiaryMapSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingEnrichSheet) {
            CompletionDiaryEnrichSheet(viewModel: viewModel)
        }
        .accessibilityIdentifier("af_dd_activity_detail")
    }

    private var showMappingActions: Bool {
        guard let detail = viewModel.detail else { return false }
        return detail.workoutId == nil && !viewModel.isVerified
    }

    @ViewBuilder
    private func detailScroll(_ detail: WorkoutCompletionDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backLink
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                header(detail)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                statusBanner(detail)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                DDMetricGrid(tiles: metricTiles(for: detail))
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                if viewModel.hasZoneData {
                    DDHRZonesCard(zones: viewModel.hrZones, note: zoneNote(for: detail))
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                }

                Spacer(minLength: showMappingActions ? 140 : 40)
            }
        }
    }

    private var backLink: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text("Today")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(DailyDriver.foregroundMuted)
        }
        .buttonStyle(.plain)
    }

    private func header(_ detail: WorkoutCompletionDetail) -> some View {
        HStack(spacing: 12) {
            DDIconChip(
                systemName: detail.workoutTypeIconName,
                background: iconBackground(for: detail),
                size: 38
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(detail.workoutName)
                    .ddDisplayText(22, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                Text(metaLine(for: detail))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
        }
    }

    @ViewBuilder
    private func statusBanner(_ detail: WorkoutCompletionDetail) -> some View {
        if viewModel.isVerified || detail.workoutId != nil {
            DDStatusBanner(style: .verified(
                title: "Verified workout",
                body: detail.sourceLabel ?? "Linked to a workout in AmakaFlow"
            ))
        } else if detail.activeCalories != nil && detail.distanceMeters == nil && detail.avgHeartRate == nil {
            DDStatusBanner(style: .amber(
                title: "What was this?",
                body: missingMetricsGuidance(for: detail)
            ))
        } else {
            DDStatusBanner(style: .amber(
                title: "Not linked to a workout yet",
                body: "Map it to the workout it actually was, or add what you did manually."
            ))
        }
    }

    private func missingMetricsGuidance(for detail: WorkoutCompletionDetail) -> String {
        let source = detail.sourceLabel?.lowercased() ?? ""
        if source.contains("strava") {
            return "Strava only sent time and calories. Map it to a workout you know, or add what you did."
        }
        return "Some metrics were missing from the import. Map it to a workout you know, or add what you did."
    }

    private func metricTiles(for detail: WorkoutCompletionDetail) -> [(String, String)] {
        var tiles: [(String, String)] = []
        if let meters = detail.distanceMeters {
            let km = meters >= 1000 ? String(format: "%.1f", Double(meters) / 1000) : "\(meters)"
            tiles.append((km, meters >= 1000 ? "KM" : "M"))
        }
        let minutes = max(1, detail.durationSeconds / 60)
        tiles.append(("\(minutes)", "MIN"))
        if let cal = detail.activeCalories {
            tiles.append(("\(cal)", "CAL"))
        }
        if let hr = detail.avgHeartRate {
            tiles.append(("\(hr)", "AVG BPM"))
        } else {
            tiles.append(("—", "AVG BPM"))
        }
        while tiles.count < 4 {
            tiles.append(("—", "—"))
        }
        return Array(tiles.prefix(4))
    }

    private func metaLine(for detail: WorkoutCompletionDetail) -> String {
        let time = detailTimeRange(detail)
        let kind = detail.workoutTypeLabel.uppercased()
        let source = (detail.sourceLabel ?? "IMPORTED").uppercased()
        return "\(time) · \(kind) · \(source)"
    }

    private func detailTimeRange(_ detail: WorkoutCompletionDetail) -> String {
        let start = detail.startedAt.formatted(date: .omitted, time: .shortened)
        let end = detail.resolvedEndedAt.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private func iconBackground(for detail: WorkoutCompletionDetail) -> Color {
        if detail.workoutName.localizedCaseInsensitiveContains("run") { return DailyDriver.blue }
        if detail.workoutName.localizedCaseInsensitiveContains("hyrox") { return DailyDriver.lime }
        return DailyDriver.card2
    }

    private func zoneNote(for detail: WorkoutCompletionDetail) -> String? {
        let zones = viewModel.hrZones
        guard let peak = zones.max(by: { $0.percentageOfWorkout < $1.percentageOfWorkout }),
              peak.percentageOfWorkout > 0 else { return nil }
        return "Most time in \(peak.name)"
    }
}

private extension WorkoutCompletionDetail {
    var workoutTypeIconName: String {
        if workoutName.localizedCaseInsensitiveContains("run") { return "figure.run" }
        if workoutName.localizedCaseInsensitiveContains("ride") { return "bicycle" }
        if workoutName.localizedCaseInsensitiveContains("swim") { return "figure.pool.swim" }
        return "flame.fill"
    }

    var workoutTypeLabel: String {
        if workoutName.localizedCaseInsensitiveContains("run") { return "Run" }
        if workoutName.localizedCaseInsensitiveContains("hyrox") { return "HIIT" }
        return "Workout"
    }

    var sourceLabel: String? {
        if isSyncedToStrava { return "Imported from Strava" }
        return nil
    }
}
