//
//  StructureClarifyView.swift
//  AmakaFlow
//
//  AMA-2305 — "Check the structure" intervene step (ADR-017).
//  Ground truth: design-handoff/screenshots/rig-clarify-states.png
//  + design-handoff/reference/screens-clarify.jsx
//

import SwiftUI

struct StructureClarifyView: View {
    @ObservedObject var viewModel: SocialImportViewModel
    var onBack: (() -> Void)?
    var onSaved: (() -> Void)?

    @State private var describeOpen = false
    @State private var sectionLabelOpen = false
    @State private var sectionLabelDraft = ""
    @FocusState private var sectionLabelFocused: Bool

    private var session: StructureClarifySession {
        viewModel.clarifySession ?? StructureClarifySession()
    }

    private var draft: SocialImportDraft? { viewModel.draft }

    private var selectionActive: Bool { !session.selectedRowIDs.isEmpty }

    /// Extra scroll padding so the last rows clear the sticky chip bar + footer.
    private var scrollBottomPadding: CGFloat {
        selectionActive ? 220 : 140
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.units) { unit in
                            switch unit {
                            case .group(let group):
                                StructureClarifyGroupCard(
                                    group: group,
                                    onConfirm: { viewModel.confirmClarifyGroup(group.id) },
                                    onUndo: { viewModel.undoClarifyGroup(group.id) },
                                    onRounds: { viewModel.bumpClarifyRounds(group.id, delta: $0) }
                                )
                            case .row(let row):
                                StructureClarifyFlatRow(
                                    row: row,
                                    selected: session.selectedRowIDs.contains(row.id)
                                ) {
                                    viewModel.toggleClarifyRow(row.id)
                                }
                            }
                        }

                        describeDoor
                            .padding(.top, 4)

                        Text("Unconfirmed groups save as a flat list — we never guess silently.")
                            .font(.system(size: 10.5))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, scrollBottomPadding)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
            }

            // AMA-2326 I1 — sticky above footer (not inside ScrollView).
            VStack(spacing: 8) {
                if selectionActive {
                    StructureClarifySelectionChipBar(
                        selectedCount: session.selectedRowIDs.count,
                        onGroup: { type, label, allowSingle in
                            viewModel.groupClarifySelection(
                                as: type,
                                label: label,
                                allowSingle: allowSingle
                            )
                        },
                        onOpenSectionLabel: {
                            sectionLabelDraft = ""
                            sectionLabelOpen = true
                        },
                        onCancel: { viewModel.clearClarifySelection() }
                    )
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                footerCTAs
                    .padding(.horizontal, 12)
            }
            .padding(.bottom, 12)
            .animation(.easeInOut(duration: 0.18), value: selectionActive)
        }
        .ddSuppressFloatingChrome()
        .sheet(isPresented: $describeOpen) {
            StructureDescribeSheet(viewModel: viewModel) {
                describeOpen = false
            }
        }
        .sheet(isPresented: $sectionLabelOpen) {
            StructureClarifySectionLabelSheet(
                labelDraft: $sectionLabelDraft,
                isFocused: $sectionLabelFocused,
                onCancel: { sectionLabelOpen = false },
                onApply: { label in
                    viewModel.groupClarifySelection(as: .sets, label: label, allowSingle: true)
                    sectionLabelOpen = false
                }
            )
        }
        .onChange(of: viewModel.phase) { _, phase in
            if case .saved = phase {
                onSaved?()
            }
        }
        .accessibilityIdentifier("structure_clarify_screen")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onBack?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

                Text("Check the structure")
                .ddDisplayText(24, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 10)

            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(2)
                .padding(.top, 5)

            provenanceCard
                .padding(.top, 10)
        }
        .padding(.horizontal, 18)
    }

    private var subtitle: String {
        let count = session.exerciseCount
        return "\(count) exercise\(count == 1 ? "" : "s") found. The grouping was implied, not stated — confirm it so the player runs it right."
    }

    private var provenanceCard: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(DailyDriver.purple)
                    .frame(width: 28, height: 28)
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(draft?.title ?? "Imported workout")
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .lineLimit(1)
                Text(provenanceMono)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if session.pendingGroupCount > 0 {
                Button {
                    viewModel.confirmAllClarifyGroups()
                } label: {
                    Text("✓ Confirm all (\(session.pendingGroupCount))")
                        .ddDisplayText(11, weight: .bold)
                        .foregroundColor(DailyDriver.lime)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("structure_clarify_confirm_all")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var provenanceMono: String {
        let creator = draft?.postProvenance?.creatorDisplay.uppercased() ?? "CREATOR"
        if let method = draft?.postProvenance?.extractionMethodDisplay?.uppercased() {
            return "\(creator) · VIA \(method)"
        }
        let mode = (draft?.postProvenance?.mode ?? "reel caption").uppercased()
        return "\(creator) · \(mode) PARSED"
    }

    // MARK: - Describe

    private var describeDoor: some View {
        Button {
            describeOpen = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Not right? Describe it")
                        .ddDisplayText(13, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text("“bench + pull ups are a superset, finisher is a circuit ×5”")
                        .font(.system(size: 10.5))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DailyDriver.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("structure_clarify_describe_door")
        .padding(.bottom, 12)
    }

    // MARK: - Footer

    private var isSaveInFlight: Bool {
        switch viewModel.phase {
        case .saving, .saved:
            return true
        default:
            return false
        }
    }

    private var footerCTAs: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.saveFromClarify(leaveFlat: true) }
            } label: {
                Text("Leave flat")
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule()
                            .fill(Color(red: 16 / 255, green: 16 / 255, blue: 18 / 255).opacity(0.96))
                    )
                    .overlay(
                        Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isSaveInFlight)
            .opacity(isSaveInFlight ? 0.55 : 1)
            .accessibilityIdentifier("structure_clarify_leave_flat")

            Button {
                Task { await viewModel.saveFromClarify(leaveFlat: false) }
            } label: {
                Text(isSaveInFlight ? "Saving…" : saveLabel)
                    .ddDisplayText(14.5, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(DailyDriver.lime))
            }
            .buttonStyle(.plain)
            .disabled(isSaveInFlight)
            .opacity(isSaveInFlight ? 0.55 : 1)
            .ddLimeGlow()
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            .accessibilityIdentifier("structure_clarify_save")
        }
    }

    private var saveLabel: String {
        let confirmed = session.confirmedGroupCount
        if confirmed > 0 {
            return "Save · \(confirmed) block\(confirmed == 1 ? "" : "s") ✓"
        }
        return "Looks right — Save"
    }
}
