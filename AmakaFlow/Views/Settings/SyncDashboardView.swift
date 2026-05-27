//
//  SyncDashboardView.swift
//  AmakaFlow
//
//  Sync dashboard showing integration health, platform status, and pending decisions (AMA-1133)
//

import SwiftUI

struct SyncDashboardView: View {
    @EnvironmentObject var workoutsViewModel: WorkoutsViewModel
    @StateObject private var activityFeedVM = ActivityFeedViewModel()
    @State private var lastSyncTime: Date?
    @State private var syncQueueSummary = SyncQueueSummary(pendingCount: 0, inFlightCount: 0, failedCount: 0, poisonCount: 0, lastAttemptedAt: nil, latestError: nil)

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Overall sync status
                overallStatusCard

                // Platform status bars
                platformStatusSection

                // Local sync queue state
                syncQueueSection

                // Pending decisions
                pendingDecisionsSection

                // Recent activity
                recentActivitySection
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Sync Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refresh()
        }
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        await activityFeedVM.loadActions()
        do {
            syncQueueSummary = try SyncQueueRepository().summary()
        } catch {
            DebugLogService.shared.log("Sync dashboard queue summary failed", details: error.localizedDescription)
        }
        lastSyncTime = Date()
    }

    // MARK: - Overall Status

    private var overallStatusCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: hasPendingIssues ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(hasPendingIssues ? Theme.Colors.accentOrange : Theme.Colors.accentGreen)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(hasPendingIssues ? "Attention Needed" : "All Systems Healthy")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    if let syncTime = lastSyncTime {
                        Text("Last checked: \(syncTime, style: .relative)")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Spacer()
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(hasPendingIssues ? Theme.Colors.accentOrange.opacity(0.3) : Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    private var hasPendingIssues: Bool {
        activityFeedVM.actions.contains { $0.status == .pending }
            || syncQueueSummary.failedCount > 0
            || syncQueueSummary.poisonCount > 0
            || syncQueueSummary.latestError != nil
    }

    // MARK: - Platform Status

    private var platformStatusSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Integrations")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            // Apple Health
            PlatformStatusBar(
                name: "Apple Health",
                icon: "heart.fill",
                iconColor: Theme.Colors.accentRed,
                status: .connected,
                detail: "Syncing workouts and activity"
            )

            // Apple Watch
            PlatformStatusBar(
                name: "Apple Watch",
                icon: "applewatch",
                iconColor: Theme.Colors.accentBlue,
                status: WatchConnectivityManager.shared.isWatchReachable ? .connected : .disconnected,
                detail: WatchConnectivityManager.shared.isWatchReachable ? "Connected and syncing" : "Not reachable"
            )

            // AmakaFlow Backend
            PlatformStatusBar(
                name: "AmakaFlow Cloud",
                icon: "cloud.fill",
                iconColor: Theme.Colors.accentBlue,
                status: workoutsViewModel.errorMessage == nil ? .connected : .error,
                detail: workoutsViewModel.errorMessage ?? "Synced"
            )
        }
    }

    // MARK: - Local Sync Queue

    private var syncQueueSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Local Sync Queue")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                SyncQueueMetricRow(label: "Pending", value: syncQueueSummary.pendingCount, color: Theme.Colors.accentBlue)
                SyncQueueMetricRow(label: "In Flight", value: syncQueueSummary.inFlightCount, color: Theme.Colors.accentOrange)
                SyncQueueMetricRow(label: "Failed", value: syncQueueSummary.failedCount, color: Theme.Colors.accentRed)
                SyncQueueMetricRow(label: "Poison", value: syncQueueSummary.poisonCount, color: Theme.Colors.accentRed)

                if let lastAttemptedAt = syncQueueSummary.lastAttemptedAt {
                    HStack {
                        Text("Last attempt")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Text(lastAttemptedAt, style: .relative)
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                if let latestError = syncQueueSummary.latestError {
                    Text(latestError)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.accentRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)
        }
    }

    // MARK: - Pending Decisions

    private var pendingDecisionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Pending Decisions")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                let pendingCount = activityFeedVM.actions.filter { $0.decisionRequired || $0.status == .pending }.count
                if pendingCount > 0 {
                    Text("\(pendingCount)")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Theme.Colors.accentOrange)
                        .cornerRadius(12)
                }
            }

            let needsDecisionActions = activityFeedVM.actions.filter { $0.decisionRequired || $0.status == .pending }
            if needsDecisionActions.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(Theme.Colors.accentGreen)
                    Text("No pending decisions")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.md)
            } else {
                ForEach(needsDecisionActions) { action in
                    PendingDecisionCard(action: action) {
                        Task { await activityFeedVM.approveAction(action) }
                    } onReject: {
                        Task { await activityFeedVM.rejectAction(action) }
                    }
                }
            }
        }
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recent Activity")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            let resolvedActions = activityFeedVM.actions.filter { $0.status != .pending }.prefix(5)
            if resolvedActions.isEmpty {
                Text("No recent activity")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.md)
            } else {
                ForEach(Array(resolvedActions)) { action in
                    HStack(spacing: Theme.Spacing.sm) {
                        statusIcon(action.status)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(action.createdAt)
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }

                        Spacer()

                        Text(action.status.rawValue.capitalized)
                            .font(Theme.Typography.footnote)
                            .foregroundColor(statusColor(action.status))
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.sm)
                }
            }
        }
    }

    private func statusIcon(_ status: AgentActionStatus) -> some View {
        Group {
            switch status {
            case .applied:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.Colors.accentGreen)
            case .rejected:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Theme.Colors.accentRed)
            case .undone:
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundColor(Theme.Colors.textSecondary)
            case .pending:
                Image(systemName: "clock.fill")
                    .foregroundColor(Theme.Colors.accentOrange)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private func statusColor(_ status: AgentActionStatus) -> Color {
        switch status {
        case .applied: return Theme.Colors.accentGreen
        case .rejected: return Theme.Colors.accentRed
        case .undone: return Theme.Colors.textSecondary
        case .pending: return Theme.Colors.accentOrange
        case .unknown: return Theme.Colors.textSecondary
        }
    }
}

private struct SyncQueueMetricRow: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text("\(value)")
                .font(Theme.Typography.captionBold)
                .foregroundColor(value > 0 ? color : Theme.Colors.textTertiary)
        }
    }
}

// MARK: - Platform Status

enum PlatformConnectionStatus {
    case connected
    case disconnected
    case error
    case syncing
}

private struct PlatformStatusBar: View {
    let name: String
    let icon: String
    let iconColor: Color
    let status: PlatformConnectionStatus
    let detail: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.15))
                .cornerRadius(Theme.CornerRadius.sm)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(detail)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(statusColor)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    private var statusColor: Color {
        switch status {
        case .connected: return Theme.Colors.accentGreen
        case .disconnected: return Theme.Colors.textTertiary
        case .error: return Theme.Colors.accentRed
        case .syncing: return Theme.Colors.accentBlue
        }
    }

    private var statusText: String {
        switch status {
        case .connected: return "Connected"
        case .disconnected: return "Offline"
        case .error: return "Error"
        case .syncing: return "Syncing"
        }
    }
}

// MARK: - Pending Decision Card

private struct PendingDecisionCard: View {
    let action: AgentAction
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(Theme.Colors.accentOrange)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    if let summary = action.preview ?? action.rationale {
                        Text(summary)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button(action: onApprove) {
                    Text("Approve")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentGreen)
                        .cornerRadius(Theme.CornerRadius.md)
                }

                Button(action: onReject) {
                    Text("Reject")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentRed)
                        .cornerRadius(Theme.CornerRadius.md)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.accentOrange.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    private var iconName: String {
        switch action.kind {
        case let value where value.contains("move") || value.contains("schedule"):
            return "calendar.badge.clock"
        case let value where value.contains("downgrade") || value.contains("recovery"):
            return "arrow.down.circle"
        case let value where value.contains("rest"):
            return "bed.double.fill"
        case let value where value.contains("week") || value.contains("plan"):
            return "calendar"
        case let value where value.contains("session") || value.contains("workout"):
            return "figure.run"
        default:
            return "bell.fill"
        }
    }
}

#Preview {
    NavigationStack {
        SyncDashboardView()
            .environmentObject(WorkoutsViewModel())
    }
    .preferredColorScheme(.dark)
}
