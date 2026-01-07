//
//  SimulationBannerView.swift
//  AmakaFlow
//
//  Yellow banner displayed during simulated workouts.
//  Part of AMA-271: Workout Simulation Mode
//

import SwiftUI

/// Yellow banner indicating simulation mode is active
struct SimulationBannerView: View {
    let speed: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.caption2)

            Text("SIMULATION MODE (\(Int(speed))x)")
                .font(.caption.bold())
        }
        .foregroundColor(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow)
        .cornerRadius(4)
    }
}

/// Compact version for tight spaces
struct SimulationBadgeView: View {
    let speed: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10))
            Text("\(Int(speed))x")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.black)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.yellow)
        .cornerRadius(3)
    }
}

/// Badge indicating health data is simulated
struct SimulatedDataBadgeView: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 8))
            Text("simulated")
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(Theme.Colors.textTertiary)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Theme.Colors.surface.opacity(0.5))
        .cornerRadius(2)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SimulationBannerView(speed: 10)
        SimulationBannerView(speed: 30)
        SimulationBannerView(speed: 60)

        Divider()

        HStack {
            Text("Compact badge:")
            SimulationBadgeView(speed: 10)
        }

        Divider()

        HStack {
            Text("HR: 142 bpm")
            SimulatedDataBadgeView()
        }
    }
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
