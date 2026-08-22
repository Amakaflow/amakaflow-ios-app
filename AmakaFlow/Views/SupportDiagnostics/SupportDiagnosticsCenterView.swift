import SwiftUI

struct SupportDiagnosticsCenterView: View {
    @ObservedObject var viewModel: SupportDiagnosticsViewModel

    var body: some View {
        NavigationStack {
            List {
                accessSection
                capabilitySection
            }
            .navigationTitle("Support Diagnostics")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.dismissCenter()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.pollWhilePresented()
        }
    }

    @ViewBuilder
    private var accessSection: some View {
        if let authorization = viewModel.authorization {
            Section("Authorized access") {
                LabeledContent("Role", value: authorization.role.rawValue.capitalized)
                if let expiresAt = authorization.expiresAt {
                    LabeledContent("Expires", value: expiresAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    @ViewBuilder
    private var capabilitySection: some View {
        if let authorization = viewModel.authorization {
            Section {
                statusRow(authorization: authorization)
                capabilityRow(
                    title: "Logs",
                    systemImage: "doc.text.magnifyingglass",
                    capability: .logsRead,
                    authorization: authorization
                )
                capabilityRow(
                    title: "Export",
                    systemImage: "square.and.arrow.up",
                    capability: .bundleExport,
                    authorization: authorization
                )
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Sanitized logs and explicit export are added in the next AMA-2510 slices.")
            }
        }
    }

    @ViewBuilder
    private func statusRow(authorization: SupportDiagnosticsAuthorization) -> some View {
        if authorization.capabilities.contains(.statusRead) {
            NavigationLink {
                SupportDiagnosticsStatusView(authorization: authorization)
            } label: {
                capabilityLabel(
                    title: "Status",
                    systemImage: "waveform.path.ecg",
                    isAuthorized: true
                )
            }
        } else {
            capabilityLabel(
                title: "Status",
                systemImage: "waveform.path.ecg",
                isAuthorized: false
            )
        }
    }

    private func capabilityRow(
        title: String,
        systemImage: String,
        capability: SupportDiagnosticsCapability,
        authorization: SupportDiagnosticsAuthorization
    ) -> some View {
        capabilityLabel(
            title: title,
            systemImage: systemImage,
            isAuthorized: authorization.capabilities.contains(capability)
        )
    }

    private func capabilityLabel(
        title: String,
        systemImage: String,
        isAuthorized: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
            Text(title)
            Spacer()
            Image(systemName: isAuthorized ? "checkmark.circle.fill" : "lock.fill")
                .foregroundStyle(isAuthorized ? .green : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func supportDiagnosticsLifecycle(
        viewModel: SupportDiagnosticsViewModel,
        accountID: String?,
        isAuthenticated: Bool,
        scenePhase: ScenePhase
    ) -> some View {
        modifier(
            SupportDiagnosticsLifecycleModifier(
                viewModel: viewModel,
                accountID: accountID,
                isAuthenticated: isAuthenticated,
                scenePhase: scenePhase
            )
        )
    }
}

private struct SupportDiagnosticsLifecycleModifier: ViewModifier {
    @ObservedObject var viewModel: SupportDiagnosticsViewModel
    let accountID: String?
    let isAuthenticated: Bool
    let scenePhase: ScenePhase

    func body(content: Content) -> some View {
        content
            .environmentObject(viewModel)
            .task(id: accountID) {
                viewModel.updateAccount(isAuthenticated ? accountID : nil)
            }
            .onChange(of: accountID) { _, newAccountID in
                viewModel.updateAccount(isAuthenticated ? newAccountID : nil)
            }
            .onChange(of: isAuthenticated) { _, authenticated in
                viewModel.updateAccount(authenticated ? accountID : nil)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await viewModel.appDidBecomeActive()
                }
            }
    }
}
