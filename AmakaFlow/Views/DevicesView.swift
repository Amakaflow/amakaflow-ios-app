//
//  DevicesView.swift
//  AmakaFlow
//
//  AMA-1996: Connected devices screen (D4 Wedge A list).
//  AMA-2030: role chips are writable toggles.
//

import SwiftUI

struct DevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DevicesViewModel
    @State private var didLoad = false
    @State private var showingPairSheet = false
    @State private var pendingRemoval: DevicesViewModel.PairedDevice?

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
                    actionTitle: errorActionTitle,
                    error: error,
                    onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .sheet(isPresented: $showingPairSheet) {
            PairDeviceSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Remove this device?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let device = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await viewModel.remove(device) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("You'll need to re-pair it.")
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
            backAction: { dismiss() },
            right: { AFChip(text: "Roles", outline: true) }
        )
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

    private var errorActionTitle: String {
        switch viewModel.lastFailedAction {
        case .load:
            return "Couldn't load devices"
        case .pair:
            return "Couldn't add device"
        case .remove:
            return "Couldn't remove device"
        case .setRoles:
            return "Couldn't update device roles"
        case .none:
            return "Device action failed"
        }
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

                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    roleChips(for: display.device)
                    Spacer(minLength: 0)
                    removeButton(for: display.device)
                }
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
                let isUpdating = viewModel.isSettingRoles(for: device)
                Button {
                    Task {
                        await viewModel.toggleRole(role, for: device)
                    }
                } label: {
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
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .opacity(isUpdating ? 0.7 : 1)
                .accessibilityLabel("\(DevicesViewModel.roleLabel(role)) role")
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(isUpdating ? "Updating roles" : "Double tap to toggle")
                .accessibilityIdentifier("af_device_role_\(device.id)_\(role.rawValue)")
            }
        }
        .accessibilityIdentifier("device_roles_\(device.id)")
    }

    private var addDeviceButton: some View {
        Button { showingPairSheet = true } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "plus")
                Text("Add device")
            }
        }
        .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
        .accessibilityIdentifier("af_devices_add")
    }

    private func removeButton(for device: DevicesViewModel.PairedDevice) -> some View {
        Button(role: .destructive) {
            pendingRemoval = device
        } label: {
            Label("Remove", systemImage: "trash")
                .labelStyle(.iconOnly)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundColor(Theme.Colors.accentRed)
                .padding(8)
                .background(Theme.Colors.surfaceElevated)
                .clipShape(Circle())
        }
        .accessibilityLabel("Remove \(device.name)")
        .accessibilityIdentifier("af_device_remove_\(device.id)")
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

private struct PairDeviceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DevicesViewModel
    @State private var shortCode = ""
    @State private var isSubmitting = false

    private var normalizedCode: String {
        Self.normalize(shortCode)
    }

    private var canSubmit: Bool {
        normalizedCode.count == 6 && !isSubmitting
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Add Garmin")
                        .afH2()
                    Text("Enter the code shown on your Garmin watch")
                        .afMuted()
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("6-digit code")
                        .font(Theme.Typography.footnote.weight(.semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                    TextField("ABC123", text: $shortCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .tint(Theme.Colors.readyHigh)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.inputBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm, style: .continuous)
                                .stroke(Theme.Colors.borderMedium, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm, style: .continuous))
                        .onChange(of: shortCode) { value in
                            let normalized = Self.normalize(value)
                            if normalized != value {
                                shortCode = normalized
                            }
                        }
                        .accessibilityIdentifier("af_device_pair_field")
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(Theme.Colors.primaryForeground)
                    } else {
                        Text("Pair device")
                    }
                }
                .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                .disabled(!canSubmit)
                .accessibilityIdentifier("af_device_pair_submit")

                Button("Cancel") { dismiss() }
                    .buttonStyle(AFGhostButtonStyle(size: .md))

                Spacer()
            }
            .padding(Theme.Spacing.lg)

            if let error = viewModel.ctaError, viewModel.lastFailedAction == .pair {
                ErrorToast(
                    actionTitle: "Couldn't add device",
                    error: error,
                    onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.background)
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        await viewModel.pair(shortCode: normalizedCode)
        if viewModel.lastFailedAction != .pair {
            dismiss()
        }
    }

    private static func normalize(_ value: String) -> String {
        String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }
}

#if DEBUG
#Preview("Devices") {
    NavigationStack {
        DevicesView(viewModel: DevicesViewModel(apiService: FixtureAPIService()))
    }
}
#endif
