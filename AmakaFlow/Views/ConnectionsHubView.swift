//
//  ConnectionsHubView.swift
//  AmakaFlow
//
//  AMA-2103: Profile → Connections hub and reusable connection detail shell.
//

import SwiftUI

struct ConnectionsHubView: View {
    @ObservedObject var viewModel: ConnectionsHubViewModel
    let statusProvider: () -> ConnectionsHubStatusSnapshot
    let telegramInitialID: Int?
    let telegramInitiallyConnected: Bool
    let onTelegramConnected: (Int?) -> Void

    init(
        viewModel: ConnectionsHubViewModel,
        statusProvider: @escaping () -> ConnectionsHubStatusSnapshot,
        telegramInitialID: Int? = nil,
        telegramInitiallyConnected: Bool = false,
        onTelegramConnected: @escaping (Int?) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.statusProvider = statusProvider
        self.telegramInitialID = telegramInitialID
        self.telegramInitiallyConnected = telegramInitiallyConnected
        self.onTelegramConnected = onTelegramConnected
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                AFTopBar(title: "Connections", subtitle: "Watches, messaging, and delivery") {
                    EmptyView()
                } right: {
                    EmptyView()
                }

                summaryCard

                SettingsSectionCard(title: "All connections") {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            NavigationLink {
                                connectionDetail(for: item)
                            } label: {
                                connectionRow(item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(item.accessibilityID)

                            if index < viewModel.items.count - 1 {
                                SettingsRowDivider()
                            }
                        }
                    }
                }

                infoNote
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("af_connections_hub")
        .onAppear {
            viewModel.refresh(from: statusProvider())
        }
    }

    private var summaryCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(Theme.Colors.readyHigh)
                .frame(width: 10, height: 10)
                .shadow(color: Theme.Colors.readyHigh.opacity(0.28), radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.summaryText)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Watches, messaging, and delivery")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            Text("\(viewModel.connectedCount)/\(viewModel.items.count)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
        .accessibilityIdentifier("af_connections_summary")
    }

    private func connectionRow(_ item: ConnectionItem) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            connectionTile(item, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(item.purpose)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.md)

            ConnectionStatusPill(status: item.status, kind: item.kind)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.purpose), \(item.status.pillText(for: item.kind))")
    }

    private var infoNote: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Connect a watch to read readiness, messaging to hear from your coach, and a calendar to block out sessions.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }

    @ViewBuilder
    private func connectionDetail(for item: ConnectionItem) -> some View {
        ConnectionDetailView(item: item) {
            switch item.kind {
            case .appleWatch, .garmin:
                DevicesView()
            case .telegram:
                TelegramSetupView(
                    initialTelegramId: telegramInitialID,
                    initiallyConnected: telegramInitiallyConnected,
                    onConnected: { telegramId in
                        onTelegramConnected(telegramId)
                        viewModel.refresh(from: statusProvider())
                    }
                )
            case .sync:
                SyncDashboardView()
            case .calendar:
                CalendarSyncView()
            }
        }
    }

    private func connectionTile(_ item: ConnectionItem, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(item.tint.opacity(item.status.isOn ? 0.16 : 0.09))
                .frame(width: size, height: size)
            Image(systemName: item.icon)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundColor(item.status.isOn ? item.tint : Theme.Colors.textTertiary)
        }
    }
}

struct ConnectionDetailView<Destination: View>: View {
    let item: ConnectionItem
    private let destination: Destination

    init(item: ConnectionItem, @ViewBuilder destination: () -> Destination) {
        self.item = item
        self.destination = destination()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header
                statusCard
                if item.status.isOn {
                    metaCard
                }
                actionLink
                footnote
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("af_connection_detail_\(item.kind.rawValue)")
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(item.tint.opacity(0.16))
                    .frame(width: 68, height: 68)
                Image(systemName: item.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(item.tint)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(item.name)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(item.description)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
    }

    private var statusCard: some View {
        HStack {
            Text("STATUS")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
            Spacer()
            ConnectionStatusPill(status: item.status, kind: item.kind)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
    }

    private var metaCard: some View {
        SettingsSectionCard(title: item.kind.connectedMetaTitle) {
            VStack(spacing: 0) {
                ForEach(Array(item.meta.enumerated()), id: \.element.id) { index, meta in
                    HStack {
                        Text(meta.label)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Text(meta.value)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, Theme.Spacing.sm)

                    if index < item.meta.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionLink: some View {
        if item.status.isOn {
            NavigationLink {
                destination
            } label: {
                Text(item.actionLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AFGhostButtonStyle(size: .lg))
            .accessibilityIdentifier("af_connection_action_\(item.kind.rawValue)")
        } else {
            NavigationLink {
                destination
            } label: {
                Text(item.actionLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .lg))
            .accessibilityIdentifier("af_connection_action_\(item.kind.rawValue)")
        }
    }

    private var footnote: some View {
        Text(item.status.isOn ? "You can disconnect any time — your history stays in AmakaFlow." : "Connecting takes a few seconds and you can disconnect whenever you like.")
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.lg)
    }
}

private struct ConnectionStatusPill: View {
    let status: ConnectionLiveStatus
    let kind: ConnectionKind

    var body: some View {
        HStack(spacing: 6) {
            if status.isOn {
                Circle()
                    .fill(Theme.Colors.readyHigh)
                    .frame(width: 8, height: 8)
                Text(status.pillText(for: kind))
            } else {
                Text(status.pillText(for: kind))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .font(Theme.Typography.footnote)
        .foregroundColor(status.isOn ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
        .padding(.horizontal, status.isOn ? Theme.Spacing.sm : 0)
        .padding(.vertical, status.isOn ? 4 : 0)
        .background(status.isOn ? Theme.Colors.readyHigh.opacity(0.12) : Color.clear)
        .clipShape(Capsule())
    }
}
