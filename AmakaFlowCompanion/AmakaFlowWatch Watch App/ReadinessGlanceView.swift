//
//  ReadinessGlanceView.swift
//  AmakaFlowWatch Watch App
//
//  Compact readiness glance for watch face complication (AMA-1150)
//

import SwiftUI

struct ReadinessGlanceView: View {
    @ObservedObject var viewModel: DayStateViewModel

    var body: some View {
        Group {
            if let dayState = viewModel.dayState {
                glanceContent(dayState)
            } else if viewModel.isLoading {
                ProgressView()
                    .accessibilityIdentifier("readiness-loading")
            } else {
                unavailableView
            }
        }
        .onAppear {
            if viewModel.dayState == nil {
                viewModel.requestDayState()
            }
        }
    }

    // MARK: - Glance Content

    private func glanceContent(_ dayState: DayState) -> some View {
        VStack(spacing: 6) {
            // Score circle
            ZStack {
                Circle()
                    .strokeBorder(dayState.readinessLabel.color.opacity(0.3), lineWidth: 4)
                    .frame(width: 64, height: 64)

                Circle()
                    .trim(from: 0, to: CGFloat(dayState.readinessScore) / 100.0)
                    .stroke(dayState.readinessLabel.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))

                Text("\(dayState.readinessScore)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(dayState.readinessLabel.color)
            }

            // Status text
            Text(dayState.readinessLabel.displayText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(dayState.readinessLabel.color)

            // Session count
            if !dayState.sessions.isEmpty {
                let remaining = dayState.sessions.filter { !$0.isCompleted }.count
                Text("\(remaining) session\(remaining == 1 ? "" : "s") remaining")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityIdentifier("readiness-glance")
    }

    private var unavailableView: some View {
        VStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 24))
                .foregroundColor(.gray)

            Text("Readiness unavailable")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .accessibilityIdentifier("readiness-unavailable")
    }
}
