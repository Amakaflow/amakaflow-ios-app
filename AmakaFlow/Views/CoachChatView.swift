//
//  CoachChatView.swift
//  AmakaFlow
//
//  AI coach chat interface with SSE streaming (AMA-1410)
//

import SwiftUI

struct CoachChatView: View {
    @StateObject private var viewModel = CoachViewModel()
    @State private var inputText = ""
    @State private var showNewChatConfirmation = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fatigue advisor banner
                if let advice = viewModel.fatigueAdvice {
                    fatigueBanner(advice)
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            if viewModel.messages.isEmpty {
                                coachWelcome
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(message: message) { text in
                                    Task { await viewModel.sendMessage(text) }
                                }
                                .id(message.id)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                    }
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

                // Stage indicator (visible during streaming)
                if viewModel.isStreaming, viewModel.currentStage != nil || !viewModel.completedStages.isEmpty {
                    StageIndicator(
                        completedStages: viewModel.completedStages,
                        currentStage: viewModel.currentStage
                    )
                }

                // Rate limit banner
                if let info = viewModel.rateLimitInfo {
                    rateLimitBanner(info)
                }

                // Error message
                if let error = viewModel.errorMessage, viewModel.rateLimitInfo == nil {
                    Text(error)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.accentRed)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xs)
                }

                // Input bar
                inputBar
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if !viewModel.messages.isEmpty {
                            showNewChatConfirmation = true
                        }
                    } label: {
                        Image(systemName: "plus.bubble")
                            .foregroundColor(Theme.Colors.accentBlue)
                            .accessibilityLabel("Start new chat")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: FatigueAdvisorView(viewModel: viewModel)) {
                        Image(systemName: "heart.text.square")
                            .foregroundColor(Theme.Colors.accentBlue)
                            .accessibilityLabel("Open fatigue advisor")
                    }
                }
            }
            .confirmationDialog("Start new chat?", isPresented: $showNewChatConfirmation) {
                Button("New Chat", role: .destructive) { viewModel.startNewChat() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will clear your current conversation.")
            }
            .task {
                await viewModel.loadFatigueAdvice()
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if let last = viewModel.messages.last {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Welcome

    private var coachWelcome: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.accentBlue)

            Text("Your AI Coach")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Ask about training plans, recovery, or anything fitness related.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: Theme.Spacing.sm) {
                quickPromptButton("How should I train this week?")
                quickPromptButton("Am I overtraining?")
                quickPromptButton("Suggest a recovery day workout")
            }
        }
        .padding(Theme.Spacing.xl)
    }

    private func quickPromptButton(_ text: String) -> some View {
        Button {
            Task { await viewModel.sendMessage(text) }
        } label: {
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.accentBlue)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.accentBlue.opacity(0.1))
                .cornerRadius(Theme.CornerRadius.lg)
        }
        .disabled(viewModel.isStreaming)
    }

    // MARK: - Fatigue Banner

    private func fatigueBanner(_ advice: FatigueAdvice) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(advice.level.displayColor)
                .frame(width: 10, height: 10)
            Text(advice.message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface)
    }

    // MARK: - Rate Limit

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

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Ask your coach...", text: $inputText)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.lg)
                .focused($isInputFocused)
                .disabled(viewModel.isStreaming)

            Button {
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                inputText = ""
                Task { await viewModel.sendMessage(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(
                        inputText.isEmpty || viewModel.isStreaming
                        ? Theme.Colors.textTertiary
                        : Theme.Colors.accentBlue
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }
}

// MARK: - Message Bubble View
// Uses @ObservedObject so SwiftUI re-renders whenever ChatMessage @Published properties
// change during streaming (content, toolCalls, isStreaming, workoutData, etc.).

struct MessageBubbleView: View {
    @ObservedObject var message: ChatMessage
    let onSendMessage: (String) -> Void

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer() }

            if message.role == .assistant {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.accentBlue)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.accentBlue.opacity(0.15))
                    .cornerRadius(16)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.xs) {
                // Message content
                if message.role == .assistant {
                    assistantBubbleContent
                } else {
                    Text(message.content)
                        .font(Theme.Typography.body)
                        .foregroundColor(.white)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(Theme.CornerRadius.lg)
                }

                // Tool calls
                if !message.toolCalls.isEmpty {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(message.toolCalls) { toolCall in
                            ToolCallCard(toolCall: toolCall)
                        }
                    }
                }

                // Workout preview
                if let workout = message.workoutData {
                    WorkoutPreviewCard(workout: workout)
                }

                // Suggestion chips — legacy fields populated by old non-streaming endpoint.
                // SSE mode does not send suggestions; the if-let guard gracefully skips rendering.
                if message.role == .assistant, let suggestions = message.suggestions, !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(suggestions, id: \.stableId) { suggestion in
                                sourceChip(suggestion)
                            }
                        }
                    }
                }

                // Action items — legacy fields, see note above.
                if message.role == .assistant, let actions = message.actionItems, !actions.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(actions, id: \.stableId) { item in
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.Colors.accentBlue)
                                Text(item.title)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.accentBlue)
                            }
                        }
                    }
                }

                Text(message.timestamp, style: .time)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    @ViewBuilder
    private var assistantBubbleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !message.content.isEmpty {
                if message.isStreaming {
                    // Plain text during streaming to avoid reparsing markdown on every delta
                    Text(message.content)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.md)
                } else if let attributed = try? AttributedString(markdown: message.content) {
                    Text(attributed)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.md)
                } else {
                    Text(message.content)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.md)
                }
            }

            if message.isStreaming && message.content.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    TypingIndicator()
                    Text("Coach is thinking...")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.md)
            }
        }
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.lg)
    }

    private func sourceChip(_ suggestion: CoachSuggestion) -> some View {
        Button {
            onSendMessage(suggestion.text)
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: chipIcon(suggestion.type))
                    .font(.system(size: 10))
                Text(suggestion.text)
                    .font(Theme.Typography.footnote)
                    .lineLimit(1)
            }
            .foregroundColor(Theme.Colors.accentBlue)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.accentBlue.opacity(0.1))
            .cornerRadius(Theme.CornerRadius.md)
        }
    }

    private func chipIcon(_ type: SuggestionType?) -> String {
        switch type {
        case .workout: return "figure.run"
        case .recovery: return "bed.double.fill"
        case .nutrition: return "fork.knife"
        case .general, .none: return "lightbulb.fill"
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.Colors.accentBlue)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach is typing")
        .accessibilityAddTraits(.updatesFrequently)
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
        .preferredColorScheme(.dark)
}
