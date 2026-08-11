//
//  ActualsVerifiedView.swift
//  AmakaFlow
//
//  AMA-2387: verified session screen — payoff after fill-in save.
//  AMA-2396: ⋯ menu (edit / remove from Strava / un-verify / unmatch) + badge.
//

import SwiftUI

struct ActualsVerifiedView: View {
    let title: String
    let metaLine: String
    let sourceName: String
    let rpe: Int
    let rows: [ActualsVerifiedDeltaRow]
    let decoration: StravaDecorationState
    let stravaActivityId: String?
    let stravaCurrentDescription: String

    var onEditActuals: (() -> Void)?
    var onWriteToStrava: (() -> Void)?
    var onRemoveFromStrava: (() -> Void)?
    var onUnverify: (() -> Void)?
    var onUnmatch: (() -> Void)?
    var onStravaDescriptionLoaded: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showMenu = false

    init(
        session: ActualsFillInSession,
        sourceName: String = "Strava",
        metaLine: String? = nil,
        decoration: StravaDecorationState = .none,
        onEditActuals: (() -> Void)? = nil,
        onWriteToStrava: (() -> Void)? = nil,
        onRemoveFromStrava: (() -> Void)? = nil,
        onUnverify: (() -> Void)? = nil,
        onUnmatch: (() -> Void)? = nil,
        onStravaDescriptionLoaded: ((String) -> Void)? = nil
    ) {
        self.title = session.title
        self.sourceName = sourceName
        self.rpe = session.rpe ?? 0
        self.rows = ActualsVerifiedDeltas.rows(from: session.exercises)
        self.decoration = decoration
        self.stravaActivityId = session.stravaActivityId
        self.stravaCurrentDescription = session.stravaCurrentDescription ?? ""
        self.onEditActuals = onEditActuals
        self.onWriteToStrava = onWriteToStrava
        self.onRemoveFromStrava = onRemoveFromStrava
        self.onUnverify = onUnverify
        self.onUnmatch = onUnmatch
        self.onStravaDescriptionLoaded = onStravaDescriptionLoaded
        if let metaLine {
            self.metaLine = metaLine
        } else {
            let rpeText = session.rpe.map { " · RPE \($0)" } ?? ""
            self.metaLine = "\(session.subtitle) · FROM \(sourceName.uppercased())\(rpeText)"
        }
    }

    private var menuRows: [ActualsVerifiedMenuRow] {
        var rows: [ActualsVerifiedMenuRow] = []
        if let onEditActuals {
            rows.append(
                ActualsVerifiedMenuRow(
                    id: "edit",
                    title: ActualsCopy.verifiedMenuEdit,
                    subtitle: ActualsCopy.verifiedMenuEditSub,
                    destructive: false,
                    action: onEditActuals
                )
            )
        }
        if let onWriteToStrava, decoration != .ours {
            rows.append(
                ActualsVerifiedMenuRow(
                    id: "writeStrava",
                    title: ActualsCopy.verifiedMenuWriteStrava,
                    subtitle: ActualsCopy.verifiedMenuWriteStravaSub,
                    destructive: false,
                    action: onWriteToStrava
                )
            )
        }
        // Nothing to remove when we never wrote to Strava.
        if let onRemoveFromStrava, decoration == .ours {
            rows.append(
                ActualsVerifiedMenuRow(
                    id: "removeStrava",
                    title: ActualsCopy.verifiedMenuRemoveStrava,
                    subtitle: ActualsCopy.verifiedMenuRemoveStravaSub,
                    destructive: true,
                    action: onRemoveFromStrava
                )
            )
        }
        if let onUnverify {
            rows.append(
                ActualsVerifiedMenuRow(
                    id: "unverify",
                    title: ActualsCopy.verifiedMenuUnverify,
                    subtitle: ActualsCopy.verifiedMenuUnverifySub,
                    destructive: false,
                    action: onUnverify
                )
            )
        }
        if let onUnmatch {
            rows.append(
                ActualsVerifiedMenuRow(
                    id: "unmatch",
                    title: ActualsCopy.verifiedMenuUnmatch,
                    subtitle: ActualsCopy.verifiedMenuUnmatchSub,
                    destructive: false,
                    action: onUnmatch
                )
            )
        }
        return rows
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)

                if decoration.badgeLabel != nil {
                    SZStravaBadge(decoration: decoration)
                        .padding(.top, 10)
                }

                ActualsVerifiedCard(
                    sourceName: sourceName,
                    rpe: rpe,
                    rows: rows
                )
                .padding(.top, 12)

                // AMA-2405: only when Strava metadata exists and AmakaFlow does
                // not already own the description (`.ours` skips re-fetch).
                if ActualsStravaDescriptionPolicy.showsDescriptionSection(
                    decoration: decoration,
                    stravaActivityId: stravaActivityId,
                    cachedDescription: stravaCurrentDescription
                ) {
                    ActualsStravaDescriptionSection(
                        stravaActivityId: stravaActivityId,
                        initialDescription: stravaCurrentDescription,
                        allowsRemoteFetch: ActualsStravaDescriptionPolicy.allowsRemoteFetch(
                            decoration: decoration
                        ),
                        onLoaded: onStravaDescriptionLoaded
                    )
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .sheet(isPresented: $showMenu) {
            ActualsVerifiedMenuSheet(rows: menuRows) { row in
                showMenu = false
                row.action()
            }
            .presentationDetents([.height(CGFloat(96 + menuRows.count * 64)), .medium])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Today")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(DailyDriver.foregroundMuted)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if !menuRows.isEmpty {
                    Button {
                        showMenu = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .frame(width: 32, height: 32)
                            .background(DailyDriver.card2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(ActualsCopy.verifiedMenuAccessibilityID)
                }
            }

            HStack(spacing: 12) {
                DDIconChip(systemName: "dumbbell.fill", background: DailyDriver.purple, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .ddDisplayText(22, weight: .heavy)
                        .foregroundColor(DailyDriver.foreground)
                    Text(metaLine)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - ⋯ menu

private struct ActualsVerifiedMenuRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let destructive: Bool
    let action: () -> Void
}

private struct ActualsVerifiedMenuSheet: View {
    let rows: [ActualsVerifiedMenuRow]
    var onSelect: (ActualsVerifiedMenuRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(DailyDriver.border)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                ForEach(rows) { row in
                    Button {
                        onSelect(row)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .ddDisplayText(14, weight: .bold)
                                .foregroundColor(row.destructive ? DailyDriver.red : DailyDriver.foreground)
                            Text(row.subtitle)
                                .font(.system(size: 7.5, design: .monospaced))
                                .foregroundColor(DailyDriver.foregroundDim)
                                .lineSpacing(1.5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(DailyDriver.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(DailyDriver.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(ActualsCopy.verifiedMenuAccessibilityID)_\(row.id)")
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 8)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
#Preview("Verified session") {
    var session = ActualsFillInSession.lowerBodyPosteriorSample()
    session.exercises[0].confirmation = .adjusted
    session.exercises[0].actualWeightKg = 90
    for index in 1..<session.exercises.count {
        session.exercises[index].confirmation = .asPlanned
    }
    session.rpe = 8
    session.verified = true
    return ActualsVerifiedView(
        session: session,
        sourceName: "Strava",
        metaLine: "MON 17:20 · 52 MIN · FROM STRAVA",
        decoration: .ours,
        onEditActuals: {},
        onRemoveFromStrava: {},
        onUnverify: {},
        onUnmatch: {}
    )
}
#endif
