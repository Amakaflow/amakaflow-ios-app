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
                capabilityRow(
                    title: "Status",
                    systemImage: "waveform.path.ecg",
                    capability: .statusRead,
                    authorization: authorization
                )
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
                Text("Status, sanitized logs, and explicit export are added in the next AMA-2510 slices.")
            }
        }
    }

    private func capabilityRow(
        title: String,
        systemImage: String,
        capability: SupportDiagnosticsCapability,
        authorization: SupportDiagnosticsAuthorization
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
            Text(title)
            Spacer()
            Image(systemName: authorization.capabilities.contains(capability) ? "checkmark.circle.fill" : "lock.fill")
                .foregroundStyle(authorization.capabilities.contains(capability) ? .green : .secondary)
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
