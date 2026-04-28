//
//  HistoryView.swift
//  AmakaFlow
//
//  Completed workouts history screen grouped by week
//

import SwiftUI

// MARK: - History Item Model

struct HistoryItem: Identifiable {
    let id: String
    let workoutId: String
    let workoutName: String
    let completedAt: Date
    let duration: Int
    let device: DeviceType

    enum DeviceType: String {
        case appleWatch = "apple_watch"
        case manual = "manual"
        case voiceRecording = "voice_recording"

        var displayName: String {
            switch self {
            case .appleWatch: return "Apple Watch"
            case .manual: return "Manual"
            case .voiceRecording: return "Voice Recording"
            }
        }
    }
}

struct HistoryView: View {
    @State private var historyItems: [HistoryItem] = HistoryView.sampleHistory
    @State private var showingAddWorkout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if groupedItems.isEmpty {
                    emptyState
                        .padding(.top, Theme.Spacing.xl * 2)
                } else {
                    VStack(spacing: Theme.Spacing.lg) {
                        AFTopBar(title: "History", subtitle: "\(historyItems.count) sessions · last 30 days") {
                            EmptyView()
                        } right: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .onTapGesture { showingAddWorkout = true }
                        }

                        trainingLoadCard

                        HStack(spacing: 3) {
                            Text("All").historySegment(isSelected: true)
                            Text("Run").historySegment(isSelected: false)
                            Text("Strength").historySegment(isSelected: false)
                            Text("Ride").historySegment(isSelected: false)
                        }
                        .padding(3)
                        .background(Theme.Colors.inputBackground)
                        .clipShape(Capsule())
                        .padding(.horizontal, Theme.Spacing.lg)

                        ForEach(groupedItems, id: \.title) { group in
                            historySection(title: group.title, items: group.items)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.bottom, 100)
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var trainingLoadCard: some View {
        AFCard(padding: 14) {
            VStack(spacing: 10) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        AFLabel(text: "Load · Last 4 Weeks")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("412")
                                .font(.system(size: 22, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("TSS")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(Theme.Colors.readyHigh).frame(width: 8, height: 8)
                        Text("Optimal")
                    }
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.Colors.chipBackground)
                    .clipShape(Capsule())
                }

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array([0.62, 0.76, 0.86, 1.0].enumerated()), id: \.offset) { index, value in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(index == 3 ? Theme.Colors.textPrimary : Theme.Colors.accentBackground)
                                .frame(height: 36 * value)
                            Text(index == 3 ? "THIS" : "W-\(3 - index)")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 48, alignment: .bottom)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - History Section

    private func historySection(title: String, items: [HistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(items) { item in
                    HistoryRow(item: item)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.surface)
                    .frame(width: 64, height: 64)

                Image(systemName: "checkmark")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text("No completed workouts yet")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Text("Complete a workout to see it here")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grouped Items

    private struct HistoryGroup {
        let title: String
        let items: [HistoryItem]
    }

    private var groupedItems: [HistoryGroup] {
        let now = Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: now)!
        let twoWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -2, to: now)!

        let thisWeek = historyItems.filter { $0.completedAt >= oneWeekAgo }
        let lastWeek = historyItems.filter { $0.completedAt >= twoWeeksAgo && $0.completedAt < oneWeekAgo }
        let older = historyItems.filter { $0.completedAt < twoWeeksAgo }

        var groups: [HistoryGroup] = []

        if !thisWeek.isEmpty {
            groups.append(HistoryGroup(title: "THIS WEEK", items: thisWeek))
        }
        if !lastWeek.isEmpty {
            groups.append(HistoryGroup(title: "LAST WEEK", items: lastWeek))
        }
        if !older.isEmpty {
            groups.append(HistoryGroup(title: "OLDER", items: older))
        }

        return groups
    }

    // MARK: - Sample Data

    static var sampleHistory: [HistoryItem] {
        let now = Date()
        return [
            HistoryItem(
                id: "1",
                workoutId: "w1",
                workoutName: "Morning Strength",
                completedAt: now.addingTimeInterval(-86400),
                duration: 2700,
                device: .appleWatch
            ),
            HistoryItem(
                id: "2",
                workoutId: "w2",
                workoutName: "HIIT Cardio",
                completedAt: now.addingTimeInterval(-172800),
                duration: 1800,
                device: .appleWatch
            ),
            HistoryItem(
                id: "3",
                workoutId: "w3",
                workoutName: "Evening Run",
                completedAt: now.addingTimeInterval(-259200),
                duration: 3600,
                device: .manual
            ),
            HistoryItem(
                id: "4",
                workoutId: "w4",
                workoutName: "Mobility Session",
                completedAt: now.addingTimeInterval(-604800),
                duration: 1200,
                device: .appleWatch
            ),
            HistoryItem(
                id: "5",
                workoutId: "w5",
                workoutName: "Full Body Workout",
                completedAt: now.addingTimeInterval(-691200),
                duration: 2400,
                device: .voiceRecording
            )
        ]
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Checkmark icon
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentGreen.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.accentGreen)
            }

            // Workout info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.workoutName)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("\(formattedDate) \u{2022} \(item.device.displayName)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Color.clear, lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Colors.borderLight).frame(height: 1)
        }
    }

    private var formattedDate: String {
        item.completedAt.formatted(.dateTime.month(.abbreviated).day())
    }
}

private extension Text {
    func historySegment(isSelected: Bool) -> some View {
        self
            .font(Theme.Typography.captionBold)
            .foregroundColor(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.Colors.surface : Color.clear)
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .preferredColorScheme(.dark)
}
