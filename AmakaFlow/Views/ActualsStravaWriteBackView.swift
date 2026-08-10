//
//  ActualsStravaWriteBackView.swift
//  AmakaFlow
//
//  AMA-2396 A4: Strava write-back settings — master toggle, skip rules,
//  ownership explainer, and a live preview of what Strava will receive.
//

import SwiftUI

struct ActualsStravaWriteBackView: View {
    @ObservedObject var store: StravaWriteBackSettingsStore
    /// Master toggle flipped ON without the write scope — caller owns the reconnect flow.
    var onReconnect: (() -> Void)?

    init(
        store: StravaWriteBackSettingsStore? = nil,
        onReconnect: (() -> Void)? = nil
    ) {
        self.store = store ?? StravaWriteBackSettingsStore()
        self.onReconnect = onReconnect
    }

    private var masterToggleBinding: Binding<Bool> {
        Binding(
            get: { store.writeBackEnabled },
            set: { newValue in
                if newValue, !store.hasActivityWriteScope {
                    store.writeBackEnabled = false
                    DDToastCenter.shared.present(
                        DDToastEvent(
                            kind: .error,
                            text: ActualsCopy.writeBackReconnectToast,
                            action: "Reconnect",
                            onAction: { onReconnect?() }
                        )
                    )
                } else {
                    store.writeBackEnabled = newValue
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)

                masterToggleRow
                    .padding(.top, 16)

                skipRulesSection
                    .padding(.top, 18)

                ownershipExplainer
                    .padding(.top, 16)

                previewSection
                    .padding(.top, 18)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .accessibilityIdentifier(ActualsCopy.writeBackAccessibilityID)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Strava write-back")
                .ddDisplayText(24, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
            Text(store.statusLine)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(DailyDriver.lime)
        }
    }

    // MARK: - Master toggle

    private var masterToggleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ActualsCopy.writeBackMasterTitle)
                    .ddDisplayText(14.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(ActualsCopy.writeBackMasterSub)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: masterToggleBinding)
                .labelsHidden()
                .tint(DailyDriver.stravaBrand)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("af_actuals_writeback_master")
    }

    // MARK: - Skip rules

    private var skipRulesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(ActualsCopy.writeBackSkipHeader)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)

            VStack(spacing: 8) {
                skipRuleRow(.virtual, isOn: skipVirtualBinding)
                skipRuleRow(.described, isOn: skipDescribedBinding)
                skipRuleRow(.race, isOn: skipRacesBinding)
            }
        }
    }

    private var skipVirtualBinding: Binding<Bool> {
        Binding(get: { store.rules.skipVirtual }, set: { store.rules.skipVirtual = $0 })
    }

    private var skipDescribedBinding: Binding<Bool> {
        Binding(get: { store.rules.skipDescribed }, set: { store.rules.skipDescribed = $0 })
    }

    private var skipRacesBinding: Binding<Bool> {
        Binding(get: { store.rules.skipRaces }, set: { store.rules.skipRaces = $0 })
    }

    private func skipRuleRow(_ rule: StravaWriteBackSkipRule, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.title)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(rule.subtitle)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(DailyDriver.lime)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("af_actuals_writeback_skip_\(rule.rawValue)")
    }

    // MARK: - Ownership explainer

    private var ownershipExplainer: some View {
        Text(ActualsCopy.writeBackOwnershipExplainer)
            .font(.system(size: 7.5, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(DailyDriver.border)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ActualsCopy.writeBackPreviewHeader)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)

            Text(Self.samplePreviewDescription)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DailyDriver.foreground)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DailyDriver.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DailyDriver.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private static let samplePreviewDescription = StravaWriteBackDecorator.previewDescription(
        structureBody: "3×5 Back squat @ 85 kg\n3×8 Romanian deadlift @ 70 kg\n2×10 Split squat",
        rpe: 8
    )
}

#if DEBUG
#Preview("Strava write-back settings") {
    let store = StravaWriteBackSettingsStore(defaults: UserDefaults(suiteName: "preview.writeback")!)
    return ActualsStravaWriteBackView(store: store)
}
#endif
