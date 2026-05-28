//
//  DevicesView.swift
//  AmakaFlow
//
//  AMA-1996: Connected devices screen (D4 Wedge A read-only list).
//

import SwiftUI

struct DevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DevicesViewModel
    @State private var didLoad = false

    init(viewModel: DevicesViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? DevicesViewModel())
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            Group {
                switch viewModel.state {
                case .loading:
                    loadingView
                case .content:
                    contentView
                case .empty:
                    emptyView
                case .error:
                    loadErrorView
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            if let error = viewModel.ctaError {
                ErrorToast(
                    actionTitle: "Couldn't load devices",
                    error: error,
                    onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.load()
        }
        .accessibilityIdentifier("devices_screen")
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Loading connected devices")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("devices_loading")
    }

    private var contentView: some View {
        scrollContainer {
            devicesSection
            infoNote
        }
    }

    private var emptyView: some View {
        scrollContainer {
            AFLabel(text: "Connected Devices")
                .accessibilityAddTraits(.isHeader)

            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "watch")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(Theme.Colors.readyHigh)
                    Text("No devices paired.")
                        .afH2()
                    Text("Add one to sync workouts.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    addDeviceButton
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("devices_empty_state")

            infoNote
        }
    }

    private var loadErrorView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            topBar

            Spacer()

            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Theme.Colors.accentRed)
                    Text("We couldn't load your devices.")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Retry when you’re back online. Device roles and pairing stay unchanged.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    if loadError?.isRetryable == true {
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Text("Retry")
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .md))
                        .accessibilityIdentifier("devices_retry_load")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
    }

    @ViewBuilder
    private func scrollContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                topBar
                    .padding(.horizontal, -Theme.Spacing.lg)

                content()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }

    private var topBar: some View {
        AFTopBar(
            title: "Devices",
            subtitle: headerSubtitle,
            backIdentifier: "devices_back",
            backAction: { dismiss() }
        ) {
            AFChip(text: "Read", outline: true)
        }
    }

    private var headerSubtitle: String {
        if case .error = viewModel.state {
            return "Unable to load"
        }
        return viewModel.connectedSubtitle
    }

    private var loadError: CTAError? {
        if case .error(let error) = viewModel.state {
            return error
        }
        return viewModel.ctaError
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center) {
                AFLabel(text: "Connected Devices")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                addDeviceButton
            }

            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(viewModel.displayDevices) { device in
                    deviceCard(device)
                }
            }
            .accessibilityIdentifier("devices_list")
        }
    }

    private func deviceCard(_ display: DevicesViewModel.DisplayDevice) -> some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    iconTile(symbolName: display.symbolName)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                            Text(display.name)
                                .afH3()
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Circle()
                                .fill(Theme.Colors.readyHigh)
                                .frame(width: 8, height: 8)
                                .accessibilityLabel("Synced")
                        }

                        Text(display.modelSyncCaption)
                            .font(Theme.Typography.mono)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                roleChips(for: display.device)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device_card_\(display.id)")
    }

    private func iconTile(symbolName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                .fill(Theme.Colors.accentBackground)
                .frame(width: 48, height: 48)
            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.Colors.readyHigh)
        }
    }

    private func roleChips(for device: DevicesViewModel.PairedDevice) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(DevicesViewModel.displayRoles, id: \.self) { role in
                let selected = viewModel.hasRole(role, in: device)
                Text(DevicesViewModel.roleLabel(role))
                    .font(Theme.Typography.footnote.weight(.semibold))
                    .foregroundColor(selected ? Theme.Colors.primaryForeground : Theme.Colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selected ? Theme.Colors.primary : Color.clear)
                    .overlay(
                        Capsule().stroke(selected ? Theme.Colors.primary : Theme.Colors.borderMedium, lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("device_role_\(role.rawValue)")
            }
        }
        .accessibilityIdentifier("device_roles_\(device.id)")
    }

    private var addDeviceButton: some View {
        Button { } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "plus")
                Text("Add device")
                Text("SOON")
                    .font(Theme.Typography.captionBold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.chipBackground)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
        .disabled(true)
        .accessibilityIdentifier("devices_add_device")
    }

    private var infoNote: some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("Roles decide which device feeds which metric. If two devices fight for the same role, the most-recently-synced wins.")
                    .afMuted()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("devices_roles_note")
    }
}

#Preview("Devices") {
    NavigationStack {
        DevicesView(viewModel: DevicesViewModel(apiService: MockAPIService()))
    }
}
