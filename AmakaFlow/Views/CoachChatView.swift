//
//  CoachChatView.swift
//  AmakaFlow
//
//  AMA-2234 (E9-3): the single in-app coach UI shell.
//
//  This is the ONE coach entry point on iOS. It renders the approved Epic 9
//  design (`screens-e9-coach.jsx`: one-coach header, coach/user bubbles,
//  composer, and the loading / first-token / streaming / sent / failed /
//  text-only-degraded states) and routes every turn through the shared
//  mobile-BFF / Channel Gateway / coach core session path via
//  `CoachSessionStore` (`CoachViewModel`). iOS owns NO coach prompt stack,
//  memory store, policy, or tool list — the same path Telegram proved in
//  Epic 8. The "ONE COACH · iOS · TELEGRAM · WATCH" header encodes that
//  no-duplicate-brain invariant.
//
//  Voice capture/output is intentionally out of scope here (AMA-2231); the
//  mic affordance is a disabled placeholder. PendingActions (AMA-2230) and
//  first-token/streaming instrumentation (AMA-2233) layer on top of this
//  shell.
//

import SwiftUI

struct CoachChatView: View {
    @EnvironmentObject private var viewModel: CoachSessionStore
    @State private var inputText = ""
    @State private var showNewChatConfirmation = false
    @State private var route: CoachShellRoute?
    @FocusState private var isInputFocused: Bool

    /// ContentView owns the custom AFTabBar via a parent safeAreaInset. On the
    /// Coach surface that parent inset does not keep the composer above the tab
    /// bar, so reserve the tab-bar lane locally (kept even while focused to
    /// cover simulator/hardware-keyboard runs).
    private let tabBarClearance: CGFloat = 72

    private enum CoachShellRoute: Hashable {
        case readiness
        case fatigue
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CoachShellHeader(
                    isDegraded: viewModel.degradeMode?.isDegraded ?? false,
                    onNewChat: { requestNewChat() },
                    onReadiness: { route = .readiness },
                    onFatigue: { route = .fatigue }
                )

                if let mode = viewModel.degradeMode, mode.isDegraded {
                    CoachDegradedBanner(mode: mode)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.sm)
                }

                if viewModel.isLoadingMessages && viewModel.messages.isEmpty {
                    loadingHistory
                } else {
                    messagesSection
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
                    .padding(.bottom, tabBarClearance)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(item: $route) { destination in
                switch destination {
                case .readiness:
                    FatigueHistoryView()
                case .fatigue:
                    FatigueAdvisorView(viewModel: viewModel)
                }
            }
            .confirmationDialog("Start new chat?", isPresented: $showNewChatConfirmation) {
                Button("New Chat", role: .destructive) { viewModel.startNewChat() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will clear your current conversation.")
            }
            .task {
                await viewModel.loadMessagesIfNeeded()
                await viewModel.loadFatigueAdvice()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coach-chat-root")
            .onChange(of: viewModel.didRestoreConversation) { _, restored in
                guard restored else { return }
                UIAccessibility.post(notification: .announcement, argument: "Conversation restored")
            }
        }
    }

    private func requestNewChat() {
        if !viewModel.messages.isEmpty {
            showNewChatConfirmation = true
        }
    }

    // MARK: - Loading history (session restore)

    private var loadingHistory: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
            Text("Restoring your conversation…")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("coach-restoring")
    }

    // MARK: - Messages

    private var messagesSection: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if viewModel.messages.isEmpty {
                            coachWelcome
                        } else {
                            dayDivider

                            ForEach(viewModel.messages) { message in
                                CoachMessageRow(message: message) {
                                    viewModel.cancelStream()
                                } onSendMessage: { text in
                                    Task { await viewModel.sendMessage(text) }
                                }
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("coach-message-list")
                .onChange(of: viewModel.messages.count) { _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.isStreaming) { streaming in
                    if !streaming { scrollToBottom(proxy) }
                }
                .onChange(of: viewModel.scrollTrigger) { _ in
                    scrollToBottom(proxy, animated: false)
                }
            }

            if let info = viewModel.rateLimitInfo {
                rateLimitBanner(info)
            }

            if let restoreError = viewModel.restoreError {
                restoreErrorBanner(restoreError)
            }

            if let ctaError = viewModel.error, viewModel.rateLimitInfo == nil {
                ErrorToast(
                    actionTitle: "Couldn't reach the coach",
                    error: ctaError,
                    onRetry: ctaError.isRetryable ? {
                        Task { await viewModel.retryLastMessage() }
                    } : nil,
                    onReport: {
                        ErrorReporter.shared.report(
                            action: "coach_send_message",
                            error: ctaError,
                            endpoint: "/v1/chat/stream",
                            userId: PairingService.shared.userProfile?.id
                        )
                    },
                    onDismiss: {
                        viewModel.acknowledgeError()
                    }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private var dayDivider: some View {
        Text("TODAY")
            .font(Theme.Typography.label)
            .tracking(0.8)
            .foregroundColor(Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, Theme.Spacing.xs)
            .accessibilityHidden(true)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = viewModel.messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Welcome (empty state)

    private var coachWelcome: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 36))
                .foregroundColor(Theme.Colors.readyHigh)

            Text("Your AI Coach")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("One coach across iOS, Telegram, and Watch. Ask about training, recovery, or anything fitness.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: Theme.Spacing.sm) {
                quickPromptButton("How should I train this week?")
                quickPromptButton("Am I overtraining?")
                quickPromptButton("Suggest a recovery day workout")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private func quickPromptButton(_ text: String) -> some View {
        Button {
            Task { await viewModel.sendMessage(text) }
        } label: {
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.readyHigh)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.readyHigh.opacity(0.12))
                .cornerRadius(Theme.CornerRadius.lg)
        }
        .disabled(viewModel.isStreaming)
    }

    // MARK: - Rate limit / restore banners

    private func rateLimitBanner(_ info: RateLimitInfo) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(Theme.Colors.accentRed)
            Text("Rate limit reached (\(info.usage)/\(info.limit) messages)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.accentRed)
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.accentRed.opacity(0.1))
    }

    private func restoreErrorBanner(_ error: CoachSessionError) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.Colors.accentRed)
            Text(error.localizedDescription)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            if error.isRetryable {
                Button("Retry") {
                    Task { await viewModel.retryLoadMessages() }
                }
                .font(Theme.Typography.caption)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface)
    }

    // MARK: - Composer

    private var composer: some View {
        let isTextOnly = viewModel.degradeMode?.isDegraded ?? false
        return HStack(spacing: Theme.Spacing.sm) {
            TextField(isTextOnly ? "Message your coach…" : "Message…", text: $inputText)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.inputBackground)
                .cornerRadius(Theme.CornerRadius.lg)
                .focused($isInputFocused)
                .disabled(viewModel.isStreaming)
                .submitLabel(.send)
                .onSubmit(send)
                .accessibilityIdentifier("af_coach_input")

            // Voice is AMA-2231 — placeholder only. Disabled, and visibly
            // crossed-out while text-only/degraded to match the approved
            // text-fallback artboard.
            CoachMicPlaceholder(isTextOnly: isTextOnly)

            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(canSend ? Theme.Colors.primaryForeground : Theme.Colors.textTertiary)
                    .frame(width: 38, height: 38)
                    .background(canSend ? Theme.Colors.primary : Theme.Colors.inputBackground)
                    .clipShape(Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Send coach message")
            .accessibilityIdentifier("af_coach_send")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Theme.Colors.background
                .overlay(Rectangle().fill(Theme.Colors.borderLight).frame(height: 1), alignment: .top)
        )
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !viewModel.isStreaming else { return }
        inputText = ""
        Task { await viewModel.sendMessage(text) }
    }
}

// MARK: - One-coach header

/// The "one coach, any channel" header. The health dot turns amber when the
/// shared coach path is degraded; the mono subtitle encodes the no-duplicate-
/// brain invariant.
private struct CoachShellHeader: View {
    let isDegraded: Bool
    let onNewChat: () -> Void
    let onReadiness: () -> Void
    let onFatigue: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.readyHigh.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Coach")
                        .font(Theme.Typography.afH2)
                        .foregroundColor(Theme.Colors.textPrimary)
                    CoachHealthDot(isDegraded: isDegraded)
                }
                Text("ONE COACH · iOS · TELEGRAM · WATCH")
                    .font(Font.geistMono(9.5, .medium))
                    .tracking(0.2)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("coach-one-brain-indicator")
            }

            Spacer()

            Menu {
                Button {
                    onNewChat()
                } label: {
                    Label("New chat", systemImage: "plus.bubble")
                }
                Button {
                    onReadiness()
                } label: {
                    Label("Readiness history", systemImage: "chart.line.uptrend.xyaxis")
                }
                Button {
                    onFatigue()
                } label: {
                    Label("Fatigue advisor", systemImage: "heart.text.square")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Coach options")
            .accessibilityIdentifier("coach-options-menu")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
        .overlay(Rectangle().fill(Theme.Colors.borderLight).frame(height: 1), alignment: .bottom)
    }
}

private struct CoachHealthDot: View {
    let isDegraded: Bool

    private var color: Color {
        isDegraded ? Theme.Colors.readyModerate : Theme.Colors.readyHigh
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay(Circle().stroke(color.opacity(0.30), lineWidth: 3))
            .accessibilityElement()
            .accessibilityLabel(isDegraded ? "Coach degraded" : "Coach healthy")
            .accessibilityIdentifier("coach-health-dot")
    }
}

// MARK: - Degraded banner (text-only fallback)

/// Text-only / degraded banner. Surfaces an honest reason (manual / mock /
/// skip / data_gap) so a missing BFF / gateway / LLM / Redis / Supabase
/// dependency never becomes a blank screen, crash, or silent success.
private struct CoachDegradedBanner: View {
    let mode: CoachDegradeMode

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.readyModerate)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                if let title = mode.bannerTitle {
                    Text(title)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                if let detail = mode.bannerDetail {
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.readyModerate.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                .stroke(Theme.Colors.readyModerate.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach-degraded-banner")
        .accessibilityValue(mode.contractToken)
    }
}

// MARK: - Mic placeholder (voice = AMA-2231)

private struct CoachMicPlaceholder: View {
    let isTextOnly: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.inputBackground)
                .overlay(Circle().stroke(Theme.Colors.borderLight, lineWidth: 1))
                .frame(width: 38, height: 38)
            Image(systemName: "mic")
                .font(.system(size: 15))
                .foregroundColor(Theme.Colors.textTertiary)
            if isTextOnly {
                Rectangle()
                    .fill(Theme.Colors.textSecondary)
                    .frame(width: 24, height: 1.5)
                    .rotationEffect(.degrees(-45))
            }
        }
        .opacity(isTextOnly ? 0.5 : 0.7)
        .accessibilityLabel(isTextOnly ? "Voice unavailable" : "Voice coming soon")
        .accessibilityIdentifier("coach-mic-placeholder")
        .allowsHitTesting(false)
    }
}

// MARK: - Message row

/// One conversation row. Uses `@ObservedObject` so SwiftUI re-renders as the
/// streamed assistant message's `content` / `isStreaming` change during a turn.
struct CoachMessageRow: View {
    @ObservedObject var message: ChatMessage
    let onStop: () -> Void
    let onSendMessage: (String) -> Void

    private var isUser: Bool { message.role == .user }
    private var isThinking: Bool { message.role == .assistant && message.isStreaming && message.content.isEmpty }
    private var isStreamingText: Bool { message.role == .assistant && message.isStreaming && !message.content.isEmpty }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: Theme.Spacing.xs) {
            if isThinking {
                CoachThinkingBubble()
            } else {
                bubble
            }

            if !message.toolCalls.isEmpty {
                ForEach(message.toolCalls) { toolCall in
                    ToolCallCard(toolCall: toolCall)
                }
            }

            if let workout = message.workoutData {
                WorkoutPreviewCard(workout: workout)
            }

            if isStreamingText {
                streamingFooter
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var bubble: some View {
        let shape = BubbleShape(tightCorner: isUser ? .bottomTrailing : .bottomLeading)
        return bubbleText
            .font(Theme.Typography.body)
            .foregroundColor(isUser ? Theme.Colors.primaryForeground : Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isUser ? Theme.Colors.primary : Theme.Colors.surfaceElevated)
            .clipShape(shape)
            .overlay {
                if !isUser {
                    shape.stroke(Theme.Colors.borderLight, lineWidth: 1)
                }
            }
            .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private var bubbleText: some View {
        if isUser {
            Text(message.content)
        } else if isStreamingText {
            // Plain text during streaming + a blinking caret; avoids reparsing
            // markdown on every delta.
            (Text(message.content) + Text(" ▍"))
        } else if let attributed = try? AttributedString(markdown: message.content) {
            Text(attributed)
        } else {
            Text(message.content)
        }
    }

    private var streamingFooter: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.Colors.readyHigh)
                    .frame(width: 5, height: 5)
                Text("STREAMING")
                    .font(Font.geistMono(9, .medium))
                    .foregroundColor(Theme.Colors.readyHigh)
            }
            Rectangle()
                .fill(Theme.Colors.borderLight)
                .frame(width: 1, height: 10)
            Button(action: onStop) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                    Text("Stop")
                        .font(Theme.Typography.caption)
                }
                .foregroundColor(Theme.Colors.textSecondary)
            }
            .accessibilityIdentifier("coach-stop-streaming")
        }
        .padding(.leading, Theme.Spacing.xs)
        .padding(.top, 2)
    }
}

/// First-token waiting state: animated dots + a step line. Maps the approved
/// "thinking" artboard. Detailed first-token instrumentation is AMA-2233.
private struct CoachThinkingBubble: View {
    @State private var animating = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.Colors.textSecondary)
                        .frame(width: 6, height: 6)
                        .opacity(animating ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.55)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.18),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .clipShape(BubbleShape(tightCorner: .bottomLeading))

            Text("Reading your recent sessions…")
                .font(Font.geistMono(9.5, .regular))
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.leading, Theme.Spacing.xs)
        }
        .onAppear { animating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach is thinking")
        .accessibilityIdentifier("coach-thinking")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Asymmetric chat-bubble corner radius (one tight corner like the design).
private struct BubbleShape: Shape {
    enum Corner { case bottomLeading, bottomTrailing }
    let tightCorner: Corner
    var radius: CGFloat = Theme.CornerRadius.lg
    var tight: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let tl = radius
        let tr = radius
        let bl = tightCorner == .bottomLeading ? tight : radius
        let br = tightCorner == .bottomTrailing ? tight : radius

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Fatigue Advisor View

struct FatigueAdvisorView: View {
    @ObservedObject var viewModel: CoachViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if viewModel.isLoadingAdvice {
                    ProgressView("Analyzing your fatigue levels...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xl)
                } else if let advice = viewModel.fatigueAdvice {
                    HStack {
                        Text("Fatigue Level")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text(advice.level.rawValue.capitalized)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(advice.level.displayColor)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(advice.level.displayColor.opacity(0.15))
                            .cornerRadius(Theme.CornerRadius.md)
                    }

                    Text(advice.message)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Recommendations")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        ForEach(advice.recommendations, id: \.self) { rec in
                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.Colors.accentGreen)
                                    .font(.system(size: 14))
                                Text(rec)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }

                    if let restDays = advice.suggestedRestDays {
                        HStack {
                            Image(systemName: "bed.double.fill")
                                .foregroundColor(Theme.Colors.accentBlue)
                            Text("Suggested rest days: \(restDays)")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.surface)
                        .cornerRadius(Theme.CornerRadius.lg)
                    }
                } else {
                    Text("No fatigue data available yet. Complete some workouts first.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xl)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Fatigue Advisor")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.fatigueAdvice == nil {
                await viewModel.loadFatigueAdvice()
            }
        }
    }
}

#Preview {
    CoachChatView()
        .environmentObject(CoachSessionStore())
        .preferredColorScheme(.dark)
}
