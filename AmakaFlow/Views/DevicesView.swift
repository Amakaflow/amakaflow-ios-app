//
//  DevicesView.swift
//  AmakaFlow
//
//  AMA-1996: Connected devices screen (D4 Wedge A list).
//  AMA-2030: role chips are writable toggles.
//

import SwiftUI

// swiftlint:disable file_length type_body_length
struct DevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DevicesViewModel
    @State private var didLoad = false
    @State private var showingPairSheet = false
    @State private var showingWatchDisplayPrefs = false
    /// AMA-2317: raise the prefs sheet only once the pair sheet has dismissed.
    @State private var prefsQueuedAfterPair = false
    @State private var pendingRemoval: DevicesViewModel.PairedDevice?

    init(viewModel: DevicesViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? DevicesViewModel())
    }

    var body: some View {
        ZStack {
            DailyDriver.screenBackground.ignoresSafeArea()

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
        .preferredColorScheme(.dark)
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
        .sheet(isPresented: $showingPairSheet, onDismiss: presentQueuedDisplayPrefs) {
            PairDeviceSheet(viewModel: viewModel) {
                // AMA-2316/AMA-2317: one-time watch display prefs, raised after dismiss.
                prefsQueuedAfterPair = GarminPairFollowUp.shouldPresentDisplayPrefs(
                    pairSucceeded: true,
                    hasConfiguredPrefs: GarminWatchDisplayPrefsStore.hasConfigured
                )
            }
        }
        .sheet(isPresented: $showingWatchDisplayPrefs) {
            GarminWatchDisplayPrefsSheet(
                mode: GarminWatchDisplayPrefsStore.hasConfigured ? .settings : .onboarding
            )
        }
        .confirmationDialog(
            GarminLifecycleCopy.removeDeviceTitle,
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
            Text(GarminLifecycleCopy.removeDeviceMessage)
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.load()
            // AMA-2316/AMA-2317: if Garmin is already paired and prefs never set, ask once.
            // Require a Garmin (not just any wearable) so Apple Watch–only lists never spam this sheet.
            if GarminWatchDisplayPrefsStore.shouldPresentOnboarding,
               case .content = viewModel.state,
               viewModel.hasPairedGarmin {
                showingWatchDisplayPrefs = true
            }
        }
        .accessibilityIdentifier("devices_screen")
    }

    /// SwiftUI drops a sheet raised while another is still dismissing, so the
    /// AMA-2316 prefs onboarding has to wait for the pair sheet to go away.
    private func presentQueuedDisplayPrefs() {
        guard prefsQueuedAfterPair else { return }
        prefsQueuedAfterPair = false
        showingWatchDisplayPrefs = true
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(DailyDriver.foreground)
            Text("Loading connected devices")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("devices_loading")
    }

    private var contentView: some View {
        scrollContainer {
            devicesSection
            watchDisplayPrefsRow
            if #available(iOS 18.0, *) {
                scheduledWorkoutPlansRow
            }
            pairingLifecycleNote
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
                        .foregroundColor(DailyDriver.lime)
                    Text("No devices paired.")
                        .afH2()
                    Text(GarminLifecycleCopy.notPairedLifecycleCaption)
                        .afMuted()
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("af_devices_pairing_status")
                    addDeviceButton
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("devices_empty_state")

            if #available(iOS 18.0, *) {
                scheduledWorkoutPlansRow
            }

            pairingLifecycleNote
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

    /// AMA-2316: Settings → Garmin edit entry (also reachable from Devices).
    private var watchDisplayPrefsRow: some View {
        Button {
            showingWatchDisplayPrefs = true
        } label: {
            AFCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Watch workout display")
                        .afH2()
                    Text(
                        GarminWatchDisplayPrefsStore.hasConfigured
                            ? GarminWatchDisplayPrefsStore.current.summaryLine
                            : "Choose how work sets and rest show on Garmin."
                    )
                    .afMuted()
                    .multilineTextAlignment(.leading)
                    .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_garmin_watch_display_prefs_devices")
    }

    /// AMA-2330: entry point to the WorkoutKit scheduled-plan cleanup screen.
    /// iOS 18+ only — no "Requires iOS 18" row on older systems, just hidden.
    @available(iOS 18.0, *)
    private var scheduledWorkoutPlansRow: some View {
        NavigationLink {
            WorkoutScheduleView()
        } label: {
            AFCard {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Scheduled in Workout")
                            .afH2()
                        Text("Manage AmakaFlow plans scheduled in the Apple Watch Workout app.")
                            .afMuted()
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_devices_scheduled_workout_plans")
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
                                .fill(DailyDriver.lime)
                                .frame(width: 8, height: 8)
                                .accessibilityLabel("Synced")
                        }

                        Text(display.modelSyncCaption)
                            .font(Theme.Typography.mono)
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .lineLimit(2)

                        // AMA-2317: pairing is one-shot; say so on the row itself.
                        Text(GarminLifecycleCopy.pairedLifecycleCaption)
                            .font(Theme.Typography.footnote)
                            .foregroundColor(DailyDriver.lime)
                            .accessibilityIdentifier("af_device_pairing_status_\(display.id)")
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
                .foregroundColor(DailyDriver.lime)
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
                        .foregroundColor(selected ? Theme.Colors.primaryForeground : DailyDriver.foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? Theme.Colors.primary : Color.clear)
                        .overlay(
                            Capsule().stroke(selected ? Theme.Colors.primary : DailyDriver.borderStrong, lineWidth: 1)
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

    /// AMA-2317: answers the two dogfood questions in one place — does the code
    /// expire, and does Remove delete workouts off the watch.
    private var pairingLifecycleNote: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(GarminLifecycleCopy.pairCodeLifecycle)
                    .afMuted()
                    .fixedSize(horizontal: false, vertical: true)
                Text(GarminLifecycleCopy.deviceScopeNote)
                    .afMuted()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("af_devices_pairing_lifecycle_note")
    }

    private var infoNote: some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(DailyDriver.foregroundMuted)
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
    /// Called after a successful pair (before this sheet dismisses).
    var onPaired: (() -> Void)?
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
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(GarminLifecycleCopy.pairSheetTitle)
                        .afH2()
                    Text(GarminLifecycleCopy.pairSheetSubtitle)
                        .afMuted()
                    Text(GarminLifecycleCopy.pairCodeLifecycle)
                        .afMuted()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("af_device_pair_lifecycle_note")
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("6-digit code")
                        .font(Theme.Typography.footnote.weight(.semibold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                    TextField("ABC123", text: $shortCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(DailyDriver.foreground)
                        .tint(DailyDriver.lime)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.inputBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm, style: .continuous)
                                .stroke(DailyDriver.borderStrong, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm, style: .continuous))
                        .onChange(of: shortCode) { value in
                            let normalized = Self.normalize(value)
                            if normalized != value {
                                shortCode = normalized
                            }
                        }
                        .accessibilityIdentifier("af_device_pair_field")

                    Text(GarminLifecycleCopy.pairCodeExpired)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .fixedSize(horizontal: false, vertical: true)
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
        .presentationBackground(DailyDriver.screenBackground)
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        await viewModel.pair(shortCode: normalizedCode)
        if viewModel.lastFailedAction != .pair {
            onPaired?()
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

// swiftlint:enable file_length type_body_length
