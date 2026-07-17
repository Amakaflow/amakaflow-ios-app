//
//  DailyDriverComponents.swift
//  AmakaFlow
//
//  Shared Daily Driver UI primitives — stat tiles, HR zones, banners, CTAs.
//  Ground truth: design-handoff/screenshots/ + DESIGN.md
//

import SwiftUI

// MARK: - Stat grid (activity detail)

struct DDMetricTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .ddDisplayText(20, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct DDMetricGrid: View {
    let tiles: [(String, String)]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(4, max(1, tiles.count))), spacing: 8) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                DDMetricTile(value: tile.0, label: tile.1)
            }
        }
    }
}

// MARK: - HR zones bar

struct DDHRZonesCard: View {
    let zones: [HRZone]
    var note: String?

    private static let zoneColors: [Color] = [
        DailyDriver.blue,
        DailyDriver.zoneGreen,
        DailyDriver.lime,
        DailyDriver.amber,
        DailyDriver.red
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DailyDriver.red)
                Text(displayNote)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Spacer(minLength: 0)
                Text("HR ZONES")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
            }

            if !zones.isEmpty {
                let spacing: CGFloat = 3
                let zoneTotal = zones.reduce(0.0) { $0 + $1.percentageOfWorkout }
                GeometryReader { geo in
                    let segmentCount = zones.count
                    let totalSpacing = spacing * CGFloat(max(segmentCount - 1, 0))
                    let availableWidth = max(0, geo.size.width - totalSpacing)
                    HStack(spacing: spacing) {
                        ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                            let isPeak = zone.percentageOfWorkout == zones.map(\.percentageOfWorkout).max()
                            let share = zoneTotal > 0 ? zone.percentageOfWorkout / zoneTotal : 0
                            RoundedRectangle(cornerRadius: 99, style: .continuous)
                                .fill(Self.zoneColors[safe: index] ?? DailyDriver.card2)
                                .opacity(isPeak ? 1 : 0.45)
                                .frame(width: availableWidth * CGFloat(share))
                        }
                    }
                }
                .frame(height: 10)
                .padding(.top, 11)

                HStack {
                    ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                        Text("Z\(zone.id) · \(Int(zone.percentageOfWorkout.rounded()))%")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 6)
            }
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

    private var displayNote: String {
        if let note, !note.isEmpty { return note }
        if let peak = zones.max(by: { $0.percentageOfWorkout < $1.percentageOfWorkout }), peak.percentageOfWorkout > 0 {
            return "Most time in \(peak.name)"
        }
        return "Heart rate zones"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Status banner (amber / lime)

struct DDStatusBanner: View {
    enum Style {
        case amber(title: String, body: String)
        case lime(title: String, body: String?)
        case verified(title: String, body: String)

        var title: String {
            switch self {
            case .amber(let title, _), .lime(let title, _), .verified(let title, _): return title
            }
        }

        var body: String? {
            switch self {
            case .amber(_, let body): return body
            case .lime(_, let body): return body
            case .verified(_, let body): return body
            }
        }

        var accent: Color {
            switch self {
            case .amber: return DailyDriver.amber
            case .lime, .verified: return DailyDriver.lime
            }
        }

        var titleColor: Color {
            switch self {
            case .verified: return DailyDriver.lime
            case .amber, .lime: return DailyDriver.foreground
            }
        }
    }

    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if case .verified = style {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DailyDriver.lime)
                }
                Text(style.title)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(style.titleColor)
            }
            if let body = style.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 11))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(style.accent.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.accent.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Profile insight banner

struct DDInsightBanner: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                DDIconChip(systemName: "dumbbell.fill", background: DailyDriver.amber, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .ddDisplayText(13, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DailyDriver.amber.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.amber.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_profile_insight_banner")
    }
}

// MARK: - Dual CTA bar (activity detail)

struct DDDualActionBar: View {
    let primaryTitle: String
    let secondaryTitle: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule(style: .continuous))
                    .ddLimeGlow()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_activity_map_primary")

            Button(action: secondaryAction) {
                Text(secondaryTitle)
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DailyDriver.tabBarBackground)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DailyDriver.borderStrong, lineWidth: 1)
                    )
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_activity_map_secondary")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}

// MARK: - Editor sticky save bar

struct DDEditorSaveBar: View {
    let title: String
    var isSaving: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().tint(DailyDriver.ink)
                }
                Text(title)
                    .ddDisplayText(15, weight: .bold)
            }
            .foregroundColor(DailyDriver.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DailyDriver.lime)
            .clipShape(Capsule(style: .continuous))
            .ddLimeGlow()
        }
        .disabled(isSaving)
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .accessibilityIdentifier("dd_editor_save")
    }
}
