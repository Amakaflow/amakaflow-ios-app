//
//  AppleWatchScheduledListView.swift
//  AmakaFlow
//
//  AMA-2375: Apple Watch scheduled list + Peloton-style edit mode.
//  Reuses AMA-2330 WorkoutScheduleViewModel / WorkoutKitScheduleManaging.
//

import SwiftUI

// swiftlint:disable:next type_body_length
struct AppleWatchScheduledListView: View {
    @StateObject private var viewModel: WorkoutScheduleViewModel
    @State private var didLoad = false
    @State private var showRemoveAllConfirm = false
    @State private var moveTarget: WorkoutScheduleRow?
    @State private var moveDate = Date()
    @State private var watchItemRow: WorkoutScheduleRow?
    @State private var watchItemDetent: PresentationDetent = .large
    var onScheduleFromLibrary: (() -> Void)?
    var onOpenWorkoutFromWatchItem: ((String) -> Void)?

    private let calendar: Calendar

    init(
        viewModel: WorkoutScheduleViewModel? = nil,
        calendar: Calendar = .current,
        onScheduleFromLibrary: (() -> Void)? = nil,
        onOpenWorkoutFromWatchItem: ((String) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? Self.defaultViewModel())
        self.calendar = calendar
        self.onScheduleFromLibrary = onScheduleFromLibrary
        self.onOpenWorkoutFromWatchItem = onOpenWorkoutFromWatchItem
    }

    private static func defaultViewModel() -> WorkoutScheduleViewModel {
        #if DEBUG
        if OnYourWatchesDemoSupport.isEnabled {
            return WorkoutScheduleViewModel(scheduler: OnYourWatchesDemoSupport.makeAppleScheduler())
        }
        #endif
        if #available(iOS 18.0, *) {
            return WorkoutScheduleViewModel(scheduler: LiveWorkoutKitScheduler())
        }
        #if DEBUG
        return WorkoutScheduleViewModel(scheduler: MockWorkoutKitScheduler())
        #else
        return WorkoutScheduleViewModel(scheduler: UnavailableWorkoutKitScheduler())
        #endif
    }

    private var rows: [WorkoutScheduleRow] {
        viewModel.incompleteRows + viewModel.completedRows
    }

    var body: some View {
        ZStack {
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topChrome
                if let status = viewModel.statusMessage, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DailyDriver.amber)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .accessibilityIdentifier("af_apple_scheduled_status")
                }
                listBody
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerCTA
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(DailyDriver.screenBackground.opacity(0.001))
        }
        .navigationBarHidden(true)
        .ddSuppressFloatingChrome()
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.refresh(mode: .manual)
        }
        .sheet(item: $moveTarget) { row in
            moveSheet(for: row)
        }
        .sheet(item: $watchItemRow) { row in
            WatchItemSheet(
                viewModel: WatchItemViewModel.apple(row: row, calendar: calendar),
                onRemove: {
                    let target = row
                    watchItemRow = nil
                    Task {
                        await viewModel.delete(row: target)
                        DDToastCenter.shared.undo(
                            DDToastCopy.removedFromWatch,
                            sub: DDToastCopy.libraryUntouched
                        ) {}
                    }
                },
                onOpenWorkout: {
                    watchItemRow = nil
                    onOpenWorkoutFromWatchItem?(row.id.planID)
                },
                onSeeSteps: {
                    // Task 5: read-only preview. Toast placeholder for now.
                    DDToastCenter.shared.device("Opens the read-only step preview — not the editor")
                }
            )
            // Same as Make it watch-ready: open large so readiness rows +
            // nested configurators aren't clipped in a medium detent.
            .presentationDetents([.large, .medium], selection: $watchItemDetent)
            .presentationDragIndicator(.visible)
            .presentationBackground(DailyDriver.screenBackground)
        }
        .confirmationDialog(
            OnYourWatchesCopy.appleRemoveAllTitle,
            isPresented: $showRemoveAllConfirm,
            titleVisibility: .visible
        ) {
            Button(OnYourWatchesCopy.appleRemoveAllConfirm(count: rows.count), role: .destructive) {
                Task {
                    await viewModel.clearAll()
                    let cleared = viewModel.incompleteRows.isEmpty && viewModel.completedRows.isEmpty
                    if cleared {
                        viewModel.exitEditing()
                    }
                }
            }
            .accessibilityIdentifier("af_apple_scheduled_remove_all_confirm")
            Button(OnYourWatchesCopy.cancel, role: .cancel) {}
                .accessibilityIdentifier("af_apple_scheduled_remove_all_cancel")
        } message: {
            Text(OnYourWatchesCopy.appleRemoveAllBody(count: rows.count))
        }
    }

    private var topChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                OnYourWatchesBackLabel(title: "Watches")
                Spacer()
                Button {
                    if viewModel.isEditing {
                        viewModel.exitEditing()
                    } else {
                        viewModel.enterEditing()
                    }
                } label: {
                    Text(viewModel.isEditing ? OnYourWatchesCopy.done : OnYourWatchesCopy.edit)
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(viewModel.isEditing ? DailyDriver.lime : DailyDriver.foregroundMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.isEditing
                                ? DailyDriver.lime.opacity(0.16)
                                : DailyDriver.card2
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isMutating || rows.isEmpty)
                .accessibilityIdentifier("af_apple_scheduled_edit")
            }

            Text(OnYourWatchesCopy.appleTitle)
                .ddDisplayText(24, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 8)

            Text(
                OnYourWatchesCopy.appleSummaryLine(
                    scheduled: rows.count,
                    durationLabel: nil,
                    slotsFree: max(0, viewModel.maxAllowedCount - rows.count)
                )
            )
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.top, 6)
            .accessibilityIdentifier("af_apple_scheduled_summary")

            slotMeter
                .padding(.top, 8)

            Text(
                "\(OnYourWatchesCopy.appleCapFootnotePrefix) \(viewModel.maxAllowedCount) \(OnYourWatchesCopy.appleCapFootnoteSuffix)"
            )
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundDim)
            .padding(.top, 5)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var slotMeter: some View {
        GeometryReader { geo in
            let cap = max(viewModel.maxAllowedCount, 1)
            let fraction = min(1, CGFloat(rows.count) / CGFloat(cap))
            let nearCap = viewModel.maxAllowedCount > 0 && rows.count >= viewModel.maxAllowedCount - 2
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(nearCap ? DailyDriver.amber : DailyDriver.lime)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityIdentifier("af_apple_scheduled_slot_meter")
    }

    private var listBody: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if viewModel.authDenied {
                    Text("Allow Workout scheduling in Settings to manage Apple Watch plans.")
                        .font(.system(size: 12))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.vertical, 20)
                } else if viewModel.showEmptyState {
                    Text(WorkoutScheduleCopy.emptyState)
                        .font(.system(size: 12))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.vertical, 20)
                        .accessibilityIdentifier("af_apple_scheduled_empty")
                } else {
                    ForEach(rows) { row in
                        rowCard(row)
                    }
                }

                Text(OnYourWatchesCopy.appleOwnership)
                    .font(.system(size: 10.5))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable { await viewModel.refresh(mode: .manual) }
    }

    private func rowCard(_ row: WorkoutScheduleRow) -> some View {
        Group {
            if viewModel.isEditing {
                rowCardContent(row)
            } else {
                Button {
                    watchItemDetent = .large
                    watchItemRow = row
                } label: {
                    rowCardContent(row)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("af_apple_scheduled_row_\(row.id.planID)")
    }

    private func rowCardContent(_ row: WorkoutScheduleRow) -> some View {
        HStack(spacing: 11) {
            if viewModel.isEditing {
                Button {
                    Task { await viewModel.delete(row: row) }
                } label: {
                    ZStack {
                        Circle().fill(DailyDriver.red).frame(width: 22, height: 22)
                        Text("−")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_apple_scheduled_remove_\(row.id.planID)")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .lineLimit(1)
                Text(whenLine(for: row))
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(row.scheduledAt == nil ? DailyDriver.amber : DailyDriver.foregroundMuted)
            }

            Spacer(minLength: 0)

            if viewModel.isEditing {
                Button {
                    moveDate = row.scheduledAt ?? Date()
                    moveTarget = row
                } label: {
                    Text(OnYourWatchesCopy.move)
                        .ddDisplayText(11.5, weight: .bold)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DailyDriver.card2)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_apple_scheduled_move_\(row.id.planID)")
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footerCTA: some View {
        Group {
            if viewModel.isEditing {
                Button {
                    showRemoveAllConfirm = true
                } label: {
                    Text(OnYourWatchesCopy.appleRemoveAll)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(DailyDriver.destructive.opacity(0.18))
                        .overlay(
                            Capsule().stroke(DailyDriver.destructive.opacity(0.5), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(rows.isEmpty || viewModel.isMutating)
                .accessibilityIdentifier("af_apple_scheduled_remove_all")
            } else {
                Button {
                    onScheduleFromLibrary?()
                } label: {
                    Text(OnYourWatchesCopy.appleScheduleCTA)
                        .ddDisplayText(14.5, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(DailyDriver.lime)
                        .clipShape(Capsule())
                        .ddLimeGlow()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_apple_scheduled_from_library")
            }
        }
    }

    @ViewBuilder
    private func moveSheet(for row: WorkoutScheduleRow) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker(
                    "New schedule",
                    selection: $moveDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)

                Text("Moves this plan by removing it and scheduling again at the new time. Your Library is unchanged.")
                    .font(.system(size: 12))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.horizontal)

                if let status = viewModel.statusMessage, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DailyDriver.amber)
                        .padding(.horizontal)
                        .accessibilityIdentifier("af_apple_scheduled_move_status")
                }

                Spacer()
            }
            .navigationTitle("Move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(OnYourWatchesCopy.cancel) { moveTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.move(row: row, to: moveDate) {
                                moveTarget = nil
                            }
                        }
                    }
                    .accessibilityIdentifier("af_apple_scheduled_move_save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func whenLine(for row: WorkoutScheduleRow) -> String {
        guard let date = row.scheduledAt else {
            return OnYourWatchesCopy.unscheduled
        }
        let day: String
        if calendar.isDateInToday(date) {
            day = "TODAY"
        } else if calendar.isDateInTomorrow(date) {
            day = "TOMORROW"
        } else {
            day = Self.weekdayFormatter.string(from: date).uppercased()
        }
        let time = Self.timeFormatter.string(from: date)
        let complete = row.isComplete ? " · DONE" : ""
        return "\(day) · \(time)\(complete)"
    }
}
