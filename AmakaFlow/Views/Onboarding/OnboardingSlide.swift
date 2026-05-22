//
//  OnboardingSlide.swift
//  AmakaFlow
//
//  AMA-1875 / Production-Ready v1 gap "first-60-seconds UX rewrite".
//
//  Data model for a single animated-explainer slide. The onboarding
//  flow is a sequence of these, auto-advancing every ~8s with a
//  "Skip" affordance in the top-right.
//
//  Per the 2026-05-22 spike (docs/architecture/UX_FIRST_SESSION_PLAN.md):
//  "by demo. I meant something that shows the user how it works in
//  animation rather than a actual demo of the app." — David
//
//  Each slide pairs:
//    - A Lottie file from lottiefiles.com (free pack curated for the
//      feature being introduced)
//    - A one-line headline
//    - A one-line supporting caption
//

import Foundation

/// One screen in the animated-explainer onboarding flow.
struct OnboardingSlide: Identifiable, Equatable {
    let id: String
    /// File name (without extension) of the Lottie .json animation that
    /// lives in the app bundle. The flow auto-renders this via
    /// `LottieView(animation: .named(lottieAssetName))`.
    let lottieAssetName: String
    /// The one-line value claim that headlines the slide.
    let headline: String
    /// Single-line supporting context under the headline.
    let caption: String
}

extension OnboardingSlide {
    /// The v1 onboarding sequence — 5 slides covering AmakaFlow's
    /// headline features in ~45s of auto-advancing motion.
    ///
    /// Lottie asset names are placeholders until the .json files are
    /// curated from lottiefiles.com and dropped into the app bundle
    /// (tracked in AMA-1875 follow-up — Lottie asset curation).
    static let v1Sequence: [OnboardingSlide] = [
        OnboardingSlide(
            id: "ai-coach",
            lottieAssetName: "onboarding-ai-coach",  // TODO(AMA-1875): curate Lottie file
            headline: "Your AI coach plans every week",
            caption: "Tell us your goal. The AI builds a workout plan that adapts as you train."
        ),
        OnboardingSlide(
            id: "device-sync",
            lottieAssetName: "onboarding-device-sync",  // TODO(AMA-1875): curate Lottie file
            headline: "Connect Apple Watch, Garmin, or Strava",
            caption: "Workouts auto-log from your wearable. No manual entry."
        ),
        OnboardingSlide(
            id: "telegram-nudges",
            lottieAssetName: "onboarding-telegram",  // TODO(AMA-1875): curate Lottie file
            headline: "Get nudges in Telegram (optional)",
            caption: "Your coach sends a check-in when it matters. Off by default."
        ),
        OnboardingSlide(
            id: "weekly-progress",
            lottieAssetName: "onboarding-progress-ring",  // TODO(AMA-1875): curate Lottie file
            headline: "See your week fill with effort",
            caption: "Readiness, fatigue, and PRs in one view. The coach uses all of it."
        ),
        OnboardingSlide(
            id: "ready-to-start",
            lottieAssetName: "onboarding-start",  // TODO(AMA-1875): curate Lottie file
            headline: "Ready to train smarter?",
            caption: "Free during v1. Pricing comes later, after you've seen the value."
        ),
    ]
}
