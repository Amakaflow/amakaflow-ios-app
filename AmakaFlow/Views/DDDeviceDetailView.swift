//
//  DDDeviceDetailView.swift
//  AmakaFlow
//
//  Daily Driver device detail — dd-device-dark.png (DDDeviceScreen ~L2135).
//

import SwiftUI

struct DDDeviceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionToggles: [String: Bool] = Dictionary(
        uniqueKeysWithValues: DDDeviceFixture.sessionTypes.map { ($0.key, $0.defaultOn) }
    )
    @State private var showingImportEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backButton
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 0) {
                    Text(DDDeviceFixture.statusLine)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.lime)
                        .padding(.top, 8)

                    Text(DDDeviceFixture.deviceName)
                        .ddDisplayText(28, weight: .heavy)
                        .foregroundColor(DailyDriver.foreground)
                        .padding(.top, 6)

                    batteryHero
                        .padding(.top, 18)

                    Text("Queue")
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .padding(.top, 24)
                        .padding(.bottom, 10)

                    deliveredQueueCard
                    failedQueueCard
                        .padding(.top, 8)

                    Text("Sessions on this watch")
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .padding(.top, 20)

                    Text("Toggled-off types default to your other watch or the phone. Override per workout with a long-press on Push.")
                        .font(.system(size: 11))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.top, 2)
                        .padding(.bottom, 10)

                    sessionToggleCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 100)
            }
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showingImportEditor) {
            DDEditorView(mode: .importReview)
                .ddSuppressFloatingChrome()
        }
        .accessibilityIdentifier("dd_device_detail_screen")
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text("Back")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(DailyDriver.foregroundMuted)
        }
        .buttonStyle(.plain)
    }

    private var batteryHero: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(DDDeviceFixture.batteryPercent)")
                .ddDisplayText(64, weight: .heavy)
                .foregroundColor(DailyDriver.lime)
            Text("%")
                .ddDisplayText(20, weight: .heavy)
                .foregroundColor(DailyDriver.lime)
            Text(DDDeviceFixture.batteryCaption)
                .font(.system(size: 12))
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.leading, 4)
        }
    }

    private var deliveredQueueCard: some View {
        HStack(spacing: 12) {
            DDIconChip(systemName: "checkmark", background: DailyDriver.lime, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(DDDeviceFixture.deliveredTitle)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(DDDeviceFixture.deliveredTime)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.lime)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var failedQueueCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                DDIconChip(systemName: "xmark", background: DailyDriver.red, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DDDeviceFixture.failedTitle)
                        .ddDisplayText(13, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text("FAILED")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.destructive)
                }
                Spacer(minLength: 0)
            }

            Text(DDDeviceFixture.failedReason)
                .font(.system(size: 11.5))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(3)
                .padding(.top, 9)

            Button { showingImportEditor = true } label: {
                Text("Fix in editor →")
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(DailyDriver.card2)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.destructive.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sessionToggleCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(DDDeviceFixture.sessionTypes.enumerated()), id: \.element.key) { index, session in
                sessionRow(
                    title: session.title,
                    icon: session.icon,
                    color: sessionColor(for: session.key),
                    key: session.key,
                    isFirst: index == 0
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sessionColor(for key: String) -> Color {
        switch key {
        case "Hyrox / HIIT": return DailyDriver.lime
        case "Runs": return DailyDriver.blue
        case "Strength": return DailyDriver.purple
        default: return DailyDriver.card2
        }
    }

    private func sessionRow(title: String, icon: String, color: Color, key: String, isFirst: Bool) -> some View {
        HStack(spacing: 12) {
            DDIconChip(systemName: icon, background: color, size: 34)
            Text(title)
                .ddDisplayText(14, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { sessionToggles[key, default: false] },
                set: { sessionToggles[key] = $0 }
            ))
            .labelsHidden()
            .tint(DailyDriver.lime)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(DailyDriver.border).frame(height: 1)
            }
        }
    }
}

#if DEBUG
#Preview("Device detail") {
    NavigationStack {
        DDDeviceDetailView()
    }
    .preferredColorScheme(.dark)
}
#endif
