//
//  SZStravaBadge.swift
//  AmakaFlow
//
//  AMA-2396: per-session Strava write-state badge (rig panels 3–4).
//  ours → STRAVA ✓ OURS · skipped → STRAVA · SKIPPED · untouched → STRAVA · UNTOUCHED
//  none → renders nothing (never write to a session with no Strava involvement).
//

import SwiftUI

struct SZStravaBadge: View {
    let decoration: StravaDecorationState

    var body: some View {
        if let label = decoration.badgeLabel {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(background)
                .clipShape(Capsule(style: .continuous))
                .accessibilityIdentifier("af_actuals_strava_badge_\(decoration.prototypeKey ?? "none")")
        }
    }

    private var foreground: Color {
        switch decoration {
        case .ours: return DailyDriver.ink
        case .skipped, .untouched: return DailyDriver.foregroundDim
        case .none: return .clear
        }
    }

    private var background: Color {
        switch decoration {
        case .ours: return DailyDriver.stravaBrand
        case .skipped, .untouched: return DailyDriver.card2
        case .none: return .clear
        }
    }
}

#if DEBUG
#Preview("Strava badge states") {
    VStack(alignment: .leading, spacing: 10) {
        SZStravaBadge(decoration: .ours)
        SZStravaBadge(decoration: .skipped(rule: .virtual))
        SZStravaBadge(decoration: .untouched)
        SZStravaBadge(decoration: .none)
    }
    .padding(24)
    .background(DailyDriver.screenBackground)
    .preferredColorScheme(.dark)
}
#endif
