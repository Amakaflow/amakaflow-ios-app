//
//  DDActivePlayerView.swift
//  AmakaFlow
//
//  Daily Driver phone player — dd-player-dark.png
//

import SwiftUI

struct DDActivePlayerView: View {
    @ObservedObject var engine: WorkoutEngine
    @ObservedObject var watchManager: WatchConnectivityManager
    var onEnd: () -> Void

    private var totalSteps: Int { engine.totalSteps }
    private var currentIndex: Int { engine.currentStepIndex }

    var body: some View {
        VStack(spacing: 0) {
            statsStage
            controlDock
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Stats stage

    private var statsStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onEnd) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DailyDriver.foreground)
                        .frame(width: 40, height: 40)
                        .background(DailyDriver.card2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ama1842.endWorkout.button")

                Spacer(minLength: 0)

                Text(sessionMeta)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 0) {
                Text("BLOCK \(currentIndex + 1) OF \(max(totalSteps, 1))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.top, 26)

                Text(engine.currentStep?.displayLabel ?? engine.workout?.name ?? "Exercise")
                    .ddDisplayText(30, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                    .padding(.top, 6)

                if let details = stepDetailLine {
                    Text(details)
                        .ddDisplayText(16, weight: .semibold)
                        .foregroundColor(DailyDriver.blue)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text(engine.formattedRemainingTime)
                    .font(.system(size: 76, weight: .semibold, design: .monospaced))
                    .foregroundColor(engine.phase == .paused ? DailyDriver.foregroundDim : DailyDriver.lime)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text(engine.phase == .paused ? "THIS BLOCK · PAUSED" : "THIS BLOCK")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text(nextLine)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)

                HStack(spacing: 5) {
                    ForEach(0..<max(totalSteps, 1), id: \.self) { index in
                        Capsule()
                            .fill(segmentColor(for: index))
                            .frame(height: 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Control dock

    private var controlDock: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DailyDriver.card2)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 12)

            HStack(spacing: 10) {
                DDIconChip(systemName: "flame.fill", background: DailyDriver.card2, foreground: DailyDriver.lime, size: 30)

                Text(engine.formattedElapsedTime)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: "F5D90A"))
                    .monospacedDigit()

                Text("ELAPSED")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)

                Spacer(minLength: 0)

                Text(heartRateLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DailyDriver.red)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            HStack(spacing: 28) {
                playerCircleButton(systemName: "chevron.left") {
                    engine.previousStep()
                }
                .disabled(currentIndex == 0)
                .opacity(currentIndex == 0 ? 0.35 : 1)

                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.phase == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(DailyDriver.ink)
                        .frame(width: 64, height: 64)
                        .background(DailyDriver.lime)
                        .clipShape(Circle())
                        .ddLimeGlow()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dd_player_play_pause")

                playerCircleButton(systemName: "chevron.right") {
                    engine.nextStep()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)

            Button("End workout", action: onEnd)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.bottom, 16)
        }
        .background(
            Color(hex: "101012")
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DailyDriver.border)
                        .frame(height: 1)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func playerCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DailyDriver.foreground)
                .frame(width: 54, height: 54)
                .background(DailyDriver.card2)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var sessionMeta: String {
        let name = (engine.workout?.name ?? "WORKOUT").uppercased()
        return "\(name) · ON PHONE · NO WATCH NEEDED"
    }

    private var stepDetailLine: String? {
        if let details = engine.currentStep?.details, !details.isEmpty {
            return details.uppercased()
        }
        if engine.currentStep?.stepType == .reps {
            return "REPS"
        }
        return nil
    }

    private var nextLine: String {
        let nextIndex = currentIndex + 1
        guard nextIndex < engine.flattenedSteps.count else {
            return "NEXT · DONE — LOG IT"
        }
        let next = engine.flattenedSteps[nextIndex]
        let label = next.displayLabel.uppercased()
        let detail = (next.details ?? "").uppercased()
        if detail.isEmpty {
            return "NEXT · \(label)"
        }
        return "NEXT · \(label) — \(detail)"
    }

    private func segmentColor(for index: Int) -> Color {
        if index < currentIndex { return DailyDriver.lime }
        if index == currentIndex { return DailyDriver.foreground }
        return DailyDriver.card2
    }

    private var heartRateLabel: String {
        if watchManager.watchHeartRate > 0 {
            return "♥ \(Int(watchManager.watchHeartRate))"
        }
        return "♥ —"
    }
}
