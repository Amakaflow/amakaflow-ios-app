import SwiftUI

struct DiagnosticBundlePreviewView: View {
    @ObservedObject var viewModel: SupportDiagnosticsViewModel

    private let provider: any DiagnosticBundleSnapshotProviding
    @State private var snapshot: DiagnosticBundleSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @MainActor
    init(viewModel: SupportDiagnosticsViewModel) {
        self.init(
            viewModel: viewModel,
            provider: LiveDiagnosticBundleSnapshotProvider(eventsProvider: LiveDiagnosticEventSnapshotProvider())
        )
    }

    @MainActor
    init(viewModel: SupportDiagnosticsViewModel, provider: any DiagnosticBundleSnapshotProviding) {
        self.viewModel = viewModel
        self.provider = provider
    }

    var body: some View {
        List {
            if let preview = DiagnosticBundlePreviewPolicy.preview(state: viewModel.state, snapshot: snapshot) {
                includedFilesSection(preview)
                metadataSection(preview)
                excludedSection(preview)
            } else {
                lockedSection
            }
        }
        .navigationTitle("Export Preview")
        .refreshable {
            await loadSnapshot()
        }
        .task(id: viewModel.state) {
            clearIfLocked()
            guard snapshot == nil else { return }
            await loadSnapshot()
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func includedFilesSection(_ preview: DiagnosticBundlePreview) -> some View {
        Section {
            ForEach(preview.includedFileNames, id: \.self) { fileName in
                Label(fileName, systemImage: "doc.text")
            }
        } header: {
            Text("Included files")
        } footer: {
            Text("This is a preview only. Bundle creation and sharing are handled by a later task.")
        }
    }

    private func metadataSection(_ preview: DiagnosticBundlePreview) -> some View {
        Section {
            LabeledContent("Events", value: "\(preview.eventCount)")
            if let timeRange = preview.timeRange {
                LabeledContent("First event", value: timeRange.start.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Last event", value: timeRange.end.formatted(date: .abbreviated, time: .standard))
            } else {
                LabeledContent("Time range", value: "No events")
            }
            if let errorMessage {
                LabeledContent("Safe error", value: errorMessage)
            }
        } header: {
            Text("Preview metadata")
        } footer: {
            Text("Metadata is derived from one frozen diagnostic snapshot, not live services.")
        }
    }

    private func excludedSection(_ preview: DiagnosticBundlePreview) -> some View {
        Section("Explicitly excluded") {
            ForEach(preview.excludedCategories, id: \.self) { category in
                Label(category, systemImage: "xmark.shield")
            }
        }
    }

    private var lockedSection: some View {
        Section {
            Label("Export preview is unavailable for this support session.", systemImage: "lock.fill")
        } footer: {
            Text("Preview content is removed unless the active session includes bundle.export.")
        }
    }

    @MainActor
    private func loadSnapshot() async {
        guard DiagnosticBundlePreviewPolicy.canPreviewBundle(viewModel.state),
              let authorization = viewModel.authorization
        else {
            snapshot = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            snapshot = try await provider.snapshot(authorization: authorization)
            errorMessage = nil
        } catch {
            snapshot = nil
            errorMessage = "BUNDLE_PREVIEW_UNAVAILABLE"
        }
    }

    @MainActor
    private func clearIfLocked() {
        guard DiagnosticBundlePreviewPolicy.canPreviewBundle(viewModel.state) else {
            snapshot = nil
            errorMessage = nil
            return
        }
    }
}
