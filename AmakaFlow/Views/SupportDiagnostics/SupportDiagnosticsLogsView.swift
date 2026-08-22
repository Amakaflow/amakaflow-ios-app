import SwiftUI

struct SupportDiagnosticsLogsView: View {
    @ObservedObject var viewModel: SupportDiagnosticsViewModel

    private let provider: any DiagnosticEventSnapshotProviding
    @State private var events: [DiagnosticEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @MainActor
    init(
        viewModel: SupportDiagnosticsViewModel,
        provider: any DiagnosticEventSnapshotProviding = LiveDiagnosticEventSnapshotProvider()
    ) {
        self.viewModel = viewModel
        self.provider = provider
    }

    var body: some View {
        List {
            if DiagnosticLogsPolicy.canReadLogs(viewModel.state) {
                let visibleEvents = DiagnosticLogsPolicy.visibleEvents(state: viewModel.state, events: events)
                summarySection(eventCount: visibleEvents.count)
                if visibleEvents.isEmpty, !isLoading {
                    emptySection
                }
                ForEach(visibleEvents) { event in
                    DiagnosticEventSection(event: event)
                }
            } else {
                lockedSection
            }
        }
        .navigationTitle("Logs")
        .refreshable {
            await loadEvents()
        }
        .task(id: viewModel.state) {
            clearIfLocked()
            guard events.isEmpty else { return }
            await loadEvents()
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func summarySection(eventCount: Int) -> some View {
        Section {
            LabeledContent("Events", value: "\(eventCount)")
            if let errorMessage {
                LabeledContent("Safe error", value: errorMessage)
            }
        } footer: {
            Text("Only account-scoped, already-redacted structured diagnostics are shown.")
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView(
                "No diagnostic events",
                systemImage: "doc.text.magnifyingglass",
                description: Text("No safe log events are available for this account.")
            )
        }
    }

    private var lockedSection: some View {
        Section {
            Label("Logs are unavailable for this support session.", systemImage: "lock.fill")
        } footer: {
            Text("Event content is removed unless the active session includes logs.read.")
        }
    }

    @MainActor
    private func loadEvents() async {
        guard DiagnosticLogsPolicy.canReadLogs(viewModel.state) else {
            events = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            events = try await provider.eventsForCurrentAccount()
            errorMessage = nil
        } catch {
            events = []
            errorMessage = "LOGS_UNAVAILABLE"
        }
    }

    @MainActor
    private func clearIfLocked() {
        guard DiagnosticLogsPolicy.canReadLogs(viewModel.state) else {
            events = []
            errorMessage = nil
            return
        }
    }
}

private struct DiagnosticEventSection: View {
    let event: DiagnosticEvent

    var body: some View {
        Section(event.title) {
            LabeledContent("Timestamp", value: event.timestamp.formatted(date: .abbreviated, time: .standard))
            LabeledContent("Severity", value: event.severity.rawValue)
            LabeledContent("Category", value: event.category.rawValue)
            LabeledContent("Stable name", value: event.name)
            LabeledContent("Message", value: event.message)
            metadataRows
            correlationRows
        }
    }

    @ViewBuilder
    private var metadataRows: some View {
        ForEach(event.metadata.sorted { $0.key < $1.key }, id: \.key) { key, value in
            LabeledContent(key, value: value)
        }
    }

    @ViewBuilder
    private var correlationRows: some View {
        if let requestID = event.requestID {
            LabeledContent("Request ID", value: requestID)
        }
        if let sentryEventID = event.sentryEventID {
            LabeledContent("Sentry event ID", value: sentryEventID)
        }
        if let sentryTraceID = event.sentryTraceID {
            LabeledContent("Sentry trace ID", value: sentryTraceID)
        }
    }
}
