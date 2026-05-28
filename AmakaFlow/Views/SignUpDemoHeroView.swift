//
//  SignUpDemoHeroView.swift
//  AmakaFlow
//
//  AMA-2007: purpose-built mock SwiftUI sign-up hero animation.
//

import SwiftUI

struct SignUpDemoPlayback: Equatable {
    enum Mode: Equatable {
        case animatedLoop
        case staticFirstFrame
    }

    let mode: Mode

    static func mode(reduceMotion: Bool) -> SignUpDemoPlayback {
        SignUpDemoPlayback(mode: reduceMotion ? .staticFirstFrame : .animatedLoop)
    }
}

struct SignUpDemoTimeline {
    enum Phase: Int, CaseIterable, Equatable {
        case suggest
        case accept
        case telegram
        case reset
    }

    static let loopDuration: TimeInterval = 8.8

    static func presentation(at elapsed: TimeInterval) -> SignUpDemoPresentation {
        let normalized = elapsed.truncatingRemainder(dividingBy: loopDuration)

        switch normalized {
        case 0..<2.4:
            return SignUpDemoPresentation(phase: .suggest, progress: normalized / 2.4)
        case 2.4..<4.6:
            return SignUpDemoPresentation(phase: .accept, progress: (normalized - 2.4) / 2.2)
        case 4.6..<7.6:
            return SignUpDemoPresentation(phase: .telegram, progress: (normalized - 4.6) / 3.0)
        default:
            return SignUpDemoPresentation(phase: .reset, progress: (normalized - 7.6) / 1.2)
        }
    }
}

struct SignUpDemoPresentation: Equatable {
    let phase: SignUpDemoTimeline.Phase
    /// Normalized 0...1 progress within the current phase.
    let progress: TimeInterval

    static let firstFrame = SignUpDemoPresentation(phase: .suggest, progress: 0)

    var acceptedOpacity: Double {
        switch phase {
        case .suggest: return 0
        case .accept: return min(1, progress * 1.8)
        case .telegram: return 1
        case .reset: return max(0, 1 - progress * 1.6)
        }
    }

    var workoutCardOpacity: Double {
        switch phase {
        case .suggest, .accept: return 1
        case .telegram: return max(0.24, 1 - progress * 0.76)
        case .reset: return max(0, 0.24 - progress * 0.24)
        }
    }

    var workoutCardOffsetX: CGFloat {
        guard phase == .telegram else { return 0 }
        return CGFloat(progress) * 58
    }

    var workoutCardOffsetY: CGFloat {
        guard phase == .telegram else { return 0 }
        return CGFloat(progress) * 86
    }

    var telegramOpacity: Double {
        switch phase {
        case .suggest: return 0
        case .accept: return max(0, (progress - 0.62) * 2.6)
        case .telegram: return 1
        case .reset: return max(0, 1 - progress * 1.8)
        }
    }

    var telegramScale: CGFloat {
        0.92 + CGFloat(telegramOpacity) * 0.08
    }

    var screenWashOpacity: Double {
        phase == .reset ? min(1, progress * 1.5) : 0
    }
}

struct SignUpDemoHeroView: View {
    let playback: SignUpDemoPlayback
    @State private var startDate = Date()

    var body: some View {
        ZStack {
            softGlow

            switch playback.mode {
            case .staticFirstFrame:
                phoneFrame(presentation: .firstFrame)
                    .accessibilityIdentifier("signup_demo_static")
            case .animatedLoop:
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let elapsed = context.date.timeIntervalSince(startDate)
                    phoneFrame(presentation: SignUpDemoTimeline.presentation(at: elapsed))
                }
                .accessibilityIdentifier("signup_demo_animated")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Animated preview of AmakaFlow suggesting and sending today's session")
    }

    private var softGlow: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.readyHigh.opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 46)
                .offset(x: -68, y: -52)
            Circle()
                .fill(Theme.Colors.accentBlue.opacity(0.12))
                .frame(width: 210, height: 210)
                .blur(radius: 42)
                .offset(x: 80, y: 64)
        }
        .accessibilityHidden(true)
    }

    private func phoneFrame(presentation: SignUpDemoPresentation) -> some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.74, 268)
            let height = min(proxy.size.height * 0.94, 510)

            ZStack {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(Color(light: Color(hex: "11131A"), dark: Color(hex: "050506")))
                    .shadow(color: .black.opacity(0.22), radius: 26, y: 18)

                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Theme.Colors.background)
                    .padding(8)

                VStack(spacing: 12) {
                    Capsule()
                        .fill(Theme.Colors.textPrimary.opacity(0.16))
                        .frame(width: 64, height: 5)
                        .padding(.top, 14)
                        .accessibilityHidden(true)

                    demoScreen(presentation: presentation)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 20)
                }
                .padding(8)
            }
            .frame(width: width, height: height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func demoScreen(presentation: SignUpDemoPresentation) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today")
                            .font(Font.geist(20, .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("Readiness 82 · coach adjusted")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    AFDot(level: .high)
                }

                SignUpMockSuggestionCard(acceptedOpacity: presentation.acceptedOpacity)
                    .opacity(presentation.workoutCardOpacity)
                    .offset(
                        x: presentation.workoutCardOffsetX,
                        y: presentation.workoutCardOffsetY
                    )

                Spacer(minLength: 0)
            }

            SignUpMockTelegramBubble()
                .opacity(presentation.telegramOpacity)
                .scaleEffect(presentation.telegramScale, anchor: .bottomTrailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.bottom, 18)

            Theme.Colors.background
                .opacity(presentation.screenWashOpacity)
        }
        .padding(16)
        .background(Theme.Colors.backgroundSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
    }
}

private struct SignUpMockSuggestionCard: View {
    let acceptedOpacity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.Colors.readyHigh)
                Text("Coach suggests")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text("32 min")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Text("Strength + tempo run")
                .font(Font.geist(17, .semibold))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                SignUpMockChip(text: "Lower body")
                SignUpMockChip(text: "Z2 finish")
            }

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.Colors.readyHigh)
                    .frame(height: 38)
                    .overlay {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("Accept")
                        }
                        .font(Font.geist(13, .semibold))
                        .foregroundColor(.white)
                    }
                Circle()
                    .fill(Theme.Colors.inputBackground)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
            }
        }
        .padding(14)
        .background(Theme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                Text("Accepted")
            }
            .font(Font.geist(11, .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Theme.Colors.readyHigh)
            .clipShape(Capsule())
            .padding(10)
            .opacity(acceptedOpacity)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
    }
}

private struct SignUpMockTelegramBubble: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Circle()
                .fill(Theme.Colors.accentBlue)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text("Telegram")
                    .font(Theme.Typography.label)
                    .foregroundColor(.white.opacity(0.72))
                Text("Today's session ready")
                    .font(Font.geist(13, .semibold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.Colors.accentBlue)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct SignUpMockChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Font.geistMono(10, .medium))
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.Colors.inputBackground)
            .clipShape(Capsule())
    }
}

#if DEBUG
#Preview("Sign-up demo — animated") {
    SignUpDemoHeroView(playback: .mode(reduceMotion: false))
        .frame(height: 520)
        .padding()
        .background(Theme.Colors.background)
}

#Preview("Sign-up demo — static reduced motion") {
    SignUpDemoHeroView(playback: .mode(reduceMotion: true))
        .frame(height: 520)
        .padding()
        .background(Theme.Colors.background)
}
#endif
