//
//  PendingActionViews.swift
//  AmakaFlow
//
//  AMA-2230 (E9-4): native PendingActions confirmation surfaces.
//

import SwiftUI

struct PendingActionCard: View {
    let action: PendingActionContract
    let isBusy: Bool
    let onReject: () -> Void
    let onDetails: () -> Void
    let onApprove: () -> Void

    private var canDecide: Bool {
        action.executionStatus.acceptsConfirmationDecision
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(action.riskTier.color)
                        Text("PENDING ACTION")
                            .font(Font.geistMono(10, .medium))
                            .tracking(0.8)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    PendingRiskChip(risk: action.riskTier)
                }

                Text(action.title)
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(action.why)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(action.exactSteps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Circle()
                                .fill(Theme.Colors.textTertiary)
                                .frame(width: 4, height: 4)
                                .padding(.top, 7)
                            Text(step)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)

                HStack(spacing: Theme.Spacing.sm) {
                    Label("EXPIRES IN \(action.expiresIn)", systemImage: "clock")
                    Rectangle()
                        .fill(Theme.Colors.borderLight)
                        .frame(width: 1, height: 10)
                    Label(action.reversible ? "REVERSIBLE" : "NOT REVERSIBLE", systemImage: action.reversible ? "arrow.left.arrow.right" : "flag")
                        .foregroundColor(action.reversible ? Theme.Colors.textSecondary : Theme.Colors.readyLow)
                }
                .font(Font.geistMono(9.5, .regular))
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.top, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().fill(Theme.Colors.borderLight).frame(height: 1), alignment: .top)
            }
            .padding(Theme.Spacing.md)

            HStack(spacing: 0) {
                PendingActionButton(title: "Reject", foreground: Theme.Colors.textSecondary, background: Color.clear, isDisabled: isBusy || !canDecide, action: onReject)
                Divider().background(Theme.Colors.borderLight)
                PendingActionButton(title: "Details", foreground: Theme.Colors.textPrimary, background: Color.clear, isDisabled: isBusy, action: onDetails)
                Divider().background(Theme.Colors.borderLight)
                PendingActionButton(title: "Approve", foreground: Theme.Colors.primaryForeground, background: Theme.Colors.primary, isDisabled: isBusy || !canDecide, action: onApprove)
            }
            .frame(height: 44)
            .overlay(Rectangle().fill(Theme.Colors.borderLight).frame(height: 1), alignment: .top)
        }
        .background(Theme.Colors.surfaceElevated)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(action.riskTier.color)
                .frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending-action-card-\(action.actionId)")
    }
}

struct PendingRiskChip: View {
    let risk: PendingActionRiskTier

    var body: some View {
        Text(risk.label)
            .font(Font.geistMono(9.5, .medium))
            .foregroundColor(risk.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(risk.color, lineWidth: 1))
            .accessibilityIdentifier("pending-action-risk-\(risk.rawValue)")
    }
}

private struct PendingActionButton: View {
    let title: String
    let foreground: Color
    let background: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.captionBold)
                .foregroundColor(foreground.opacity(isDisabled ? 0.5 : 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background.opacity(isDisabled ? 0.65 : 1))
        }
        .disabled(isDisabled)
    }
}

struct PendingActionDetailsView: View {
    let action: PendingActionContract
    let isBusy: Bool
    let onReject: () -> Void
    let onApprove: () -> Void

    private var canDecide: Bool {
        action.executionStatus.acceptsConfirmationDecision
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(action.title)
                        .font(Theme.Typography.afH2)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(action.why)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                section(title: "EXACT CHANGES") {
                    VStack(spacing: 0) {
                        ForEach(Array(action.exactSteps.enumerated()), id: \.offset) { index, step in
                            row(
                                leading: String(format: "%02d", index + 1),
                                trailing: step,
                                isLast: index == action.exactSteps.count - 1
                            )
                        }
                    }
                }

                section(title: "WHY THIS RISK LEVEL") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(action.riskTier.label.replacingOccurrences(of: " RISK", with: "")) - \(action.riskTier.note.lowercased())")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(action.riskTier.color)
                        Text(action.reversible ? "It writes to your plan and connected devices, but every change is reversible from the action lifecycle." : "This change is not marked reversible, so approval is required before any side effect.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.backgroundSubtle)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(action.riskTier.color).frame(width: 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                            .stroke(Theme.Colors.borderLight, lineWidth: 1)
                    )
                }

                section(title: "EXECUTION PATH") {
                    VStack(spacing: 0) {
                        row(leading: "Channel Gateway", trailing: "iOS request · same path as Telegram", isLast: false)
                        row(leading: "Coach core", trailing: "Shared planner · no iOS-only logic", isLast: false)
                        row(leading: "Tools", trailing: action.toolName, isLast: true)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Button("Reject", action: onReject)
                    .buttonStyle(AFGhostButtonStyle())
                    .disabled(isBusy || !canDecide)
                Button("Approve", action: onApprove)
                    .buttonStyle(AFPrimaryButtonStyle())
                    .disabled(isBusy || !canDecide)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.background.overlay(Rectangle().fill(Theme.Colors.borderLight).frame(height: 1), alignment: .top))
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Action details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PendingRiskChip(risk: action.riskTier)
            }
        }
        .accessibilityIdentifier("pending-action-details-\(action.actionId)")
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.label)
                .tracking(0.8)
                .foregroundColor(Theme.Colors.textSecondary)
            content()
        }
    }

    private func row(leading: String, trailing: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(leading)
                .font(Font.geistMono(10.5, .medium))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(minWidth: 34, alignment: .leading)
            Text(trailing)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 12)
        .overlay {
            if !isLast {
                Rectangle()
                    .fill(Theme.Colors.borderLight)
                    .frame(height: 1)
                    .padding(.leading, Theme.Spacing.md)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(Theme.Colors.surfaceElevated)
    }
}

struct PendingActionsLifecycleView: View {
    let actions: [PendingActionContract]
    let onRetry: (PendingActionContract) -> Void
    let onAskAgain: (PendingActionContract) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(actions) { action in
                    PendingLifecycleRow(
                        action: action,
                        onRetry: { onRetry(action) },
                        onAskAgain: { onAskAgain(action) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Actions")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("pending-actions-lifecycle")
    }
}

private struct PendingLifecycleRow: View {
    let action: PendingActionContract
    let onRetry: () -> Void
    let onAskAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                HStack(spacing: 7) {
                    statusIcon
                    Text(action.executionStatus.lifecycleLabel)
                        .font(Theme.Typography.label)
                        .tracking(0.8)
                        .foregroundColor(action.executionStatus.toneColor)
                }
                Spacer()
                Text(action.lastResponseStatus == "replayed_noop" ? "NOOP" : "NOW")
                    .font(Font.geistMono(9, .regular))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text(action.title)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            if action.executionStatus == .failedRetryable {
                Button("Retry", action: onRetry)
                    .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
            } else if action.executionStatus == .expired || action.executionStatus == .stale {
                Button("Ask again", action: onAskAgain)
                    .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
            } else if action.executionStatus == .succeeded && action.reversible {
                Button("Undo") { }
                    .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
                    .disabled(true)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surfaceElevated)
        .overlay(alignment: .leading) {
            Rectangle().fill(action.executionStatus.toneColor).frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        .opacity(action.executionStatus == .expired || action.executionStatus == .stale ? 0.72 : 1)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if action.executionStatus == .executing {
            ProgressView()
                .controlSize(.mini)
        } else {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(iconForeground)
                .frame(width: 16, height: 16)
                .background(iconBackground)
                .clipShape(Circle())
                .overlay(Circle().stroke(action.executionStatus.toneColor, lineWidth: iconBackground == Color.clear ? 1.5 : 0))
        }
    }

    private var iconName: String {
        switch action.executionStatus {
        case .succeeded: return "checkmark"
        case .failedRetryable, .failedTerminal: return "xmark"
        case .expired, .stale, .replayedNoop: return "clock"
        case .declined, .canceled: return "minus"
        default: return "bolt.fill"
        }
    }

    private var iconForeground: Color {
        action.executionStatus == .expired || action.executionStatus == .stale ? action.executionStatus.toneColor : Theme.Colors.primaryForeground
    }

    private var iconBackground: Color {
        action.executionStatus == .expired || action.executionStatus == .stale ? Color.clear : action.executionStatus.toneColor
    }

    private var subtitle: String {
        if let error = action.error {
            return error.message
        }
        switch action.executionStatus {
        case .executing: return "Execution is running through the shared PendingActions path."
        case .succeeded: return "Saved through the shared execute path. No duplicate side effect on replay."
        case .failedRetryable: return "The dependency returned a retryable data_gap. Nothing is silently marked successful."
        case .failedTerminal: return "The backend marked this terminal; retry is not offered."
        case .expired: return "You did not respond inside the confirmation window."
        case .declined: return "You rejected this action. Later approvals are safe noops."
        case .replayedNoop: return "Replay returned the existing result; no second side effect ran."
        case .stale: return "Your plan changed after this was proposed."
        default: return "Nothing runs until you approve."
        }
    }
}
