//
//  MetricGridView.swift
//  AmakaFlow
//
//  Reusable grid for displaying workout metrics
//

import SwiftUI

// MARK: - Metric Item

struct MetricItem: Identifiable {
    let id = UUID()
    let icon: String
    let value: String
    let label: String
    let iconColor: Color

    init(icon: String, value: String, label: String, iconColor: Color = .primary) {
        self.icon = icon
        self.value = value
        self.label = label
        self.iconColor = iconColor
    }
}

// MARK: - Metric Grid View

struct MetricGridView: View {
    let title: String
    let metrics: [MetricItem]
    let columns: Int

    init(title: String, metrics: [MetricItem], columns: Int = 3) {
        self.title = title
        self.metrics = metrics
        self.columns = columns
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(metrics) { metric in
                    metricCell(metric)
                }
            }
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    private func metricCell(_ metric: MetricItem) -> some View {
        VStack(spacing: 4) {
            Image(systemName: metric.icon)
                .font(.title3)
                .foregroundColor(metric.iconColor)

            Text(metric.value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text(metric.label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Convenience Initializers

extension MetricGridView {
    /// Create a summary metrics grid (duration, calories, steps)
    static func summary(duration: String, calories: String?, steps: String?) -> MetricGridView {
        var metrics: [MetricItem] = [
            MetricItem(icon: "timer", value: duration, label: "Duration", iconColor: .blue)
        ]

        if let calories = calories {
            metrics.append(MetricItem(icon: "flame.fill", value: calories, label: "Calories", iconColor: .orange))
        }

        if let steps = steps {
            metrics.append(MetricItem(icon: "figure.walk", value: steps, label: "Steps", iconColor: .green))
        }

        return MetricGridView(title: "Summary", metrics: metrics)
    }

    /// Create activity metrics grid (calories, steps, distance) - without duration
    static func activity(calories: String?, steps: String?, distance: String?) -> MetricGridView {
        var metrics: [MetricItem] = []

        if let calories = calories {
            metrics.append(MetricItem(icon: "flame.fill", value: calories, label: "Calories", iconColor: .orange))
        }

        if let steps = steps {
            metrics.append(MetricItem(icon: "figure.walk", value: steps, label: "Steps", iconColor: .green))
        }

        if let distance = distance {
            metrics.append(MetricItem(icon: "map", value: distance, label: "Distance", iconColor: .purple))
        }

        // Use 2 columns if only 2 items, otherwise 3
        let columns = metrics.count == 2 ? 2 : 3
        return MetricGridView(title: "Activity", metrics: metrics, columns: columns)
    }

    /// Whether this grid has any metrics to display
    var hasMetrics: Bool {
        !metrics.isEmpty
    }

    /// Create a heart rate metrics grid (avg, max, min)
    static func heartRate(avg: Int?, max: Int?, min: Int?) -> MetricGridView {
        var metrics: [MetricItem] = []

        if let avg = avg {
            metrics.append(MetricItem(icon: "heart.fill", value: "\(avg)", label: "Average", iconColor: .red))
        }

        if let max = max {
            metrics.append(MetricItem(icon: "arrow.up.heart.fill", value: "\(max)", label: "Maximum", iconColor: .red))
        }

        if let min = min {
            metrics.append(MetricItem(icon: "arrow.down.heart.fill", value: "\(min)", label: "Minimum", iconColor: .red))
        }

        return MetricGridView(title: "Heart Rate", metrics: metrics)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        MetricGridView.summary(
            duration: "45:00",
            calories: "320",
            steps: "4.5k"
        )

        MetricGridView.heartRate(
            avg: 142,
            max: 178,
            min: 85
        )

        MetricGridView(
            title: "Custom Grid",
            metrics: [
                MetricItem(icon: "map", value: "3.2 km", label: "Distance", iconColor: .purple),
                MetricItem(icon: "speedometer", value: "8:30", label: "Pace", iconColor: .blue)
            ],
            columns: 2
        )
    }
    .padding()
    .background(Theme.Colors.background)
}
