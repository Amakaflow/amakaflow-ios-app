//
//  GarminWatchQueueView.swift
//  AmakaFlow
//
//  AMA-2375: Garmin widget queue — ON WATCH / SENT / FAILED rows.
//

import SwiftUI

struct GarminWatchQueueView: View {
    @StateObject private var viewModel: GarminWatchQueueViewModel
    @State private var didLoad = false
    var onPushFromLibrary: (() -> Void)?
    var onFix: ((GarminQueueItem) -> Void)?

    init(
        viewModel: GarminWatchQueueViewModel? = nil,
        onPushFromLibrary: (() -> Void)? = nil,
        onFix: ((GarminQueueItem) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? GarminWatchQueueViewModel())
        self.onPushFromLibrary = onPushFromLibrary
        self.onFix = onFix
    }

    var body: some View {
        ZStack {
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if viewModel.items.isEmpty && !viewModel.isLoading {
                            Text("Nothing in the Garmin queue yet — push a workout from Library or Start.")
                                .font(.system(size: 12))
                                .foregroundColor(DailyDriver.foregroundMuted)
                                .padding(.vertical, 20)
                                .accessibilityIdentifier("af_garmin_queue_empty")
                        } else {
                            ForEach(viewModel.items) { item in
                                queueRow(item)
                            }
                        }

                        Text(OnYourWatchesCopy.garminOwnership)
                            .font(.system(size: 10.5))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 150)
                }
                .refreshable { await viewModel.refresh() }
            }

            VStack {
                Spacer()
                Button {
                    onPushFromLibrary?()
                } label: {
                    Text(OnYourWatchesCopy.garminPushCTA)
                        .ddDisplayText(14.5, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(DailyDriver.lime)
                        .clipShape(Capsule())
                        .ddLimeGlow()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .accessibilityIdentifier("af_garmin_queue_push_from_library")
            }
        }
        .navigationBarHidden(true)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            OnYourWatchesBackLabel(title: "Watches")
            Text(OnYourWatchesCopy.garminTitle)
                .ddDisplayText(24, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 8)
            Text(viewModel.summaryLine)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.lime)
                .padding(.top, 4)
                .accessibilityIdentifier("af_garmin_queue_summary")
            Text(OnYourWatchesCopy.garminIntro)
                .font(.system(size: 11.5))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(2)
                .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private func queueRow(_ item: GarminQueueItem) -> some View {
        HStack(spacing: 12) {
            statusIcon(for: item.state)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .lineLimit(1)
                Text(item.statusLine)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(statusColor(for: item.state))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if item.state == .failed {
                HStack(spacing: 8) {
                    Button {
                        onFix?(item)
                    } label: {
                        Text(OnYourWatchesCopy.garminFix)
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.amber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(DailyDriver.card2)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_garmin_queue_fix_\(item.id)")

                    Button {
                        Task { await viewModel.remove(item: item) }
                    } label: {
                        Text(OnYourWatchesCopy.garminRemove)
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(DailyDriver.card2)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_garmin_queue_remove_\(item.id)")
                }
            } else {
                Button {
                    Task { await viewModel.remove(item: item) }
                } label: {
                    Text(OnYourWatchesCopy.garminRemove)
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DailyDriver.card2)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_garmin_queue_remove_\(item.id)")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    item.state == .failed
                        ? DailyDriver.destructive.opacity(0.45)
                        : DailyDriver.border,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("af_garmin_queue_row_\(item.id)")
    }

    private func statusIcon(for state: GarminQueueItemState) -> some View {
        let (icon, color): (String, Color) = {
            switch state {
            case .onWatch: return ("checkmark", DailyDriver.lime)
            case .waiting: return ("clock", DailyDriver.amber)
            case .failed: return ("xmark", DailyDriver.red)
            }
        }()
        return DDIconChip(systemName: icon, background: color, size: 28)
    }

    private func statusColor(for state: GarminQueueItemState) -> Color {
        switch state {
        case .onWatch: return DailyDriver.lime
        case .waiting: return DailyDriver.amber
        case .failed: return DailyDriver.red
        }
    }
}
