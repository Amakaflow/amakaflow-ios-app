//
//  HRChartView.swift
//  AmakaFlow
//
//  Heart rate line chart using Swift Charts
//

import SwiftUI
import Charts

struct HRChartView: View {
    let samples: [HRSample]
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let minHeartRate: Int?

    // MARK: - Computed Properties

    private var yAxisMin: Int {
        let minSample = samples.map(\.bpm).min() ?? 60
        let providedMin = minHeartRate ?? minSample
        return max(40, min(minSample, providedMin) - 10)
    }

    private var yAxisMax: Int {
        let maxSample = samples.map(\.bpm).max() ?? 180
        let providedMax = maxHeartRate ?? maxSample
        return min(220, max(maxSample, providedMax) + 10)
    }

    private var startTime: Date {
        samples.first?.timestamp ?? Date()
    }

    private var endTime: Date {
        samples.last?.timestamp ?? Date()
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate")
                .font(.headline)
                .foregroundColor(.primary)

            if samples.isEmpty {
                emptyState
            } else {
                chart
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            // Main line
            ForEach(samples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("BPM", sample.bpm)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Area fill under the line
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("BPM", sample.bpm)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red.opacity(0.3), .red.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Average line
            if let avg = avgHeartRate {
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("avg \(avg)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
            }
        }
        .chartYScale(domain: yAxisMin...yAxisMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(formatTimeLabel(date))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bpm = value.as(Int.self) {
                        Text("\(bpm)")
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 200)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No heart rate data available")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatTimeLabel(_ date: Date) -> String {
        let elapsed = date.timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        return "\(minutes)m"
    }
}

// MARK: - Preview

#Preview {
    VStack {
        HRChartView(
            samples: WorkoutCompletionDetail.sample.heartRateSamples ?? [],
            avgHeartRate: 142,
            maxHeartRate: 178,
            minHeartRate: 85
        )

        HRChartView(
            samples: [],
            avgHeartRate: nil,
            maxHeartRate: nil,
            minHeartRate: nil
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
