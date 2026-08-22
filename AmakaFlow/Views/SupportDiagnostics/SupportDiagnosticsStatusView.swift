import SwiftUI

struct SupportDiagnosticsStatusView: View {
    @ObservedObject var viewModel: SupportDiagnosticsViewModel

    @State private var snapshot: SupportDiagnosticsSnapshot?
    @State private var loadedToken: DiagnosticAuthorizationLoadToken?
    @State private var isLoading = false

    var body: some View {
        List {
            if currentToken == nil {
                Section {
                    Label("Status is unavailable for this support session.", systemImage: "lock.fill")
                }
            } else if let snapshot {
                Section {
                    LabeledContent("Generated", value: snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))
                        .monospacedDigit()
                }

                ForEach(snapshot.results, id: \.id) { result in
                    Section(result.title) {
                        availabilityRows(result.availability)
                    }
                }
            } else {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Collecting safe status probes…")
                    }
                }
            }
        }
        .navigationTitle("Status")
        .scrollContentBackground(.hidden)
        .background(DailyDriver.screenBackground)
        .tint(DailyDriver.lime)
        .refreshable {
            await loadSnapshot()
        }
        .task(id: currentToken) {
            guard currentToken != nil else {
                clearLoadedContent()
                return
            }
            guard loadedToken != currentToken else { return }
            clearLoadedContent()
            await loadSnapshot()
        }
        .overlay {
            if isLoading, snapshot != nil {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func availabilityRows(_ availability: SupportDiagnosticsAvailability) -> some View {
        switch availability {
        case .available(let fields):
            ForEach(fields, id: \.label) { field in
                LabeledContent(field.label, value: field.value)
            }
        case .unavailable(let errorCode, let correlationID):
            LabeledContent("Status", value: "Unavailable")
            LabeledContent("Safe error", value: errorCode.rawValue)
            if let correlationID {
                LabeledContent("Correlation ID", value: correlationID)
            }
        }
    }

    @MainActor
    private func loadSnapshot() async {
        guard let token = currentToken,
              let authorization = viewModel.authorization
        else {
            clearLoadedContent()
            return
        }
        isLoading = true
        defer { isLoading = false }

        let correlationIDProvider: @Sendable () -> String? = {
            SupportDiagnosticsRuntimeState.shared.safeCorrelationID()
        }
        let runner = SupportDiagnosticsProbeRunner(
            probes: SupportDiagnosticsProbes.live(authorization: authorization),
            correlationIDProvider: correlationIDProvider
        )
        let loadedSnapshot = await runner.run()
        guard token.matches(
            state: viewModel.state,
            accountID: viewModel.currentAccountID,
            requiredCapability: .statusRead
        ) else { return }
        snapshot = loadedSnapshot
        loadedToken = token
    }

    @MainActor
    private var currentToken: DiagnosticAuthorizationLoadToken? {
        DiagnosticAuthorizationLoadToken.capture(
            state: viewModel.state,
            accountID: viewModel.currentAccountID,
            requiredCapability: .statusRead
        )
    }

    @MainActor
    private func clearLoadedContent() {
        snapshot = nil
        loadedToken = nil
    }
}
