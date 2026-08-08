//
//  ActualsAppleHealthPrimerView.swift
//  AmakaFlow
//
//  AMA-2387: Apple Health primer — three read types + Turn On All coaching,
//  then the real HealthKit permission sheet (design-handoff screens-actuals3).
//

import SwiftUI

struct ActualsAppleHealthPrimerView<Store: ActualsSourceConnecting>: View where Store: ObservableObject {
    @ObservedObject var store: Store
    var healthKit: any ActualsHealthKitConnecting
    var onFinished: () -> Void

    @State private var isRequesting = false
    @Environment(\.dismiss) private var dismiss

    init(
        store: Store,
        healthKit: any ActualsHealthKitConnecting,
        onFinished: @escaping () -> Void = {}
    ) {
        self.store = store
        self.healthKit = healthKit
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(ActualsCopy.appleHealthTitle)
                    .ddDisplayText(24, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                    .padding(.top, 10)

                (Text(ActualsCopy.appleHealthPrimerLeadPrefix)
                    .foregroundColor(DailyDriver.foregroundMuted)
                 + Text(ActualsCopy.appleHealthPrimerLeadEmphasis)
                    .foregroundColor(DailyDriver.foreground)
                    .fontWeight(.semibold)
                 + Text(ActualsCopy.appleHealthPrimerLeadSuffix)
                    .foregroundColor(DailyDriver.foregroundMuted))
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)

                readTypesCard
                    .padding(.top, 10)

                Text(ActualsCopy.appleHealthTurnOnAllCoach)
                    .font(.system(size: 11))
                    .foregroundColor(DailyDriver.amber)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                Button(action: continueTapped) {
                    HStack {
                        if isRequesting {
                            ProgressView()
                                .tint(DailyDriver.ink)
                        }
                        Text(ActualsCopy.appleHealthContinueCTA)
                            .ddDisplayText(14, weight: .bold)
                    }
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
                .padding(.top, 22)
                .accessibilityIdentifier(ActualsCopy.appleHealthContinueAccessibilityID)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ActualsCopy.appleHealthPrimerAccessibilityID)
    }

    private var readTypesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(ActualsCopy.appleHealthReadTypes.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(DailyDriver.border)
                        .frame(height: 1)
                }
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DailyDriver.lime)
                        .frame(width: 14)

                    Text(row.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(DailyDriver.foreground)

                    Spacer(minLength: 8)

                    Text(row.why)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 9)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 2)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func continueTapped() {
        guard !isRequesting else { return }
        isRequesting = true
        Task { @MainActor in
            let outcome = await healthKit.connect()
            ActualsAppleHealthConnectAction.apply(
                outcome: outcome,
                store: store
            ) {
                healthKit.openHealthSettings()
            }
            if outcome == .granted {
                ActualsLinkFeedback.announceLinked(.appleHealth)
            }
            isRequesting = false
            switch outcome {
            case .granted, .denied:
                onFinished()
                dismiss()
            case .needsSettings:
                // Stay on primer so user can retry after flipping Settings.
                break
            }
        }
    }
}

#if DEBUG
#Preview("Apple Health primer") {
    ActualsAppleHealthPrimerView(
        store: ActualsSourceConnectionStore(),
        healthKit: MockActualsHealthKitConnector()
    )
}
#endif
