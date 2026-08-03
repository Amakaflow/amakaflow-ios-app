//
//  WatchLibraryPickView.swift
//  AmakaFlow
//
//  AMA-2375: Library pick mode after Schedule/Push CTAs.
//

import SwiftUI

struct WatchLibraryPickView: View {
    let target: WatchLibraryPickTarget
    let onPick: (String) -> Void
    @StateObject private var viewModel = LibraryViewModel()
    @State private var searchText = ""

    private var workouts: [Workout] {
        viewModel.entries.compactMap { entry in
            if case .workout(let workout) = entry { return workout }
            return nil
        }
        .filter {
            searchText.isEmpty
                || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var title: String {
        switch target {
        case .appleSchedule: return "Schedule on Apple Watch"
        case .garminPush: return "Push to Garmin"
        }
    }

    private var subtitle: String {
        switch target {
        case .appleSchedule:
            return "Pick a Library workout — Start opens the Apple schedule preview."
        case .garminPush:
            return "Pick a Library workout — Start opens the Garmin push path."
        }
    }

    var body: some View {
        ZStack {
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    OnYourWatchesBackLabel(title: "Watches")
                    Text(title)
                        .ddDisplayText(22, weight: .heavy)
                        .foregroundColor(DailyDriver.foreground)
                        .padding(.top, 8)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                DDSearchField(text: $searchText)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(workouts) { workout in
                            Button {
                                onPick(workout.id)
                            } label: {
                                let row = DDLibraryPresentation.row(for: workout)
                                DDLibraryRow(
                                    title: workout.name,
                                    metaLine: row.meta,
                                    platform: row.platform,
                                    thumbIcon: row.icon,
                                    gradientColors: row.gradient
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("af_watch_library_pick_\(workout.id)")
                        }

                        if workouts.isEmpty {
                            Text("No workouts in Library yet.")
                                .font(.system(size: 12))
                                .foregroundColor(DailyDriver.foregroundMuted)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
        .task { await viewModel.load() }
        .accessibilityIdentifier("af_watch_library_pick")
    }
}
