import Combine
import SwiftUI

@MainActor
final class AgentInboxViewModel: ObservableObject {
    @Published var actions: [AgentAction] = []
    @Published var isLoading = false
    /// Guards approve/reject/undo so a double-tap can't fire concurrent mutating calls.
    @Published var isOperating = false
    @Published var apiErrorDisplay: APIErrorDisplayState?

    private let apiErrorState = APIErrorState()
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .current) {
        self.dependencies = dependencies
    }

    var needsYou: [AgentAction] {
        actions.filter { $0.decisionRequired || $0.status == .pending }
    }

    var coachDid: [AgentAction] {
        actions.filter { $0.status == .applied }
    }

    var historyTail: [AgentAction] {
        actions.filter { $0.status == .rejected || $0.status == .undone }
    }

    func load() async {
        isLoading = true
        apiErrorDisplay = nil
        apiErrorState.clear()

        do {
            actions = try await dependencies.apiService.fetchAgentActions(status: nil)
        } catch {
            print("[AgentInboxViewModel] load failed: \(error)")
            apiErrorState.present(error)
            apiErrorDisplay = apiErrorState.current
        }

        isLoading = false
    }

    func approve(id: String) async {
        await respond(id: id, decision: "approve")
    }

    func reject(id: String) async {
        await respond(id: id, decision: "reject")
    }

    func undo(id: String) async {
        guard !isOperating else { return }
        isOperating = true
        defer { isOperating = false }
        apiErrorDisplay = nil
        apiErrorState.clear()

        do {
            _ = try await dependencies.apiService.undoAction(id: id)
            await load()
        } catch {
            print("[AgentInboxViewModel] undo failed: \(error)")
            apiErrorState.present(error)
            apiErrorDisplay = apiErrorState.current
        }
    }

    private func respond(id: String, decision: String) async {
        guard !isOperating else { return }
        isOperating = true
        defer { isOperating = false }
        apiErrorDisplay = nil
        apiErrorState.clear()

        do {
            _ = try await dependencies.apiService.respondToAction(id: id, decision: decision)
            await load()
        } catch {
            print("[AgentInboxViewModel] respond failed: \(error)")
            apiErrorState.present(error)
            apiErrorDisplay = apiErrorState.current
        }
    }
}

struct AgentInboxView: View {
    let onDismiss: () -> Void
    @StateObject private var viewModel: AgentInboxViewModel

    init(dependencies: AppDependencies = .current, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: AgentInboxViewModel(dependencies: dependencies))
    }

    var body: some View {
        VStack(spacing: 0) {
            AFTopBar(title: "Agent inbox", subtitle: "Review what the coach needs and what it already did.") {
                Button(action: onDismiss) { Image(systemName: "chevron.left") }
            } right: {
                Button("Done", action: onDismiss).font(Theme.Typography.captionBold)
            }

            Group {
                if viewModel.isLoading && viewModel.actions.isEmpty {
                    ProgressView("Loading inbox...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let apiError = viewModel.apiErrorDisplay {
                    apiErrorView(apiError)
                } else if viewModel.actions.isEmpty {
                    emptyState
                } else {
                    inboxSections
                }
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .task { await viewModel.load() }
    }

    private var inboxSections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                actionSection(
                    title: "Needs you",
                    subtitle: "Approve or reject coach decisions before they apply.",
                    actions: viewModel.needsYou,
                    emptyText: "No pending decisions.",
                    style: .needsYou
                )

                actionSection(
                    title: "Coach did this",
                    subtitle: "Auto-applied actions from your coach.",
                    actions: viewModel.coachDid,
                    emptyText: "No auto-applied actions yet.",
                    style: .coachDid
                )

                if !viewModel.historyTail.isEmpty {
                    actionSection(
                        title: "History",
                        subtitle: "Rejected and undone decisions.",
                        actions: viewModel.historyTail,
                        emptyText: "",
                        style: .history
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .refreshable { await viewModel.load() }
    }

    private func actionSection(
        title: String,
        subtitle: String,
        actions: [AgentAction],
        emptyText: String,
        style: AgentActionCard.Style
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            if actions.isEmpty {
                Text(emptyText)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.md)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(actions) { action in
                        AgentActionCard(
                            action: action,
                            style: style,
                            onApprove: { Task { await viewModel.approve(id: action.id) } },
                            onReject: { Task { await viewModel.reject(id: action.id) } },
                            onUndo: { Task { await viewModel.undo(id: action.id) } }
                        )
                        .disabled(viewModel.isOperating)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "tray")
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Colors.textTertiary)
            Text("No agent actions yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text("Coach decisions will appear here when the backend records actions.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.lg)
    }

    private func apiErrorView(_ error: APIErrorDisplayState) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(Theme.Colors.accentOrange)
            Text("Couldn’t load agent inbox")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(error.message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(AFPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
    }
}

private struct AgentActionCard: View {
    enum Style {
        case needsYou
        case coachDid
        case history
    }

    let action: AgentAction
    let style: Style
    let onApprove: () -> Void
    let onReject: () -> Void
    let onUndo: () -> Void

    var body: some View {
        AFCard(padding: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Image(systemName: iconName(for: action.kind))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                        .frame(width: 36, height: 36)
                        .background(iconColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(alignment: .top) {
                            Text(action.title)
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(style == .history ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                            Spacer()
                            AFChip(text: action.status.rawValue.capitalized, outline: true)
                        }

                        if let preview = action.preview, !preview.isEmpty {
                            Text(preview)
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }

                        if let rationale = action.rationale, !rationale.isEmpty {
                            Text(rationale)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineSpacing(Theme.Spacing.xs)
                        }
                    }
                }

                verbRow
            }
            .opacity(style == .history ? 0.68 : 1.0)
        }
    }

    @ViewBuilder
    private var verbRow: some View {
        if style == .needsYou {
            HStack(spacing: Theme.Spacing.sm) {
                Button("Approve", action: onApprove)
                    .buttonStyle(AFPrimaryButtonStyle())
                Button("Reject", action: onReject)
                    .buttonStyle(AFGhostButtonStyle())
            }
        } else if style == .coachDid && action.reversible {
            Button("Undo", action: onUndo)
                .buttonStyle(AFGhostButtonStyle())
        }
    }

    private var iconColor: Color {
        switch action.riskLevel {
        case .high:
            return Theme.Colors.accentRed
        case .medium:
            return Theme.Colors.accentOrange
        case .low:
            return Theme.Colors.accentGreen
        case .unknown, nil:
            return Theme.Colors.accentBlue
        }
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case let value where value.contains("move") || value.contains("schedule"):
            return "calendar.badge.clock"
        case let value where value.contains("downgrade") || value.contains("recovery"):
            return "arrow.down.circle"
        case let value where value.contains("rest"):
            return "bed.double.fill"
        case let value where value.contains("week") || value.contains("plan"):
            return "calendar"
        case let value where value.contains("session") || value.contains("workout"):
            return "figure.run"
        default:
            return "sparkles"
        }
    }
}

#Preview {
    AgentInboxView(onDismiss: {})
        .preferredColorScheme(.dark)
}
