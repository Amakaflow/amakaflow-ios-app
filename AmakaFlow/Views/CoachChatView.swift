//
//  CoachChatView.swift
//  AmakaFlow
//
//  AI coach chat interface (AMA-1147)
//

import SwiftUI

struct CoachChatView: View {
    @StateObject private var viewModel = CoachViewModel()
    @State private var inputText = ""
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
                                chatBubble(message)
                                    .id(message.id)
                            }

                            if viewModel.isLoading {
                                HStack {
                                    ProgressView()
                                        .tint(Theme.Colors.accentBlue)
                                    Text("Coach is thinking...")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                    Spacer()
                                }
                                .padding(.horizontal, Theme.Spacing.lg)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let last = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Rate limit indicator (AMA-1133)
                if viewModel.rateLimitHit {
                    rateLimitBanner
                } else if viewModel.isNearRateLimit {
                    rateLimitWarning
                }

                // Error message
                if let error = viewModel.errorMessage, !viewModel.rateLimitHit {
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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: FatigueAdvisorView(viewModel: viewModel)) {
                        Image(systemName: "heart.text.square")
                            .foregroundColor(Theme.Colors.accentBlue)
                    }
                }
            }
            .task {
                await viewModel.loadFatigueAdvice()
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

            // Quick prompts
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
    }

    // MARK: - Chat Bubble (AMA-1133 enhanced)

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer() }

            if message.role == .assistant {
                // Coach avatar
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.accentBlue)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.accentBlue.opacity(0.15))
                    .cornerRadius(16)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.xs) {
                Text(message.content)
                    .font(Theme.Typography.body)
                    .foregroundColor(message.role == .user ? .white : Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.md)
                    .background(message.role == .user ? Theme.Colors.accentBlue : Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.lg)

                // Source chips for assistant messages (AMA-1133)
                if message.role == .assistant, let suggestions = message.suggestions, !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(suggestions, id: \.stableId) { suggestion in
                                sourceChip(suggestion)
                            }
                        }
                    }
                }

                // Action items for assistant messages (AMA-1133)
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

    private func sourceChip(_ suggestion: CoachSuggestion) -> some View {
        Button {
            Task { await viewModel.sendMessage(suggestion.text) }
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

    // MARK: - Fatigue Banner

    private func fatigueBanner(_ advice: FatigueAdvice) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(fatigueColor(advice.level))
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

    private func fatigueColor(_ level: FatigueLevel) -> Color {
        switch level {
        case .low: return Theme.Colors.accentGreen
        case .moderate: return Theme.Colors.accentOrange
        case .high, .critical: return Theme.Colors.accentRed
        }
    }

    // MARK: - Rate Limit Indicators (AMA-1133)

    private var rateLimitBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(Theme.Colors.accentRed)
            Text("Rate limit reached. Please wait before sending more messages.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.accentRed)
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.accentRed.opacity(0.1))
    }

    private var rateLimitWarning: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(Theme.Colors.accentOrange)
                .font(.system(size: 12))
            Text("Approaching message limit (\(viewModel.messageCount)/\(CoachViewModel.rateLimitWarningThreshold))")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.accentOrange)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xs)
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

            Button {
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                inputText = ""
                Task { await viewModel.sendMessage(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(inputText.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.accentBlue)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
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
                    // Level indicator
                    HStack {
                        Text("Fatigue Level")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text(advice.level.rawValue.capitalized)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(fatigueColor(advice.level))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(fatigueColor(advice.level).opacity(0.15))
                            .cornerRadius(Theme.CornerRadius.md)
                    }

                    Text(advice.message)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)

                    // Recommendations
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

    private func fatigueColor(_ level: FatigueLevel) -> Color {
        switch level {
        case .low: return Theme.Colors.accentGreen
        case .moderate: return Theme.Colors.accentOrange
        case .high, .critical: return Theme.Colors.accentRed
        }
    }
}

#Preview {
    CoachChatView()
        .preferredColorScheme(.dark)
}
