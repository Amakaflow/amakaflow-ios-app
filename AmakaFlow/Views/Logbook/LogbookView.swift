//
//  LogbookView.swift
//  AmakaFlow
//
//  AMA-2426: notebook grid — SET · LAST TIME · KG · REPS · ✓ (rig panel 2).
//

import SwiftUI

// swiftlint:disable:next type_body_length
struct LogbookView: View {
    @ObservedObject var viewModel: LogbookViewModel
    var onBack: (() -> Void)?
    var onSaved: ((ActualsFillInSession) -> Void)?

    @State private var noteText: String = ""
    /// Sheet detent height — keep scroll inset + park slot in sync.
    private static let wheelSheetHeight: CGFloat = 420
    /// Fixed vertical park for the active set (fraction of the area above the sheet).
    private static let focusParkY: CGFloat = 0.32
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        ForEach(viewModel.draft.entries) { entry in
                            exerciseCard(entry)
                        }
                        notesCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 120)
                }
                // Shrink the scroll viewport by the sheet so scrollTo anchors stay
                // in the same on-screen slot above the wheels on every Next set ›.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if viewModel.wheelFocus != nil {
                        Color.clear.frame(height: Self.wheelSheetHeight)
                    }
                }
                .onChange(of: viewModel.wheelFocus) { oldFocus, focus in
                    guard let focus else { return }
                    // First open: wait for sheet present. Later advances: park immediately.
                    let delay: TimeInterval = oldFocus == nil ? 0.16 : 0.02
                    scrollToFocusedSet(proxy: proxy, focus: focus, delay: delay)
                }
            }

            if viewModel.wheelFocus == nil {
                saveCTA
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .accessibilityIdentifier(LogbookCopy.screenAccessibilityID)
        .sheet(isPresented: Binding(
            get: { viewModel.wheelFocus != nil },
            set: { if !$0 { viewModel.wheelFocus = nil } }
        )) {
            LogbookWheelSheet(viewModel: viewModel)
                .presentationDetents([.height(Self.wheelSheetHeight), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(Self.wheelSheetHeight)))
        }
        .sheet(isPresented: $viewModel.showRPE) {
            logbookRPESheet
        }
        .fullScreenCover(isPresented: $viewModel.showVerifiedPayoff) {
            if let session = viewModel.lastVerifiedSession {
                ActualsVerifiedView(session: session)
            }
        }
        .onAppear {
            noteText = viewModel.draft.note
            // Settings unit — live convert display, never rewrite canonical kg.
            viewModel.setWeightUnit(WeightUnit.stored)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            viewModel.setWeightUnit(WeightUnit.stored)
        }
        .overlay(alignment: .bottom) {
            if viewModel.undoToastVisible {
                Button(LogbookCopy.undoTimeoutToast) {
                    do {
                        try viewModel.undoTimeoutCommit()
                    } catch {
                        DDToastCenter.shared.error(ActualsCopy.fillInSaveFailedTitle)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DailyDriver.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DailyDriver.lime)
                .clipShape(Capsule())
                .padding(.bottom, 88)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                viewModel.persistDraft()
                if let onBack { onBack() } else { dismiss() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Session")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)

            Text("\(viewModel.draft.title) — log")
                .ddDisplayText(20, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 8)

            Text(viewModel.headerMeta)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.top, 4)
        }
        .padding(.top, 10)
    }

    // MARK: - Exercise card

    private func exerciseCard(_ entry: LogbookExerciseEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name)
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Spacer()
                Text(entry.plannedLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
            }

            if let tag = entry.supersetTag {
                Text(tag)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.blue)
            }

            if entry.isMetric {
                metricCard(entry)
            } else {
                columnHeader
                ForEach(entry.sets) { set in
                    setRow(entry: entry, set: set)
                        .id(Self.setAnchorID(
                            exerciseID: entry.id,
                            setIndex: set.index,
                            isWarmup: set.isWarmup
                        ))
                }
                Button {
                    viewModel.addSet(exerciseID: entry.id)
                } label: {
                    Text(LogbookCopy.addSet)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text(LogbookCopy.columnSet)
                .frame(width: 36, alignment: .leading)
            Text(LogbookCopy.columnLast)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(LogbookCopy.columnWeight(for: viewModel.weightUnit))
                .frame(width: 52, alignment: .center)
            Text(LogbookCopy.columnReps)
                .frame(width: 44, alignment: .center)
            Text("✓")
                .frame(width: 28, alignment: .center)
        }
        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
        .foregroundColor(DailyDriver.foregroundDim)
    }

    private func setRow(entry: LogbookExerciseEntry, set: SetActual) -> some View {
        let ghost = viewModel.ghost(for: entry.id, setIndex: set.index)
        let focused = viewModel.wheelFocus?.exerciseID == entry.id
            && viewModel.wheelFocus?.setIndex == set.index
            && viewModel.wheelFocus?.isWarmup == set.isWarmup
        return HStack(spacing: 0) {
            if set.isWarmup {
                Text("W")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(DailyDriver.amber)
                    .frame(width: 36, alignment: .leading)
            } else {
                Text("\(set.index)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(focused ? DailyDriver.lime : DailyDriver.foregroundMuted)
                    .frame(width: 36, alignment: .leading)
            }

            Button {
                viewModel.copyGhost(exerciseID: entry.id, setIndex: set.index, isWarmup: set.isWarmup)
            } label: {
                Text(ghost?.displayLine(unit: viewModel.weightUnit) ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            cellButton(
                text: set.weightKg.map { WeightUnitMath.formatWeight(kg: $0, unit: viewModel.weightUnit) },
                ghost: ghost.flatMap { $0.weightKg.map { WeightUnitMath.formatWeight(kg: $0, unit: viewModel.weightUnit) } },
                width: 52
            ) {
                viewModel.openWheel(exerciseID: entry.id, setIndex: set.index, isWarmup: set.isWarmup)
            }

            cellButton(
                text: set.reps.map(String.init),
                ghost: ghost.flatMap { $0.reps.map(String.init) },
                width: 44
            ) {
                viewModel.openWheel(exerciseID: entry.id, setIndex: set.index, isWarmup: set.isWarmup)
            }

            Button {
                viewModel.toggleCheck(exerciseID: entry.id, setIndex: set.index, isWarmup: set.isWarmup)
            } label: {
                ZStack {
                    Circle()
                        .stroke(set.isChecked ? DailyDriver.lime : DailyDriver.borderStrong, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if set.isChecked {
                        Circle()
                            .fill(DailyDriver.lime)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DailyDriver.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .accessibilityIdentifier("af_logbook_check_\(entry.id)_\(set.index)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(focused ? DailyDriver.lime.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(focused ? DailyDriver.lime.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .accessibilityAddTraits(focused ? .isSelected : [])
    }

    private static func setAnchorID(exerciseID: String, setIndex: Int, isWarmup: Bool) -> String {
        "logbook_set_\(exerciseID)_\(setIndex)_\(isWarmup ? "w" : "s")"
    }

    private func scrollToFocusedSet(
        proxy: ScrollViewProxy,
        focus: LogbookWheelFocus,
        delay: TimeInterval
    ) {
        let anchor = Self.setAnchorID(
            exerciseID: focus.exerciseID,
            setIndex: focus.setIndex,
            isWarmup: focus.isWarmup
        )
        // One park only — same screen slot every Next set › (not .top then mid).
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(
                    anchor,
                    anchor: UnitPoint(x: 0.5, y: Self.focusParkY)
                )
            }
        }
    }

    private func cellButton(
        text: String?,
        ghost: String?,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text ?? ghost ?? "—")
                .font(.system(size: 13, weight: text == nil ? .regular : .semibold, design: .monospaced))
                .foregroundColor(text == nil ? DailyDriver.foregroundDim : DailyDriver.foreground)
                .frame(width: width, alignment: .center)
                .padding(.vertical, 6)
                .background(DailyDriver.card2.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func metricCard(_ entry: LogbookExerciseEntry) -> some View {
        let set = entry.sets.first
        let ghost = set.flatMap { viewModel.ghost(for: entry.id, setIndex: $0.index) }
        let focused = viewModel.wheelFocus?.exerciseID == entry.id
        let duration = set?.durationSeconds ?? ghost?.durationSeconds ?? entry.plannedDurationSeconds
        let calories = set?.calories ?? ghost?.calories ?? entry.plannedCalories
        let distance = set?.distanceMeters
            ?? ghost?.distanceMeters
            ?? entry.plannedDistanceMeters.map(Double.init)
        let checked = set?.isChecked == true

        return VStack(alignment: .leading, spacing: 8) {
            if let note = entry.cardioStrip?.sourceNote {
                Text(note)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.lime)
            }
            HStack(alignment: .center, spacing: 8) {
                metricTapCell(
                    label: LogbookCopy.columnTime,
                    value: duration.map(LogbookMetricFormat.duration),
                    focused: focused
                ) {
                    if let set {
                        viewModel.openWheel(exerciseID: entry.id, setIndex: set.index, isWarmup: set.isWarmup)
                    }
                }
                metricTapCell(
                    label: LogbookCopy.columnCal,
                    value: calories.map { "\($0)" },
                    focused: focused
                ) {
                    if let set {
                        viewModel.openWheel(exerciseID: entry.id, setIndex: set.index, isWarmup: set.isWarmup)
                    }
                }
                if distance != nil || entry.plannedDistanceMeters != nil {
                    metricTapCell(
                        label: LogbookCopy.columnKm,
                        value: distance.map(LogbookMetricFormat.distanceKm),
                        focused: focused
                    ) {
                        if let set {
                            viewModel.openWheel(exerciseID: entry.id, setIndex: set.index, isWarmup: set.isWarmup)
                        }
                    }
                }
                if let hr = entry.cardioStrip?.heartRateText {
                    metricTapCell(label: LogbookCopy.columnHr, value: hr, focused: false, action: nil)
                }
                Button {
                    if let set {
                        viewModel.toggleCheck(exerciseID: entry.id, setIndex: set.index, isWarmup: set.isWarmup)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(checked ? DailyDriver.lime : DailyDriver.borderStrong, lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                        if checked {
                            Circle()
                                .fill(DailyDriver.lime)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(DailyDriver.ink)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 28)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(focused ? DailyDriver.lime.opacity(0.14) : Color.clear)
            )
            .id(set.map {
                Self.setAnchorID(exerciseID: entry.id, setIndex: $0.index, isWarmup: $0.isWarmup)
            })
        }
    }

    private func metricTapCell(
        label: String,
        value: String?,
        focused: Bool,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                Text(value ?? "—")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(focused ? DailyDriver.lime : DailyDriver.foreground)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LogbookCopy.notesPlaceholder)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
            TextField("Session note", text: $noteText, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 13))
                .foregroundColor(DailyDriver.foreground)
                .onChange(of: noteText) { _, value in
                    viewModel.setNote(value)
                }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundColor(DailyDriver.borderStrong)
        )
    }

    private var saveCTA: some View {
        Button {
            viewModel.beginSave()
        } label: {
            Text(viewModel.saveCTATitle)
                .ddDisplayText(14, weight: .bold)
                .foregroundColor(viewModel.canProceedToRPE ? DailyDriver.ink : DailyDriver.foregroundDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(viewModel.canProceedToRPE ? DailyDriver.lime : DailyDriver.card2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canProceedToRPE)
        .accessibilityIdentifier(LogbookCopy.saveAccessibilityID)
    }

    private var logbookRPESheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ActualsCopy.fillInRPEHeader)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.top, 20)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(1...10, id: \.self) { value in
                    Button {
                        viewModel.selectRPE(value)
                    } label: {
                        Text("\(value)")
                            .ddDisplayText(16, weight: .bold)
                            .foregroundColor(
                                viewModel.draft.rpe == value ? DailyDriver.ink : DailyDriver.foreground
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(viewModel.draft.rpe == value ? DailyDriver.lime : DailyDriver.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(ActualsCopy.fillInRPEAccessibilityID(value))
                }
            }

            Button {
                do {
                    switch try viewModel.saveVerified() {
                    case .verified(let session):
                        onSaved?(session)
                    case .companionPendingPersisted:
                        // Draft stays pending for watch reconcile — dismiss notepad.
                        if let onBack { onBack() } else { dismiss() }
                    }
                } catch {
                    DDToastCenter.shared.error(ActualsCopy.fillInSaveFailedTitle)
                }
            } label: {
                Text(viewModel.draft.rpe.map { "Save session · RPE \($0)" } ?? "Pick RPE to save")
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(viewModel.draft.rpe == nil ? DailyDriver.foregroundDim : DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(viewModel.draft.rpe == nil ? DailyDriver.card2 : DailyDriver.lime)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.draft.rpe == nil)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 18)
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
