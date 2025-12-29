//
//  HRZonesView.swift
//  AmakaFlow
//
//  Heart rate zone distribution view
//

import SwiftUI

struct HRZonesView: View {
    let zones: [HRZone]

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HR Zones")
                .font(.headline)
                .foregroundColor(.primary)

            if zones.isEmpty || zones.allSatisfy({ $0.percentageOfWorkout == 0 }) {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(zones.reversed()) { zone in
                        zoneRow(zone)
                    }
                }
            }
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Zone Row

    private func zoneRow(_ zone: HRZone) -> some View {
        HStack(spacing: 12) {
            // Zone label
            Text(zone.name)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 60, alignment: .leading)

            // Range
            Text(zone.rangeLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 55, alignment: .trailing)

            // Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.borderLight)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorForZone(zone.color))
                        .frame(width: max(0, geometry.size.width * CGFloat(zone.percentageOfWorkout / 100)))
                }
            }
            .frame(height: 20)

            // Percentage
            Text(String(format: "%.0f%%", zone.percentageOfWorkout))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("No zone data available")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Helpers

    private func colorForZone(_ zoneColor: HRZoneColor) -> Color {
        switch zoneColor {
        case .gray: return .gray
        case .blue: return .blue
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        HRZonesView(zones: WorkoutCompletionDetail.sample.calculateHRZones())

        HRZonesView(zones: [])
    }
    .padding()
    .background(Theme.Colors.background)
}
