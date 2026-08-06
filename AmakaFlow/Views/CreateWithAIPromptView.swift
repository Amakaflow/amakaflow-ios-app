//
//  CreateWithAIPromptView.swift
//  AmakaFlow
//
//  Daily Driver compose entry point for creating an AI workout.
//

import SwiftUI

struct CreateWithAIPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SuggestWorkoutViewModel
    @State private var ask = ""
    @State private var durationMinutes: Int?
    @State private var attached = Set<CreateWithAIContextChip>()
    @State private var isShowingSuggestion = false
    /// Prevents Edit-ask return from re-running discovery and silently
    /// re-attaching chips the user already detached.
    @State private var hasLoadedContext = false

    private let onSaved: () -> Void
    private let contextAPI: APIServiceProviding
    private let durationOptions = [30, 45, 60]

    init(
        viewModel: SuggestWorkoutViewModel? = nil,
        contextAPI: APIServiceProviding? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? SuggestWorkoutViewModel())
        self.contextAPI = contextAPI ?? AppDependencies.current.apiService
        self.onSaved = onSaved
    }

    var body: some View {
        if isShowingSuggestion {
            SuggestWorkoutView(
                viewModel: viewModel,
                mode: .createWithAI,
                onWorkoutStarted: onSaved
            ) { isShowingSuggestion = false }
        } else {
            promptForm
        }
    }

    private var promptForm: some View {
        NavigationStack {
            ZStack {
                DailyDriver.screenBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        CreateWithAIAskField(ask: $ask, onMicTap: showMicUnavailable)
                        CreateWithAIStartersGrid(ask: $ask)
                        contextChips
                        timeBox

                        Button {
                            generateWorkout()
                        } label: {
                            HStack(spacing: 7) {
                                Text("✦")
                                Text("Draft it")
                            }
                            .ddDisplayText(16, weight: .bold)
                            .foregroundColor(DailyDriver.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(DailyDriver.lime)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(trimmedAsk.isEmpty)
                        .opacity(trimmedAsk.isEmpty ? 0.35 : 1)
                        .accessibilityIdentifier("create_with_ai_draft_it")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DailyDriver.foreground)
                            .frame(width: 36, height: 36)
                            .background(DailyDriver.card2)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .toolbarBackground(DailyDriver.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await loadAvailableContext() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(CreateWithAICopy.composeTitle)
                .ddDisplayText(31, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
            Text(CreateWithAICopy.composeSubtitle)
                .font(.system(size: 14))
                .foregroundColor(DailyDriver.foregroundMuted)
        }
    }

    private var contextChips: some View {
        VStack(alignment: .leading, spacing: 11) {
            if !attached.isEmpty {
                sectionLabel("THE COACH ALREADY KNOWS")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CreateWithAIContextChip.allCases.filter { attached.contains($0) }) { chip in
                            contextChipButton(chip)
                        }
                    }
                }
            }
        }
    }

    private func contextChipButton(_ chip: CreateWithAIContextChip) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                _ = attached.remove(chip)
                // Freeze discovery so an in-flight load cannot re-attach.
                hasLoadedContext = true
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: chip.icon)
                Text(chip.label)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(DailyDriver.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(DailyDriver.card2)
            .overlay(Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(chip.label)")
    }

    private var timeBox: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("TIME BOX")
            HStack(spacing: 8) {
                durationButton(label: "Any", minutes: nil)
                ForEach(durationOptions, id: \.self) { minutes in
                    durationButton(label: "\(minutes)", minutes: minutes)
                }
            }
            .accessibilityIdentifier("create_with_ai_duration")
        }
    }

    private func durationButton(label: String, minutes: Int?) -> some View {
        let selected = durationMinutes == minutes
        return Button {
            durationMinutes = minutes
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(selected ? DailyDriver.ink : DailyDriver.foregroundMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selected ? DailyDriver.lime : DailyDriver.card)
                .overlay(Capsule().stroke(selected ? DailyDriver.lime : DailyDriver.border, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.25)
            .foregroundColor(DailyDriver.foregroundDim)
    }

    private var trimmedAsk: String {
        ask.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateWorkout() {
        let notes = CreateWithAIPromptBuilder.composeNotes(ask: ask)
        guard !notes.isEmpty else { return }
        hasLoadedContext = true
        isShowingSuggestion = true
        viewModel.requestSuggestionFromPrompt(
            notes: notes,
            durationMinutes: durationMinutes,
            focusMuscleGroups: nil,
            includeContext: CreateWithAIPromptBuilder.includeContext(attached: attached)
        )
    }

    @MainActor
    private func loadAvailableContext() async {
        guard !hasLoadedContext else { return }

        // Returning via Edit ask: prefer the flags that produced the draft so
        // detached chips stay detached.
        if let flags = viewModel.currentIncludeContext {
            attached = CreateWithAIPromptBuilder.chips(from: flags)
            hasLoadedContext = true
            return
        }

        let profileResult: Result<Components.Schemas.CoachingProfile?, Error>
        do {
            profileResult = .success(try await contextAPI.getCoachingProfile())
        } catch {
            profileResult = .failure(error)
        }

        let memoriesResult: Result<[CoachMemory], Error>
        do {
            memoriesResult = .success(try await contextAPI.fetchCoachMemories())
        } catch {
            memoriesResult = .failure(error)
        }

        // User may have detached a chip or tapped Draft while probes were in flight.
        guard !hasLoadedContext else { return }

        let discovery = CreateWithAIPromptBuilder.discoverContext(
            hasActiveGym: DDActiveGymStore.load() != nil,
            profile: profileResult,
            memories: memoriesResult
        )
        attached = discovery.attached
        hasLoadedContext = true
    }

    private func showMicUnavailable() {
        DDToastCenter.shared.success(
            "Voice input isn’t available yet — type your ask for now."
        )
    }
}

#if DEBUG
#Preview {
    CreateWithAIPromptView()
        .environmentObject(WorkoutsViewModel())
}
#endif
