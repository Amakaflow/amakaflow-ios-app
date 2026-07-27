//
//  WorkoutScheduleView.swift
//  AmakaFlow
//
//  AMA-2330: Multi-select cleanup UI for WorkoutKit-scheduled plans.
//  Entry (Devices → Scheduled in Workout / Start success → Manage scheduled
//  plans) is wired in a follow-up task; this screen is self-contained.
//

import SwiftUI

// swiftlint:disable type_body_length

/// Exact copy from the AMA-2330 design spec — confirms, empty state, footnote.
/// Centralized so tests and the view read the same strings.
enum WorkoutScheduleCopy {
    static let emptyState = "No AmakaFlow plans in Workout"
    static let watchSyncFootnote = "Changes may take a moment to appear on Apple Watch."
    static let clearAllConfirm =
        "Remove all AmakaFlow plans from the Workout app? This can’t be undone — you can re-schedule any workout from its Start button."

    static func deleteConfirm(count: Int) -> String {
        "Remove \(count) AmakaFlow workout plan(s) from Apple Watch Workout?"
    }
}

struct WorkoutScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WorkoutScheduleViewModel
    @State private var didLoad = false
    @State private var pendingDeleteRow: WorkoutScheduleRow?
    @State private var showDeleteSelectedConfirm = false
    @State private var showClearAllConfirm = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(viewModel: WorkoutScheduleViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? Self.defaultViewModel())
    }

    /// iOS 18+ gets the real WorkoutKit-backed scheduler; the pre-iOS 18 mock
    /// path exists only so this init never crashes — Task 5 hides the entry
    /// point on older OS versions.
    private static func defaultViewModel() -> WorkoutScheduleViewModel {
        if #available(iOS 18.0, *) {
            return WorkoutScheduleViewModel(scheduler: LiveWorkoutKitScheduler())
        }
        #if DEBUG
        return WorkoutScheduleViewModel(scheduler: MockWorkoutKitScheduler())
        #else
        return WorkoutScheduleViewModel(scheduler: UnavailableWorkoutKitScheduler())
        #endif
    }

    private var hasAnyRows: Bool {
        !viewModel.incompleteRows.isEmpty || !viewModel.completedRows.isEmpty
    }

    var body: some View {
        ZStack {
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                actionsBar

                Group {
                    if viewModel.authDenied {
                        authBanner
                    } else if viewModel.isLoading && !hasAnyRows {
                        loadingView
                    } else if viewModel.showEmptyState {
                        emptyView
                    } else {
                        listContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.refresh(mode: .manual)
        }
        .confirmationDialog(
            WorkoutScheduleCopy.deleteConfirm(count: viewModel.selectedCount),
            isPresented: $showDeleteSelectedConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard !viewModel.isMutating else { return }
                Task { await viewModel.deleteSelected() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            WorkoutScheduleCopy.clearAllConfirm,
            isPresented: $showClearAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                guard !viewModel.isMutating else { return }
                Task { await viewModel.clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            WorkoutScheduleCopy.deleteConfirm(count: 1),
            isPresented: Binding(
                get: { pendingDeleteRow != nil },
                set: { if !$0 { pendingDeleteRow = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let row = pendingDeleteRow else { return }
                pendingDeleteRow = nil
                guard !viewModel.isMutating else { return }
                Task { await viewModel.delete(row: row) }
            }
            Button("Cancel", role: .cancel) { pendingDeleteRow = nil }
        }
        .accessibilityIdentifier("af_workout_schedule_screen")
    }

    // MARK: - Top bar / actions

    private var topBar: some View {
        AFTopBar(
            title: "Scheduled in Workout",
            subtitle: headerSubtitle,
            backIdentifier: "af_workout_schedule_back",
            backAction: { dismiss() },
            right: { selectDoneButton }
        )
    }

    private var headerSubtitle: String {
        if viewModel.authDenied { return "Workout access needed" }
        if viewModel.isLoading && !hasAnyRows { return "Loading…" }
        if !hasAnyRows { return "No plans scheduled" }
        let base = "\(viewModel.incompleteRows.count) scheduled · \(viewModel.completedRows.count) completed"
        guard viewModel.isAtScheduleCap else { return base }
        return "\(base) · At Apple's schedule limit"
    }

    @ViewBuilder
    private var selectDoneButton: some View {
        if hasAnyRows {
            Button(viewModel.isEditing ? "Done" : "Select") {
                if viewModel.isEditing {
                    viewModel.exitEditing()
                } else {
                    viewModel.enterEditing()
                }
            }
            .font(Theme.Typography.bodyBold)
            .accessibilityIdentifier("af_workout_schedule_select_done")
        }
    }

    @ViewBuilder
    private var actionsBar: some View {
        if hasAnyRows {
            HStack(spacing: Theme.Spacing.md) {
                Button("Clear all") { showClearAllConfirm = true }
                    .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
                    .disabled(viewModel.isMutating)
                    .accessibilityIdentifier("af_workout_schedule_clear_all")

                Spacer(minLength: 0)

                if viewModel.isEditing && viewModel.selectedCount >= 1 {
                    Button("Delete (\(viewModel.selectedCount))") {
                        showDeleteSelectedConfirm = true
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .sm, isWide: false))
                    .disabled(viewModel.isMutating)
                    .accessibilityIdentifier("af_workout_schedule_delete_selected")
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)
        }
    }

    // MARK: - Auth / loading / empty

    private var authBanner: some View {
        VStack {
            Spacer(minLength: 0)
            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(DailyDriver.amber)
                    Text("Workout access needed")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Allow AmakaFlow to manage scheduled plans in the Workout app to clean up duplicates.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(AFPrimaryButtonStyle(size: .md))
                        .accessibilityIdentifier("af_workout_schedule_open_settings")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("af_workout_schedule_auth_banner")
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(DailyDriver.foreground)
            Text("Loading scheduled plans")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("af_workout_schedule_loading")
    }

    private var emptyView: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(DailyDriver.lime)
                Text(WorkoutScheduleCopy.emptyState)
                    .afH2()
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("af_workout_schedule_empty")
    }

    // MARK: - List

    private var listContent: some View {
        List {
            if !viewModel.incompleteRows.isEmpty {
                Section {
                    ForEach(viewModel.incompleteRows) { row in
                        rowView(row, isCompleted: false)
                    }
                } header: {
                    Text("Scheduled")
                }
            }

            if !viewModel.completedRows.isEmpty {
                Section {
                    ForEach(viewModel.completedRows) { row in
                        rowView(row, isCompleted: true)
                    }
                } header: {
                    Text("Completed")
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    statusMessageView(statusMessage)
                }
            }

            if hasAnyRows {
                Section {
                    Text(WorkoutScheduleCopy.watchSyncFootnote)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("af_workout_schedule_watch_footnote")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DailyDriver.screenBackground)
        .refreshable {
            await viewModel.refresh(mode: .manual)
        }
        .accessibilityIdentifier("af_workout_schedule_list")
    }

    private func rowView(_ row: WorkoutScheduleRow, isCompleted: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            if viewModel.isEditing {
                selectionIndicator(isSelected: viewModel.selectedIDs.contains(row.id))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .afH3()
                    .lineLimit(2)
                Text(relativeSubtitle(for: row, isCompleted: isCompleted))
                    .afMuted()
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .opacity(isCompleted ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard viewModel.isEditing else { return }
            viewModel.toggleSelect(row.id)
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(DailyDriver.border)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: row))
        .accessibilityAddTraits(
            viewModel.isEditing
                ? (viewModel.selectedIDs.contains(row.id) ? [.isButton, .isSelected] : .isButton)
                : []
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !viewModel.isEditing {
                Button(role: .destructive) {
                    pendingDeleteRow = row
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.isMutating)
                .accessibilityIdentifier("af_workout_schedule_swipe_delete_\(row.id.planID)_\(row.id.dateKey)")
            }
        }
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(isSelected ? DailyDriver.lime : DailyDriver.foregroundDim)
    }

    private func statusMessageView(_ message: String) -> some View {
        Text(message)
            .afMuted()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .contentShape(Rectangle())
            .onTapGesture {
                guard viewModel.canRetry, !viewModel.isMutating else { return }
                Task { await viewModel.deleteSelected() }
            }
            .accessibilityIdentifier("af_workout_schedule_status")
    }

    private func relativeSubtitle(for row: WorkoutScheduleRow, isCompleted: Bool) -> String {
        let prefix = isCompleted ? "Completed" : "Scheduled"
        guard let date = row.scheduledAt else { return prefix }
        return "\(prefix) \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func accessibilityLabel(for row: WorkoutScheduleRow) -> String {
        guard let date = row.scheduledAt else { return row.title }
        return "\(row.title), scheduled \(Self.absoluteFormatter.string(from: date))"
    }
}

// swiftlint:enable type_body_length

#if DEBUG
#Preview("Workout Schedule") {
    let mock = MockWorkoutKitScheduler()
    mock.rows = [
        WorkoutScheduleRow(
            id: WorkoutScheduleRowID(planID: "1", date: DateComponents(year: 2026, month: 7, day: 27, hour: 9)),
            title: "5x800m Intervals",
            dateComponents: DateComponents(year: 2026, month: 7, day: 27, hour: 9),
            scheduledAt: Date().addingTimeInterval(3600),
            isComplete: false
        ),
        WorkoutScheduleRow(
            id: WorkoutScheduleRowID(planID: "2", date: DateComponents(year: 2026, month: 7, day: 26, hour: 9)),
            title: "Full Body Strength",
            dateComponents: DateComponents(year: 2026, month: 7, day: 26, hour: 9),
            scheduledAt: Date().addingTimeInterval(-3600 * 20),
            isComplete: true
        )
    ]
    return NavigationStack {
        WorkoutScheduleView(viewModel: WorkoutScheduleViewModel(scheduler: mock))
    }
}
#endif
