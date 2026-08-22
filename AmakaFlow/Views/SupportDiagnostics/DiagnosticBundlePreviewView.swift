import SwiftUI

struct DiagnosticBundlePreviewView: View {
    @ObservedObject var viewModel: SupportDiagnosticsViewModel

    private let provider: any DiagnosticBundleSnapshotProviding
    @State private var snapshot: DiagnosticBundleSnapshot?
    @State private var loadedToken: DiagnosticAuthorizationLoadToken?
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
            guard loadedToken == nil || DiagnosticLogsPolicy.shouldReloadLoadedContent(
                token: loadedToken,
                currentState: viewModel.state,
                currentAccountID: viewModel.currentAccountID,
                requiredCapability: .bundleExport
            ) else { return }
            clearLoadedContent()
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
                .monospacedDigit()
            if let timeRange = preview.timeRange {
                LabeledContent("First event", value: timeRange.start.formatted(date: .abbreviated, time: .standard))
                    .monospacedDigit()
                LabeledContent("Last event", value: timeRange.end.formatted(date: .abbreviated, time: .standard))
                    .monospacedDigit()
            } else {
                LabeledContent("Time range", value: "No events")
            }
            if let errorMessage {
                LabeledContent("Status", value: displayMessage(for: errorMessage))
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
        guard let token = currentToken,
              let authorization = viewModel.authorization
        else {
            clearLoadedContent()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loadedSnapshot = try await provider.snapshot(authorization: authorization)
            guard DiagnosticBundlePreviewPolicy.acceptsLoadedSnapshot(
                token: token,
                currentState: viewModel.state,
                currentAccountID: viewModel.currentAccountID
            ), DiagnosticBundlePreviewPolicy.preview(state: viewModel.state, snapshot: loadedSnapshot) != nil
            else { return }
            snapshot = loadedSnapshot
            loadedToken = token
            errorMessage = nil
        } catch {
            guard DiagnosticBundlePreviewPolicy.acceptsLoadedSnapshot(
                token: token,
                currentState: viewModel.state,
                currentAccountID: viewModel.currentAccountID
            ) else { return }
            snapshot = nil
            loadedToken = token
            errorMessage = "BUNDLE_PREVIEW_UNAVAILABLE"
            #if DEBUG
            print("[SupportDiagnostics] BUNDLE_PREVIEW_UNAVAILABLE")
            #endif
        }
    }

    @MainActor
    private var currentToken: DiagnosticAuthorizationLoadToken? {
        DiagnosticAuthorizationLoadToken.capture(
            state: viewModel.state,
            accountID: viewModel.currentAccountID,
            requiredCapability: .bundleExport
        )
    }

    @MainActor
    private func clearLoadedContent() {
        snapshot = nil
        loadedToken = nil
        errorMessage = nil
    }

    private func displayMessage(for safeErrorCode: String) -> String {
        safeErrorCode == "BUNDLE_PREVIEW_UNAVAILABLE"
            ? "The preview could not be loaded. Pull to refresh and try again."
            : "Diagnostics are temporarily unavailable."
    }
}
