//
//  ActualsHistoryView.swift
//  AmakaFlow
//
//  AMA-2396: Profile → History — Sync v2. Day-grouped Strava history with the
//  wrong-day bug fixed (bucketed by `start_date_local`, not UTC).
//

import Combine
import SwiftUI

@MainActor
final class ActualsHistoryViewModel: ObservableObject {
    @Published private(set) var dayGroups: [(day: Date, cards: [ActualsTodayDemoCard])] = []
    @Published private(set) var isLoading = false
    @Published private(set) var daysBack = 30
    @Published var bannerExpanded = true

    private let client: BFFStravaClient
    private let calendar: Calendar
    private let now: () -> Date

    init(
        client: BFFStravaClient? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client ?? BFFStravaClient.live()
        self.calendar = calendar
        self.now = now
    }

    nonisolated deinit {}

    var totalSessions: Int {
        dayGroups.reduce(0) { $0 + $1.cards.count }
    }

    var needFillInCount: Int {
        dayGroups.reduce(0) { partial, group in
            partial + group.cards.filter { $0.kind == .unmapped || $0.kind == .fillInDebt || $0.kind == .merged }.count
        }
    }

    func loadIfNeeded() async {
        guard dayGroups.isEmpty, !isLoading else { return }
        await load(replacingExisting: true)
    }

    func loadMore() async {
        let previousDaysBack = daysBack
        let previousGroups = dayGroups
        daysBack += 30
        let ok = await load(replacingExisting: true)
        if !ok {
            // Failed pagination must not erase the window the athlete already has.
            daysBack = previousDaysBack
            dayGroups = previousGroups
        }
    }

    /// Returns `true` when groups were successfully replaced from the network.
    @discardableResult
    private func load(replacingExisting: Bool) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await client.syncCompleted(daysBack: daysBack)
            guard result.success else {
                if replacingExisting, dayGroups.isEmpty {
                    dayGroups = []
                }
                return false
            }
            dayGroups = ActualsTodayDemoFeed.historyCards(
                from: result.activities,
                calendar: calendar,
                now: now()
            )
            return true
        } catch {
            // Never crash History on a missing/expired token — keep what we have.
            if dayGroups.isEmpty {
                dayGroups = []
            }
            return false
        }
    }
}

struct ActualsHistoryView: View {
    @StateObject private var viewModel: ActualsHistoryViewModel

    @MainActor
    init(viewModel: ActualsHistoryViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ActualsHistoryViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)

                banner
                    .padding(.top, 14)

                if viewModel.bannerExpanded {
                    dayList
                        .padding(.top, 14)

                    loadMoreButton
                        .padding(.top, 6)
                }

                legend
                    .padding(.top, 18)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadIfNeeded()
        }
        .accessibilityIdentifier(ActualsCopy.historyAccessibilityID)
    }

    // MARK: - Header

    private var header: some View {
        Text(ActualsCopy.historyTitle)
            .ddDisplayText(28, weight: .heavy)
            .foregroundColor(DailyDriver.foreground)
    }

    // MARK: - Banner

    private var banner: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(
                ActualsCopy.historyPulledBanner(
                    days: viewModel.daysBack,
                    sessions: viewModel.totalSessions,
                    needFillIn: viewModel.needFillInCount
                )
            )
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.bannerExpanded.toggle()
                }
            } label: {
                Text(ActualsCopy.historyBannerShow)
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.lime)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Day list

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 18) {
            if viewModel.isLoading && viewModel.dayGroups.isEmpty {
                ProgressView()
                    .tint(DailyDriver.lime)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if viewModel.dayGroups.isEmpty {
                Text("No sessions in this window.")
                    .font(.system(size: 12))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(viewModel.dayGroups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ActualsDayBucketing.historyDayHeader(for: group.day))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)

                        VStack(spacing: 7) {
                            ForEach(group.cards) { card in
                                dayRow(card)
                                    .accessibilityIdentifier("af_actuals_history_row_\(card.id)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayRow(_ card: ActualsTodayDemoCard) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.title)
                        .ddDisplayText(13, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .lineLimit(1)
                    SZStravaBadge(decoration: card.stravaDecoration)
                }
                Text("\(card.timeLabel) · \(card.sourceLabel.uppercased())")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            rowCTA(for: card)
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

    @ViewBuilder
    private func rowCTA(for card: ActualsTodayDemoCard) -> some View {
        switch card.kind {
        case .unmapped, .fillInDebt, .merged:
            Text(ActualsCopy.historyFillInCTA)
                .ddDisplayText(11.5, weight: .bold)
                .foregroundColor(DailyDriver.amber)
        case .verified:
            Text(ActualsCopy.verifiedTimelineCTA)
                .ddDisplayText(11.5, weight: .bold)
                .foregroundColor(DailyDriver.lime)
        case .counted:
            Text(ActualsCopy.historyCountedCTA)
                .ddDisplayText(11.5, weight: .bold)
                .foregroundColor(DailyDriver.lime)
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await viewModel.loadMore() }
        } label: {
            HStack {
                if viewModel.isLoading {
                    ProgressView().tint(DailyDriver.foregroundMuted)
                }
                Text(ActualsCopy.historyLoadMore)
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DailyDriver.card2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ActualsCopy.historyLegend)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(ActualsCopy.historyLocalTimeFooter)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundColor(DailyDriver.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
