//
//  VolumeBarChart.swift
//  AmakaFlow
//
//  Stacked bar chart showing volume by muscle group (AMA-1414)
//

import SwiftUI
import Charts

struct VolumeBarChart: View {
    let dataPoints: [VolumeDataPoint]

    private var muscleGroups: [String] {
        Array(Set(dataPoints.map { $0.muscleGroup })).sorted()
    }

    var body: some View {
        if dataPoints.isEmpty {
            Text("No volume data available")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(height: 200)
        } else {
            Chart(dataPoints) { point in
                BarMark(
                    x: .value("Period", point.period),
                    y: .value("Volume", point.totalVolume)
                )
                .foregroundStyle(by: .value("Muscle", point.muscleGroup))
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatVolume(v))
                                .font(.system(size: 10))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(shortenPeriod(label))
                                .font(.system(size: 10))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1000 { return "\(Int(value / 1000))k" }
        return "\(Int(value))"
    }

    private func shortenPeriod(_ period: String) -> String {
        // "2026-03-24" -> "Mar 24"
        if period.count >= 10 {
            let parts = period.split(separator: "-")
            if parts.count == 3 {
                let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                if let month = Int(parts[1]), month > 0, month <= 12 {
                    return "\(months[month]) \(parts[2])"
                }
            }
        }
        return period
    }
}
