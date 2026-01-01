//
//  WorkoutCountdownView.swift
//  AmakaFlowWatch Watch App
//
//  3-2-1 countdown animation before workout starts
//

import SwiftUI
import WatchKit

struct WorkoutCountdownView: View {
    @Binding var isPresented: Bool
    var onComplete: () -> Void

    @State private var currentCount: Int = 3
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            // Dark overlay background
            Color.black.ignoresSafeArea()

            // Countdown display
            Text(countdownText)
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(currentCount == 0 ? .green : .white)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            startCountdown()
        }
    }

    private var countdownText: String {
        currentCount > 0 ? "\(currentCount)" : "GO!"
    }

    private func startCountdown() {
        // Initial animation for first number
        animateNumber()
        playHaptic(.click)

        // Schedule remaining counts
        for i in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) {
                if i < 3 {
                    currentCount = 3 - i
                    animateNumber()
                    playHaptic(.click)
                } else {
                    // Final "GO!"
                    currentCount = 0
                    animateNumber()
                    playHaptic(.start)

                    // Dismiss after showing GO!
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isPresented = false
                        onComplete()
                    }
                }
            }
        }
    }

    private func animateNumber() {
        // Reset for animation
        scale = 0.5
        opacity = 0

        // Animate in
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.2
            opacity = 1
        }

        // Settle to normal size
        withAnimation(.easeInOut(duration: 0.2).delay(0.3)) {
            scale = 1.0
        }

        // Fade out (except for GO! which stays visible longer)
        if currentCount > 0 {
            withAnimation(.easeIn(duration: 0.3).delay(0.6)) {
                opacity = 0.3
            }
        }
    }

    private func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}

// MARK: - Preview

#Preview {
    WorkoutCountdownView(isPresented: .constant(true)) {
        print("Countdown complete!")
    }
}
