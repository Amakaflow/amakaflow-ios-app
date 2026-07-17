//
//  DDGymDetailView.swift
//  AmakaFlow
//
//  Daily Driver gym detail — dd-gym-dark.png (DDGymScreen ~L1457).
//

import SwiftUI

struct DDGymDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShared = true

    private let freeWeights: [(String, Bool)] = [
        ("Dumbbells to 50 kg", true),
        ("Barbells + plates", true),
        ("Kettlebells", true),
        ("EZ bar", false)
    ]
    private let machines: [(String, Bool)] = [
        ("Cable crossover", true),
        ("Leg press", true),
        ("Lat pulldown", true),
        ("Chest-supported row", true),
        ("Hack squat", false)
    ]
    private let cardio: [(String, Bool)] = [
        ("Rower", true),
        ("SkiErg", true),
        ("Assault bike", true),
        ("Sled + turf", false),
        ("Treadmill", true)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backButton
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                        .padding(.top, 8)

                    sharedGymCard
                        .padding(.top, 14)

                    Button {} label: {
                        Text("Set as active gym")
                            .ddDisplayText(14.5, weight: .bold)
                            .foregroundColor(DailyDriver.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(DailyDriver.lime)
                            .clipShape(Capsule(style: .continuous))
                            .ddLimeGlow()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)

                    equipmentSection(title: "FREE WEIGHTS", items: freeWeights)
                    equipmentSection(title: "MACHINES", items: machines)
                    equipmentSection(title: "CARDIO & CONDITIONING", items: cardio)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 100)
            }
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("dd_gym_detail_screen")
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text("My Gyms")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(DailyDriver.foregroundMuted)
        }
        .buttonStyle(.plain)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            DDIconChip(systemName: "map.fill", background: DailyDriver.blue, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("24 Hour Fitness — Katy")
                    .ddDisplayText(22, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                Text("KATY, TX · 1.2 MI AWAY")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
        }
    }

    private var sharedGymCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared gym")
                        .ddDisplayText(13.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text("12 members keep this list in sync — new machines show up for everyone. Nobody enters this gym twice.")
                        .font(.system(size: 11))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .lineSpacing(3)
                        .padding(.top, 2)
                }
                Toggle("", isOn: $isShared)
                    .labelsHidden()
                    .tint(DailyDriver.lime)
            }

            Text("LAST UPDATE · “CABLE CROSSOVER ADDED” · MARIA R · 2D AGO")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.top, 9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(DailyDriver.lime.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.lime.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func equipmentSection(title: String, items: [(String, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.top, 14)

            FlowWrap(spacing: 7) {
                ForEach(items, id: \.0) { item in
                    equipmentChip(label: item.0, isPresent: item.1)
                }
            }
        }
    }

    private func equipmentChip(label: String, isPresent: Bool) -> some View {
        Text(isPresent ? label : "＋ \(label)")
            .ddDisplayText(12, weight: .semibold)
            .foregroundColor(isPresent ? DailyDriver.foreground : DailyDriver.foregroundDim)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(isPresent ? DailyDriver.card2 : Color.clear)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isPresent ? DailyDriver.borderStrong : DailyDriver.border,
                        style: isPresent ? StrokeStyle(lineWidth: 1) : StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .clipShape(Capsule())
    }
}

/// Wrapping chip row for gym equipment tags.
private struct FlowWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

#if DEBUG
#Preview("Gym detail") {
    NavigationStack {
        DDGymDetailView()
    }
    .preferredColorScheme(.dark)
}
#endif
