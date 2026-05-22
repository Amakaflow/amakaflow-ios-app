//
//  OnboardingFlowView.swift
//  AmakaFlow
//
//  AMA-1875 — top-level container for the animated-explainer
//  onboarding sequence shown on first launch.
//
//  Behaviour:
//   - Renders OnboardingSlide.v1Sequence as a horizontal paging view
//   - Auto-advances every `autoAdvanceSeconds` (default 8s); user can
//     also swipe manually
//   - Top-right "Skip" jumps straight to the final CTA slide
//   - Bottom shows page indicators
//   - On the last slide, the CTA changes from "Next" to "Get started" —
//     tapping that calls `onComplete()`, which the host wires to
//     "dismiss + mark onboarding-shown + show Clerk sign-in" in
//     AmakaFlowCompanionApp.
//

import SwiftUI

struct OnboardingFlowView: View {
    /// Called when the user finishes the flow (last slide + "Get started",
    /// OR taps "Skip"). The host marks onboarding complete + advances
    /// to the auth surface.
    var onComplete: () -> Void

    /// Source of truth for which slide is showing. State only lives in
    /// this view — when `onComplete` fires the host disposes of us.
    @State private var currentIndex: Int = 0

    /// Auto-advance timer. Suspended when the user is mid-swipe; that
    /// is handled by `TabView.onChange(of: currentIndex)` resetting
    /// the timer below.
    @State private var autoAdvanceTask: Task<Void, Never>? = nil

    /// Seconds per slide. Tuned for ~45s total over 5 slides.
    let autoAdvanceSeconds: TimeInterval

    private let slides: [OnboardingSlide]

    init(
        slides: [OnboardingSlide] = OnboardingSlide.v1Sequence,
        autoAdvanceSeconds: TimeInterval = 8.0,
        onComplete: @escaping () -> Void
    ) {
        self.slides = slides
        self.autoAdvanceSeconds = autoAdvanceSeconds
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(slides.enumerated()), id: \.offset) { offset, slide in
                    OnboardingSlideView(slide: slide)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)

            VStack {
                skipBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .onAppear { startAutoAdvance() }
        .onDisappear { autoAdvanceTask?.cancel() }
        .onChange(of: currentIndex) { _ in
            // Manual swipe restarts the timer for the new slide.
            startAutoAdvance()
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var skipBar: some View {
        HStack {
            Spacer()
            Button {
                complete()
            } label: {
                Text("Skip")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
            .accessibilityLabel("Skip onboarding")
        }
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            pageDots
            primaryCTA
        }
        .padding(.bottom, 32)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<slides.count, id: \.self) { i in
                Circle()
                    .fill(i == currentIndex ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
        .accessibilityHidden(true)  // Skip / Next CTAs convey the same info
    }

    private var primaryCTA: some View {
        Button {
            advance()
        } label: {
            Text(isLastSlide ? "Get started" : "Next")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor)
                )
                .foregroundColor(.white)
                .contentTransition(.opacity)
        }
        .accessibilityLabel(isLastSlide ? "Get started" : "Next slide")
    }

    // MARK: - Helpers

    private var isLastSlide: Bool {
        currentIndex == slides.count - 1
    }

    private func advance() {
        if isLastSlide {
            complete()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentIndex += 1
            }
        }
    }

    private func complete() {
        autoAdvanceTask?.cancel()
        onComplete()
    }

    private func startAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { [autoAdvanceSeconds] in
            try? await Task.sleep(nanoseconds: UInt64(autoAdvanceSeconds * 1_000_000_000))
            await MainActor.run {
                guard !Task.isCancelled else { return }
                advance()
            }
        }
    }
}

#if DEBUG
struct OnboardingFlowView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingFlowView(onComplete: {})
            .preferredColorScheme(.dark)
    }
}
#endif
