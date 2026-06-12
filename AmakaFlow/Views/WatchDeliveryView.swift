//
//  WatchDeliveryView.swift
//  AmakaFlow
//
//  AMA-2028: Poll-based watch delivery timeline.
//

import SwiftUI

struct WatchDeliveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WatchDeliveryViewModel
    @State private var didLoad = false

    let workoutId: String
    let workoutName: String?

    init(
        workoutId: String,
        workoutName: String? = nil,
        viewModel: WatchDeliveryViewModel? = nil
    ) {
        self.workoutId = workoutId
        self.workoutName = workoutName
        _viewModel = StateObject(wrappedValue: viewModel ?? WatchDeliveryViewModel())
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
            await viewModel.load(workoutId: workoutId)
        }
        .onDisappear {
            viewModel.cancelPolling()
        }
        .accessibilityIdentifier("watch_delivery_screen")
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Loading watch delivery")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("watch_delivery_loading")
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                topBar
                    .padding(.horizontal, -Theme.Spacing.lg)

                if let workoutName, !workoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(workoutName)
                        .afH2()
                        .lineLimit(2)
                }

                currentStatusCard
                timelineCard
                resendSection
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 100)
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
                    Text("We couldn't load watch delivery.")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Retry when you're back online. The workout delivery record stays unchanged.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    if loadError?.isRetryable == true {
                        Button {
                            Task { await viewModel.load(workoutId: workoutId) }
                        } label: {
                            Text("Retry")
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .md))
                        .accessibilityIdentifier("watch_delivery_retry_load")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
    }

    private var topBar: some View {
        AFTopBar(
            title: "Watch Delivery",
            subtitle: headerSubtitle,
            backIdentifier: "watch_delivery_back",
            backAction: { dismiss() },
            right: { AFChip(text: "Poll", outline: true) }
        )
    }

    private var headerSubtitle: String {
        guard let status = viewModel.status else { return "Checking Garmin" }
        return WatchDeliveryViewModel.isTerminal(status.state) ? "Final state" : "Auto-refreshing"
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
            return "Couldn't load delivery"
        case .resend:
            return "Couldn't resend workout"
        case .none:
            return "Watch delivery failed"
        }
    }

    @ViewBuilder
    private var currentStatusCard: some View {
        if let status = viewModel.status {
            let visual = Visuals.visual(for: status.state)
            AFCard {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Text(visual.emoji)
                        .font(.system(size: 34))
                        .frame(width: 52, height: 52)
                        .background(visual.color.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack(alignment: .center) {
                            Text(status.title)
                                .afH2()
                            Spacer(minLength: 0)
                            AFChip(text: WatchDeliveryViewModel.displayName(for: status.state), outline: true)
                        }

                        if let subtitle = status.subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(subtitle)
                                .afMuted()
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let relative = viewModel.occurredAtRelativeText {
                            Text(relative)
                                .font(Theme.Typography.mono)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Watch delivery state")
            .accessibilityValue(viewModel.stateValue)
            .accessibilityIdentifier("af_watch_delivery_state")
        }
    }

    @ViewBuilder
    private var timelineCard: some View {
        if let status = viewModel.status {
            AFCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    AFLabel(text: "Delivery Timeline")
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(WatchDeliveryStep.allCases) { step in
                            TimelineRow(
                                step: step,
                                currentState: status.state,
                                isLast: step == WatchDeliveryStep.allCases.last
                            )
                        }
                    }
                }
            }
            .accessibilityIdentifier("watch_delivery_timeline")
        }
    }

    @ViewBuilder
    private var resendSection: some View {
        if viewModel.status?.canResend == true {
            Button {
                Task { await viewModel.resend(workoutId: workoutId) }
            } label: {
                if viewModel.isResending {
                    ProgressView()
                        .tint(Theme.Colors.primaryForeground)
                } else {
                    Text("Resend to watch")
                }
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .lg))
            .disabled(!viewModel.canResend)
            .accessibilityIdentifier("af_watch_delivery_resend")
        }
    }
}

private enum WatchDeliveryStep: CaseIterable, Identifiable {
    case generated
    case pushed
    case fetchedByWidget
    case confirmedOnDevice
    case failed

    var id: String { state.rawValue }

    var state: Components.Schemas.WatchDeliveryState {
        switch self {
        case .generated: return .generated
        case .pushed: return .pushed
        case .fetchedByWidget: return .fetchedByWidget
        case .confirmedOnDevice: return .confirmedOnDevice
        case .failed: return .failed
        }
    }

    var title: String {
        WatchDeliveryViewModel.displayName(for: state)
    }

    var subtitle: String {
        switch self {
        case .generated: return "Workout created for watch delivery"
        case .pushed: return "Sent to Garmin Connect"
        case .fetchedByWidget: return "Watch widget fetched the workout"
        case .confirmedOnDevice: return "Confirmed on the watch"
        case .failed: return "Delivery needs attention"
        }
    }
}

private struct TimelineRow: View {
    let step: WatchDeliveryStep
    let currentState: Components.Schemas.WatchDeliveryState
    let isLast: Bool

    private var visual: Visuals.StateVisual {
        Visuals.visual(for: step.state)
    }

    private var isCurrent: Bool {
        step.state == currentState
    }

    private var isReached: Bool {
        if currentState == .failed {
            return step.state == .failed
        }
        guard let currentIndex = WatchDeliveryStep.allCases.firstIndex(where: { $0.state == currentState }),
              let stepIndex = WatchDeliveryStep.allCases.firstIndex(of: step) else {
            return false
        }
        return stepIndex <= currentIndex && step.state != .failed
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isReached ? visual.color : Theme.Colors.surfaceElevated)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(isCurrent ? visual.color : Theme.Colors.borderMedium, lineWidth: isCurrent ? 2 : 1))
                    Text(visual.emoji)
                        .font(.system(size: 13))
                }

                if !isLast {
                    Rectangle()
                        .fill(isReached ? visual.color.opacity(0.6) : Theme.Colors.borderLight)
                        .frame(width: 2, height: 34)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(isReached ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                Text(step.subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : Theme.Spacing.md)
        }
    }
}

private enum Visuals {
    struct StateVisual {
        let emoji: String
        let color: Color
    }

    static func visual(for state: Components.Schemas.WatchDeliveryState) -> StateVisual {
        switch state {
        case .generated:
            return StateVisual(emoji: "✨", color: Theme.Colors.accentBlue)
        case .pushed:
            return StateVisual(emoji: "📡", color: Theme.Colors.accentBlue)
        case .fetchedByWidget:
            return StateVisual(emoji: "⌚️", color: Theme.Colors.readyModerate)
        case .confirmedOnDevice:
            return StateVisual(emoji: "✅", color: Theme.Colors.readyHigh)
        case .failed:
            return StateVisual(emoji: "⚠️", color: Theme.Colors.accentRed)
        }
    }
}

#Preview("Watch Delivery") {
    NavigationStack {
        WatchDeliveryView(
            workoutId: "fixture-watch-failed",
            workoutName: "Friday Strength",
            viewModel: WatchDeliveryViewModel(apiService: FixtureAPIService())
        )
    }
}
