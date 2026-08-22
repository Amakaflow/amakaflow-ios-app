import SwiftUI

struct SupportDiagnosticsLogsView: View {
    @ObservedObject var viewModel: SupportDiagnosticsViewModel

    private let provider: any DiagnosticEventSnapshotProviding
    @State private var events: [DiagnosticEvent] = []
    @State private var loadedToken: DiagnosticAuthorizationLoadToken?
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
        .scrollContentBackground(.hidden)
        .background(DailyDriver.screenBackground)
        .tint(DailyDriver.lime)
        .refreshable {
            await loadEvents()
        }
        .task(id: currentToken) {
            guard currentToken != nil else {
                clearLoadedContent()
                return
            }
            guard loadedToken == nil || DiagnosticLogsPolicy.shouldReloadLoadedContent(
                token: loadedToken,
                currentState: viewModel.state,
                currentAccountID: viewModel.currentAccountID,
                requiredCapability: .logsRead
            ) else { return }
            clearLoadedContent()
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
                .monospacedDigit()
            if let errorMessage {
                LabeledContent("Status", value: displayMessage(for: errorMessage))
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
        guard let token = currentToken else {
            clearLoadedContent()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loadedEvents = try await provider.eventsForCurrentAccount()
            guard DiagnosticLogsPolicy.acceptsLoadedEvents(
                token: token,
                currentState: viewModel.state,
                currentAccountID: viewModel.currentAccountID
            ) else { return }
            events = loadedEvents
            loadedToken = token
            errorMessage = nil
        } catch {
            guard DiagnosticLogsPolicy.acceptsLoadedEvents(
                token: token,
                currentState: viewModel.state,
                currentAccountID: viewModel.currentAccountID
            ) else { return }
            events = []
            loadedToken = token
            errorMessage = "LOGS_UNAVAILABLE"
            #if DEBUG
            print("[SupportDiagnostics] LOGS_UNAVAILABLE")
            #endif
        }
    }

    @MainActor
    private var currentToken: DiagnosticAuthorizationLoadToken? {
        DiagnosticAuthorizationLoadToken.capture(
            state: viewModel.state,
            accountID: viewModel.currentAccountID,
            requiredCapability: .logsRead
        )
    }

    @MainActor
    private func clearLoadedContent() {
        events = []
        loadedToken = nil
        errorMessage = nil
    }

    private func displayMessage(for safeErrorCode: String) -> String {
        safeErrorCode == "LOGS_UNAVAILABLE"
            ? "Logs could not be loaded. Pull to refresh and try again."
            : "Diagnostics are temporarily unavailable."
    }
}

private struct DiagnosticEventSection: View {
    let event: DiagnosticEvent

    var body: some View {
        Section(event.title) {
            LabeledContent("Timestamp", value: event.timestamp.formatted(date: .abbreviated, time: .standard))
                .monospacedDigit()
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
