import SwiftUI

struct AgentInboxView: View {
    let onDismiss: () -> Void
    let events: [AgentEvent]
    @State private var selectedFilter: AgentInboxFilter = .all

    init(events: [AgentEvent] = [], onDismiss: @escaping () -> Void) {
        self.events = events
        self.onDismiss = onDismiss
    }

    private var visibleEvents: [AgentEvent] {
        selectedFilter == .all ? events : events.filter { $0.kind.rawValue == selectedFilter.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            AFTopBar(title: "Coach activity", subtitle: "Every agent decision in chronological order.") {
                Button(action: onDismiss) { Image(systemName: "chevron.left") }
            } right: {
                Button("Done", action: onDismiss).font(Theme.Typography.captionBold)
            }

            Picker("Filter", selection: $selectedFilter) {
                ForEach(AgentInboxFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.md)

            if visibleEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(visibleEvents, id: \.id) { event in
                            eventRow(event)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "tray")
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Colors.textTertiary)
            Text("No coach activity yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text("Agent decisions will appear here when the backend sends activity events.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.lg)
    }

    private func eventRow(_ event: AgentEvent) -> some View {
        AFCard(padding: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Text(event.emoji)
                    .font(Theme.Typography.title1)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(alignment: .top) {
                        Text(event.title)
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        AFChip(text: event.kind.rawValue, outline: true)
                    }
                    Text(event.timestamp)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(event.body)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(Theme.Spacing.xs)
                }
            }
        }
    }
}

private enum AgentInboxFilter: String, CaseIterable {
    case all = "All"
    case plan = "Plan"
    case watch = "Watch"
    case safety = "Safety"
}

enum AgentEventKind: String {
    case plan = "Plan"
    case watch = "Watch"
    case safety = "Safety"
}

struct AgentEvent {
    let id = UUID()
    let emoji: String
    let title: String
    let kind: AgentEventKind
    let timestamp: String
    let body: String
}

#Preview {
    AgentInboxView(
        events: [
            AgentEvent(emoji: "📅", title: "Plan generated", kind: .plan, timestamp: "Mon 06:14", body: "4-week block built from 8 weeks of Garmin history and HRV trend."),
            AgentEvent(emoji: "🔄", title: "Session swapped", kind: .plan, timestamp: "Tue 14:22", body: "Moved threshold run to Friday — recovery dip overnight."),
            AgentEvent(emoji: "⌚", title: "Sent to watch", kind: .watch, timestamp: "Wed 06:05", body: "Today's intervals pushed to Garmin Training Calendar."),
            AgentEvent(emoji: "🚩", title: "Red-flag rest", kind: .safety, timestamp: "Thu 06:10", body: "Stacked fatigue + calf symptoms. Replaced with mobility + walk."),
            AgentEvent(emoji: "📊", title: "Weekly review", kind: .plan, timestamp: "Sun 07:01", body: "83% adherence. Build week confirmed for next 7 days.")
        ],
        onDismiss: {}
    )
        .preferredColorScheme(.dark)
}
