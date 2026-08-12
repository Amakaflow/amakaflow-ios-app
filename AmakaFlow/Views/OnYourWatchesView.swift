//
//  OnYourWatchesView.swift
//  AmakaFlow
//
//  AMA-2375: overview — one card per paired watch.
//

import SwiftUI

struct OnYourWatchesView: View {
    @StateObject private var viewModel: OnYourWatchesViewModel
    @State private var didLoad = false
    /// Shown on the back chip (`< Library` from Library, `< Today` from Today).
    private let backTitle: String

    init(viewModel: OnYourWatchesViewModel? = nil, backTitle: String = "Library") {
        _viewModel = StateObject(wrappedValue: viewModel ?? OnYourWatchesViewModel())
        self.backTitle = backTitle
    }

    var body: some View {
        ZStack {
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if viewModel.snapshot.showsApple {
                            NavigationLink(value: LibraryDestination.appleScheduled) {
                                appleCard
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("af_on_your_watches_apple")
                        }

                        if viewModel.snapshot.showsGarmin {
                            NavigationLink(value: LibraryDestination.garminQueue) {
                                garminCard
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("af_on_your_watches_garmin")
                        }

                        if !viewModel.snapshot.hasAnyWearable {
                            emptyWearables
                        }

                        Text(OnYourWatchesCopy.overviewFootnote)
                            .font(.system(size: 10.5))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .lineSpacing(2)
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 96)
                }
            }
        }
        .navigationBarHidden(true)
        .ddSuppressFloatingChrome()
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.refresh()
        }
        // Child Apple/Garmin screens stay pushed on top; this view stays alive, so
        // re-run overview counts when WorkoutKit schedule mutations post.
        .onReceive(NotificationCenter.default.publisher(for: .appleWatchScheduleDidChange)) { _ in
            Task { await viewModel.refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Back is provided by the Library NavigationStack chrome via swipe / system —
            // match mock with an explicit label using dismiss environment when pushed.
            OnYourWatchesBackLabel(title: backTitle)
            Text(OnYourWatchesCopy.overviewTitle)
                .ddDisplayText(26, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 8)
            Text(OnYourWatchesCopy.overviewSubtitle)
                .font(.system(size: 11.5))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("af_on_your_watches_header")
    }

    private var appleCard: some View {
        let snap = viewModel.snapshot
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                DDIconChip(systemName: "applewatch", background: DailyDriver.card2, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(OnYourWatchesCopy.appleTitle)
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(
                        OnYourWatchesCopy.appleOverviewSub(
                            scheduled: snap.appleScheduledCount,
                            nextLabel: snap.appleNextLabel
                        )
                    )
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }

            slotMeter(
                filled: snap.appleScheduledCount,
                max: max(snap.appleMaxAllowed, 1),
                nearCap: snap.appleScheduledCount >= snap.appleMaxAllowed - 2
            )
            .padding(.top, 11)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var garminCard: some View {
        let snap = viewModel.snapshot
        return HStack(spacing: 12) {
            DDIconChip(systemName: "applewatch.watchface", background: DailyDriver.blue, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(OnYourWatchesCopy.garminTitle)
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(
                    OnYourWatchesCopy.garminOverviewSub(
                        onWatch: snap.garminOnWatch,
                        waiting: snap.garminWaiting,
                        failed: snap.garminFailed
                    )
                )
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyWearables: some View {
        Text("No watches paired yet — connect Apple Watch or Garmin from Devices.")
            .font(.system(size: 12))
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("af_on_your_watches_empty")
    }

    private func slotMeter(filled: Int, max: Int, nearCap: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(nearCap ? DailyDriver.amber : DailyDriver.lime)
                        .frame(width: geo.size.width * CGFloat(filled) / CGFloat(max))
                }
            }
            .frame(height: 5)

            Text(
                "\(filled) \(OnYourWatchesCopy.appleSlotsOf) \(max) \(OnYourWatchesCopy.appleSlotsLabel) · \(OnYourWatchesCopy.appleCapsShort)"
            )
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundDim)
        }
    }
}

/// Compact back chip that matches the mock (`< Library`) without fighting NavigationStack.
struct OnYourWatchesBackLabel: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(DailyDriver.foregroundMuted)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_on_your_watches_back")
    }
}

/// AMA-2418: Today watch pill — same overview as Library, with local destinations
/// so Apple / Garmin drill-down works outside Library's NavigationStack.
struct TodayOnYourWatchesView: View {
    @StateObject private var viewModel = OnYourWatchesViewModel()

    var body: some View {
        OnYourWatchesView(viewModel: viewModel, backTitle: "Today")
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .appleScheduled:
                    AppleWatchScheduledListView(
                        libraryWorkouts: [],
                        onScheduleFromLibrary: {},
                        onOpenWorkoutFromWatchItem: { _ in }
                    )
                case .garminQueue:
                    GarminWatchQueueView(
                        onPushFromLibrary: {},
                        onFix: { _ in },
                        onOpenWorkoutFromWatchItem: { _ in }
                    )
                case .libraryPick(let target):
                    WatchLibraryPickView(target: target) { _ in }
                default:
                    EmptyView()
                }
            }
            .accessibilityIdentifier("af_today_on_your_watches")
    }
}

// MARK: - Library door chrome

struct LibraryWatchHeaderButton: View {
    let badgeCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "applewatch")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DailyDriver.foreground)
                    .frame(width: 38, height: 38)
                    .background(DailyDriver.card2)
                    .clipShape(Circle())

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DailyDriver.ink)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(DailyDriver.lime)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("On your watches")
        .accessibilityValue(badgeCount > 0 ? "\(badgeCount) items" : "Open")
        .accessibilityIdentifier("af_library_watch_door")
    }
}

struct OnYourWatchesSummaryRow: View {
    let summaryLine: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    DDIconChip(systemName: "applewatch", background: DailyDriver.lime, size: 30)
                    DDIconChip(systemName: "applewatch", background: DailyDriver.blue, size: 30)
                }
                .frame(width: 52, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(OnYourWatchesCopy.librarySummaryTitle)
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(summaryLine)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_library_on_your_watches_row")
    }
}
