//
//  WatchItemSheet+Parts.swift
//  AmakaFlow
//
//  AMA-2388: extracted Watch Item sheet subviews (SwiftLint type_body_length).
//

import SwiftUI

struct WatchItemOnWatchCard: View {
    @ObservedObject var viewModel: WatchItemViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(viewModel.onWatchLabel)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.snapshotPills, id: \.self) { pill in
                        Text(pill)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(DailyDriver.card2)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 10)
            .padding(.bottom, 9)

            Button {
                viewModel.showingStepsOverlay = true
            } label: {
                HStack {
                    Text(WatchItemCopy.seeSteps(count: viewModel.stepCount))
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(DailyDriver.lime)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DailyDriver.lime)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_watchitem_see_steps")
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DailyDriver.border)
                    .frame(height: 1)
            }
        }
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 12)
        .accessibilityIdentifier("af_watchitem_onwatch_card")
    }
}

struct WatchItemLibraryRow: View {
    @ObservedObject var viewModel: WatchItemViewModel
    var onOpenWorkout: (() -> Void)?

    var body: some View {
        Group {
            if viewModel.isLinkedToLibrary,
               let name = viewModel.libraryWorkoutTitle,
               onOpenWorkout != nil {
                Button {
                    onOpenWorkout?()
                } label: {
                    content(
                        title: WatchItemCopy.libraryRowTitle(workoutName: name),
                        muted: false
                    )
                }
                .buttonStyle(.plain)
            } else if viewModel.isLinkedToLibrary, let name = viewModel.libraryWorkoutTitle {
                // Linked but no open callback — show name, not a dead tap target.
                content(title: name, muted: false)
            } else {
                content(title: WatchItemCopy.notLinked, muted: true)
            }
        }
        .accessibilityIdentifier("af_watchitem_library_row")
    }

    private func content(title: String, muted: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundDim)
            VStack(alignment: .leading, spacing: 1) {
                Text(WatchItemCopy.fromYourLibrary)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                Text(title)
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(muted ? DailyDriver.foregroundDim : DailyDriver.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(DailyDriver.border)
        )
    }
}

struct WatchItemPinnedActionBar: View {
    @ObservedObject var viewModel: WatchItemViewModel
    var onRemove: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DailyDriver.border)
                .frame(height: 1)
            VStack(spacing: 0) {
                Button {
                    Task { await viewModel.replace() }
                } label: {
                    Text(viewModel.replaceCTATitle())
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(
                            viewModel.canReplace || viewModel.isReplacing
                                ? DailyDriver.ink
                                : DailyDriver.foregroundDim
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            viewModel.canReplace || viewModel.isReplacing
                                ? DailyDriver.lime
                                : DailyDriver.card2
                        )
                        .clipShape(Capsule())
                        .modifier(WatchItemReplaceGlow(active: viewModel.canReplace))
                        .opacity(viewModel.isReplacing ? 0.75 : 1)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canReplace)
                .accessibilityIdentifier("af_watchitem_replace")

                Text(viewModel.applyNote)
                    .font(.system(size: 9.5))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 7)
                    .accessibilityIdentifier("af_watchitem_apply_note")

                Button {
                    onRemove?()
                } label: {
                    Text(WatchItemCopy.removeFromWatch)
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.red)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isReplacing)
                .padding(.top, 9)
                .accessibilityIdentifier("af_watchitem_remove")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .background(DailyDriver.playerDockBackground.opacity(0.96))
        }
    }
}

struct WatchItemReplaceGlow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.ddLimeGlow()
        } else {
            content
        }
    }
}
