//
//  ActivityFeedView.swift
//  AmakaFlow
//
//  Activity feed showing pending actions with approve/reject (AMA-1147)
//

import SwiftUI

struct ActivityFeedView: View {
    @StateObject private var viewModel = ActivityFeedViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.actions.isEmpty {
                    ProgressView("Loading actions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.actions.isEmpty {
                    emptyState
                } else {
                    actionsList
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Activity Feed")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.loadActions()
            }
            .task {
                await viewModel.loadActions()
            }
        }
    }

    // MARK: - Actions List

    private var actionsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.actions) { action in
                    ActionCard(action: action) {
                        Task { await viewModel.approveAction(action) }
                    } onReject: {
                        Task { await viewModel.rejectAction(action) }
                    } onUndo: {
                        Task { await viewModel.undoAction(action) }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.accentGreen)

            Text("All caught up")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("No pending actions right now. Check back after your next training session.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
    }
}

// MARK: - Action Card

private struct ActionCard: View {
    let action: PendingAction
    let onApprove: () -> Void
    let onReject: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                actionIcon
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(action.title)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    if let desc = action.description {
                        Text(desc)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()

                statusBadge
            }

            if action.status == .pending {
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
            } else if action.status == .approved || action.status == .rejected {
                Button(action: onUndo) {
                    Text("Undo")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    private var actionIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 20))
            .foregroundColor(iconColor)
            .frame(width: 40, height: 40)
            .background(iconColor.opacity(0.15))
            .cornerRadius(Theme.CornerRadius.md)
    }

    private var iconName: String {
        switch action.type {
        case .workoutSuggestion: return "figure.run"
        case .scheduleChange: return "calendar.badge.clock"
        case .recoveryReminder: return "bed.double.fill"
        case .goalUpdate: return "target"
        case .general: return "bell.fill"
        }
    }

    private var iconColor: Color {
        switch action.type {
        case .workoutSuggestion: return Theme.Colors.accentBlue
        case .scheduleChange: return Theme.Colors.accentOrange
        case .recoveryReminder: return Theme.Colors.accentGreen
        case .goalUpdate: return Color(hex: "9333EA")
        case .general: return Theme.Colors.textSecondary
        }
    }

    private var statusBadge: some View {
        Group {
            switch action.status {
            case .pending:
                Text("Pending")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.accentOrange)
            case .approved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.Colors.accentGreen)
            case .rejected:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Theme.Colors.accentRed)
            case .undone:
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }
}

#Preview {
    ActivityFeedView()
        .preferredColorScheme(.dark)
}
