//
//  WorkoutEnrichmentPushSheet.swift
//  AmakaFlow
//
//  AMA-2336 — the offer shown before a Garmin push when a workout is missing
//  something the user has asked for (spec §5).
//  AMA-2362 — Apple Start uses Open-rest copy + open default (not Garmin Lap).
//  AMA-2371 — Peloton-style toggle rows + live "Add N & send" (redesign 2026-08-02).
//

import SwiftUI

struct WorkoutEnrichmentPushSheet: View {
    let plan: WorkoutEnrichmentPushPlanner.Plan
    let prefs: WorkoutPreferences
    let onConfirm: (WorkoutEnrichmentPushPlanner.Decision) -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    @State private var checkedKinds: Set<EnrichmentKind>
    @State private var restSec: Int
    @State private var restOpen: Bool

    private var target: EnrichmentPushTarget { plan.target }

    init(
        plan: WorkoutEnrichmentPushPlanner.Plan,
        prefs: WorkoutPreferences,
        onConfirm: @escaping (WorkoutEnrichmentPushPlanner.Decision) -> Void,
        onSkip: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.plan = plan
        self.prefs = prefs
        self.onConfirm = onConfirm
        self.onSkip = onSkip
        self.onClose = onClose
        _checkedKinds = State(initialValue: plan.defaultCheckedKinds)
        _restSec = State(initialValue: prefs.betweenSetRest.restSec ?? 60)
        _restOpen = State(
            initialValue: WorkoutEnrichmentPushCopy.initialRestOpen(
                standing: prefs.betweenSetRest,
                target: plan.target
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DailyDriver.borderStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack(alignment: .top) {
                Text(WorkoutEnrichmentPushCopy.sheetTitle)
                    .ddDisplayText(17, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close enrichment offers")
                .accessibilityIdentifier("af_enrichment_push_close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(WorkoutEnrichmentPushCopy.introText(target: target))
                        .font(.system(size: 11.5))
                        .foregroundColor(DailyDriver.foregroundMuted)

                    ForEach(plan.offers) { offer in
                        offerRow(offer)
                    }

                    Text("Whatever you pick is saved to this workout — your watch builds the file when it downloads.")
                        .font(.system(size: 10))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(.top, 2)

                    Button {
                        onConfirm(decision)
                    } label: {
                        Text(WorkoutEnrichmentPushCopy.primaryCTA(checkedCount: checkedKinds.count))
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                    .accessibilityIdentifier("af_enrichment_push_confirm")

                    Button(action: onSkip) {
                        Text(WorkoutEnrichmentPushCopy.sendAsIsCTA)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_enrichment_push_skip")
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .background(DailyDriver.screenBackground)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("af_enrichment_push_sheet")
    }

    private var decision: WorkoutEnrichmentPushPlanner.Decision {
        WorkoutEnrichmentPushPlanner.Decision(
            checkedKinds: checkedKinds,
            restSecOverride: checkedKinds.contains(.betweenSetRest) && !restOpen ? restSec : nil,
            restOpenOverride: checkedKinds.contains(.betweenSetRest) ? restOpen : nil
        )
    }

    private func offerRow(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> some View {
        let isChecked = checkedKinds.contains(offer.kind)
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: checkedBinding(for: offer.kind)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.title)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(detail(for: offer))
                        .font(.system(size: 10.5))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .monospacedDigit()
                        .multilineTextAlignment(.leading)
                    // Default-unchecked + tombstoned = true re-opt-in. Partial
                    // warm-up-sets offers stay checked and must not warn.
                    if offer.wasTombstoned, !offer.isChecked {
                        Text("You removed this before — tick to add it back.")
                            .font(.system(size: 10))
                            .foregroundColor(DailyDriver.amber)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .tint(DailyDriver.lime)
            .accessibilityIdentifier("af_enrichment_push_offer_\(offer.kind.rawValue)")
            .accessibilityAddTraits(isChecked ? [.isSelected] : [])

            if offer.kind == .betweenSetRest, isChecked {
                restOverride
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
    }

    private var restOverride: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: restOpenBinding) {
                Text(WorkoutEnrichmentPushCopy.restOpenSegmentLabel(target: target)).tag(true)
                Text(WorkoutEnrichmentPushCopy.restTimedSegmentLabel).tag(false)
            }
            .pickerStyle(.segmented)
            .tint(DailyDriver.lime)
            .accessibilityIdentifier("af_enrichment_push_rest_open")

            if !restOpen {
                Stepper(
                    "\(restSec)s",
                    value: restSecBinding,
                    in: 15...300,
                    step: 15
                )
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundMuted)
                .monospacedDigit()
                .accessibilityIdentifier("af_enrichment_push_rest_sec")
            }
        }
        .padding(.leading, 28)
    }

    private var restOpenBinding: Binding<Bool> {
        Binding(
            get: { restOpen },
            set: { restOpen = $0 }
        )
    }

    private var restSecBinding: Binding<Int> {
        Binding(
            get: { restSec },
            set: { restSec = $0 }
        )
    }

    /// The rest row shows the live override so the user sees what will be sent.
    private func detail(for offer: WorkoutEnrichmentPushPlanner.Offer) -> String {
        guard offer.kind == .betweenSetRest, checkedKinds.contains(.betweenSetRest) else {
            return offer.detail
        }
        return WorkoutEnrichmentPushCopy.liveRestDetail(
            restOpen: restOpen,
            restSec: restSec,
            target: target
        )
    }

    private func checkedBinding(for kind: EnrichmentKind) -> Binding<Bool> {
        Binding(
            get: { checkedKinds.contains(kind) },
            set: { isOn in
                if isOn {
                    checkedKinds.insert(kind)
                } else {
                    checkedKinds.remove(kind)
                }
            }
        )
    }
}

#if DEBUG
#Preview("Garmin") {
    WorkoutEnrichmentPushSheet(
        plan: WorkoutEnrichmentPushPlanner.Plan(
            offers: [
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .sessionWarmup,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "Jump Rope · until Lap",
                    target: .garmin
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .betweenSetRest,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "60s between sets",
                    target: .garmin
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .exerciseWarmupSets,
                    isChecked: false,
                    wasTombstoned: true,
                    detail: "2 warm-up sets (8 · 5 reps) on 3 exercises",
                    target: .garmin
                )
            ],
            target: .garmin
        ),
        prefs: .defaults,
        onConfirm: { _ in },
        onSkip: {},
        onClose: {}
    )
    .presentationDetents([.large])
}

#Preview("Apple") {
    WorkoutEnrichmentPushSheet(
        plan: WorkoutEnrichmentPushPlanner.Plan(
            offers: [
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .sessionWarmup,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "Jump Rope · until tap",
                    target: .apple
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .betweenSetRest,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "Open rest between sets",
                    target: .apple
                )
            ],
            target: .apple
        ),
        prefs: .defaults,
        onConfirm: { _ in },
        onSkip: {},
        onClose: {}
    )
    .presentationDetents([.large])
}
#endif
