//
//  ActualsVerifiedView.swift
//  AmakaFlow
//
//  AMA-2387: verified session screen — payoff after fill-in save.
//

import SwiftUI

struct ActualsVerifiedView: View {
    let title: String
    let metaLine: String
    let sourceName: String
    let rpe: Int
    let rows: [ActualsVerifiedDeltaRow]

    @Environment(\.dismiss) private var dismiss

    init(session: ActualsFillInSession, sourceName: String = "Strava", metaLine: String? = nil) {
        self.title = session.title
        self.sourceName = sourceName
        self.rpe = session.rpe ?? 0
        self.rows = ActualsVerifiedDeltas.rows(from: session.exercises)
        if let metaLine {
            self.metaLine = metaLine
        } else {
            let rpeText = session.rpe.map { " · RPE \($0)" } ?? ""
            self.metaLine = "\(session.subtitle) · FROM \(sourceName.uppercased())\(rpeText)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)

                ActualsVerifiedCard(
                    sourceName: sourceName,
                    rpe: rpe,
                    rows: rows
                )
                .padding(.top, 12)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            HStack(spacing: 12) {
                DDIconChip(systemName: "dumbbell.fill", background: DailyDriver.purple, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .ddDisplayText(22, weight: .heavy)
                        .foregroundColor(DailyDriver.foreground)
                    Text(metaLine)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
            }
        }
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
    return ActualsVerifiedView(session: session, sourceName: "Strava", metaLine: "MON 17:20 · 52 MIN · FROM STRAVA")
}
#endif
