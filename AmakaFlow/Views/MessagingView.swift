//
//  MessagingView.swift
//  AmakaFlow
//
//  AMA-2027: Messaging channels + coaching-delivery preferences.
//

import SwiftUI

struct MessagingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MessagingViewModel
    @State private var didLoad = false

    init(viewModel: MessagingViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? MessagingViewModel())
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
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.load()
        }
        .accessibilityIdentifier("messaging_screen")
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Loading messaging channels")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("messaging_loading")
    }

    private var contentView: some View {
        scrollContainer {
            if !viewModel.deliveryLive {
                deliveryComingSoonBanner
            }
            channelsSection
        }
    }

    private var emptyView: some View {
        scrollContainer {
            if !viewModel.deliveryLive {
                deliveryComingSoonBanner
            }

            AFLabel(text: "Messaging Channels")
                .accessibilityAddTraits(.isHeader)

            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(Theme.Colors.readyHigh)
                    Text("No messaging channels yet.")
                        .afH2()
                    Text("Check back when Telegram, WhatsApp, or Slack are available for your account.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("messaging_empty_state")
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
                    Text("We couldn't load your messaging channels.")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Retry when you’re back online. Saved preferences stay unchanged.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    if loadError?.isRetryable == true {
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Text("Retry")
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .md))
                        .accessibilityIdentifier("messaging_retry_load")
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
            title: "Messaging",
            subtitle: headerSubtitle,
            backIdentifier: "messaging_back",
            backAction: { dismiss() },
            right: { AFChip(text: "Prefs", outline: true) }
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
            return "Couldn't load messaging"
        case .setPrefs:
            return "Couldn't save messaging prefs"
        case .none:
            return "Messaging action failed"
        }
    }

    private var deliveryComingSoonBanner: some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.Colors.readyModerate)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Briefings & check-ins are coming soon")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Your preferences are saved, but AmakaFlow is not sending briefing, check-in, or swap messages yet.")
                        .afMuted()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("af_messaging_delivery_soon_banner")
    }

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AFLabel(text: "Messaging Channels")
                .accessibilityAddTraits(.isHeader)

            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(viewModel.channels, id: \.id) { channel in
                    MessagingChannelCard(viewModel: viewModel, channel: channel)
                }
            }
            .accessibilityIdentifier("messaging_channels_list")
        }
    }
}

private struct MessagingChannelCard: View {
    @ObservedObject var viewModel: MessagingViewModel
    let channel: MessagingViewModel.MessagingChannel

    private let quietOptions = ["20:00", "21:00", "22:00", "23:00", "06:00", "07:00", "08:00"]

    var body: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    iconTile

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                            Text(channel.name)
                                .afH3()
                            Spacer(minLength: 0)
                            statusChip
                        }

                        Text(subtitle)
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                VStack(spacing: Theme.Spacing.sm) {
                    prefToggle(title: "Morning briefing", key: "briefing", value: channel.prefs?.briefing == true) { isOn in
                        viewModel.prefsRequest(from: channel, briefing: isOn)
                    }
                    prefToggle(title: "Check-ins", key: "checkin", value: channel.prefs?.checkin == true) { isOn in
                        viewModel.prefsRequest(from: channel, checkin: isOn)
                    }
                    prefToggle(title: "Workout swaps", key: "swap", value: channel.prefs?.swap == true) { isOn in
                        viewModel.prefsRequest(from: channel, swap: isOn)
                    }
                    quietHoursRow
                }
                .disabled(!viewModel.canEditPrefs(for: channel))
                .opacity(viewModel.canEditPrefs(for: channel) ? 1 : 0.55)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("af_messaging_channel_\(channel.id)")
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                .fill(Theme.Colors.accentBackground)
                .frame(width: 48, height: 48)
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(iconColor)
        }
    }

    private var iconName: String {
        switch channel.id.lowercased() {
        case "telegram": return "paperplane.fill"
        case "whatsapp": return "phone.bubble.left.fill"
        case "slack": return "number"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }

    private var iconColor: Color {
        if viewModel.isComingSoon(channel) { return Theme.Colors.textSecondary }
        return viewModel.isConnected(channel) ? Theme.Colors.readyHigh : Theme.Colors.readyModerate
    }

    @ViewBuilder
    private var statusChip: some View {
        if viewModel.isComingSoon(channel) {
            AFChip(text: "Coming soon", outline: true)
        } else if viewModel.isConnected(channel) {
            AFChip(text: "Connected", outline: true)
        } else if channel.id.lowercased() == "telegram" {
            NavigationLink {
                TelegramSetupView()
            } label: {
                Text("Connect")
            }
            .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
            .accessibilityIdentifier("af_messaging_connect_telegram")
        } else {
            AFChip(text: "Not connected", outline: true)
        }
    }

    private var subtitle: String {
        if let handle = channel.handle, !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return handle
        }
        if viewModel.isComingSoon(channel) {
            return "Preferences are disabled until this channel ships."
        }
        if viewModel.isConnected(channel) {
            return "Preferences saved for future delivery."
        }
        return "Connect Telegram to save delivery preferences."
    }

    private func prefToggle(
        title: String,
        key: String,
        value: Bool,
        request: @escaping (Bool) -> MessagingViewModel.ChannelPrefsRequest
    ) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { value },
                set: { isOn in
                    Task { await viewModel.setPrefs(channel, prefs: request(isOn)) }
                }
            ))
            .labelsHidden()
            .tint(Theme.Colors.readyHigh)
            .disabled(!viewModel.canEditPrefs(for: channel))
            .accessibilityIdentifier("af_messaging_pref_\(channel.id)_\(key)")
        }
    }

    private var quietHoursRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quiet hours")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(MessagingViewModel.quietLabel(start: channel.prefs?.quietStart, end: channel.prefs?.quietEnd))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Spacer()
            quietMenu(title: "Start", selected: channel.prefs?.quietStart) { start in
                quietRequest(start: start, end: channel.prefs?.quietEnd)
            }
            quietMenu(title: "End", selected: channel.prefs?.quietEnd) { end in
                quietRequest(start: channel.prefs?.quietStart, end: end)
            }
        }
        .accessibilityIdentifier("af_messaging_pref_\(channel.id)_quiet_hours")
    }

    private func quietMenu(
        title: String,
        selected: String?,
        request: @escaping (String?) -> MessagingViewModel.ChannelPrefsRequest
    ) -> some View {
        Menu {
            Button("Off") {
                Task { await viewModel.setPrefs(channel, prefs: quietRequest(start: nil, end: nil)) }
            }
            ForEach(quietOptions, id: \.self) { option in
                Button(option) {
                    Task { await viewModel.setPrefs(channel, prefs: request(option)) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(title): \(selected ?? "Off")")
                Image(systemName: "chevron.down")
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundColor(Theme.Colors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.Colors.surfaceElevated)
            .clipShape(Capsule())
        }
        .disabled(!viewModel.canEditPrefs(for: channel))
    }

    private func quietRequest(start: String?, end: String?) -> MessagingViewModel.ChannelPrefsRequest {
        MessagingViewModel.ChannelPrefsRequest(
            briefing: channel.prefs?.briefing ?? false,
            checkin: channel.prefs?.checkin ?? false,
            quietEnd: end,
            quietStart: start,
            swap: channel.prefs?.swap ?? false
        )
    }
}

#Preview("Messaging") {
    NavigationStack {
        MessagingView(viewModel: MessagingViewModel(apiService: MockAPIService()))
    }
}
