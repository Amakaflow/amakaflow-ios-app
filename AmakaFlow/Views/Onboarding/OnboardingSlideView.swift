//
//  OnboardingSlideView.swift
//  AmakaFlow
//
//  AMA-1875 — renders a single OnboardingSlide.
//
//  Layout (full-screen):
//    ┌─────────────────────────────────┐
//    │              Skip ▶  (top-right)│
//    │                                 │
//    │      [ Lottie animation ]       │
//    │       (60% of vertical)         │
//    │                                 │
//    │      Headline (bold, 28pt)      │
//    │      Supporting caption         │
//    │      (15pt, dimmed)             │
//    │                                 │
//    │      ● ● ○ ○ ○  (page dots)     │
//    └─────────────────────────────────┘
//
//  Falls back gracefully if the Lottie .json asset is missing from
//  the bundle — shows a subtle placeholder so the headline + caption
//  are still readable during local development before assets land.
//

import SwiftUI
import Lottie

struct OnboardingSlideView: View {
    let slide: OnboardingSlide

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 24)

            lottieContainer
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .padding(.horizontal, 32)

            Spacer(minLength: 16)

            VStack(spacing: Theme.Spacing.md) {
                Text(slide.headline)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)

                Text(slide.caption)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 64)
        }
        .padding(.top, 32)
    }

    /// The Lottie surface. If the named animation isn't in the bundle
    /// (e.g., during early dev before assets are curated), falls back
    /// to a soft placeholder rectangle so the slide layout still
    /// renders.
    private var lottieContainer: some View {
        Group {
            if LottieAnimation.named(slide.lottieAssetName) != nil {
                LottieView(animation: .named(slide.lottieAssetName))
                    .playing(loopMode: .loop)
                    .resizable()
            } else {
                placeholderLottie
            }
        }
    }

    private var placeholderLottie: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Animation: \(slide.lottieAssetName)")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                }
            )
    }
}

#if DEBUG
struct OnboardingSlideView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingSlideView(slide: OnboardingSlide.v1Sequence[0])
            .preferredColorScheme(.dark)
    }
}
#endif
