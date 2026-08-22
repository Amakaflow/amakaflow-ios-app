import SwiftUI

struct SupportDiagnosticsStatusView: View {
    let authorization: SupportDiagnosticsAuthorization

    @State private var snapshot: SupportDiagnosticsSnapshot?
    @State private var isLoading = false

    var body: some View {
        List {
            if let snapshot {
                Section {
                    LabeledContent("Generated", value: snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))
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
        .refreshable {
            await loadSnapshot()
        }
        .task {
            guard snapshot == nil else { return }
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
        isLoading = true
        defer { isLoading = false }

        let runner = SupportDiagnosticsProbeRunner(
            probes: SupportDiagnosticsProbes.live(authorization: authorization)
        ) {
            SupportDiagnosticsRuntimeState.shared.safeCorrelationID()
        }
        snapshot = await runner.run()
    }
}
