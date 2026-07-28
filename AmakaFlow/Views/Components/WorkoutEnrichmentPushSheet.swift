//
//  WorkoutEnrichmentPushSheet.swift
//  AmakaFlow
//
//  AMA-2336 — the offer shown before a Garmin push when a workout is missing
//  something the user has asked for (spec §5).
//
//  Kinds already present by type are never offered. Kinds the user deleted
//  before are offered **unchecked** — accepting is an explicit re-opt-in that
//  clears the tombstone.
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
    @State private var restEdited = false

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
        _restOpen = State(initialValue: prefs.betweenSetRest.restOpen)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DailyDriver.borderStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack(alignment: .top) {
                Text("Add before sending?")
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
                    Text("This workout is missing a few things you usually want.")
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
                        Text(checkedKinds.isEmpty ? "Send as it is" : "Add and send")
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                    .accessibilityIdentifier("af_enrichment_push_confirm")

                    Button(action: onSkip) {
                        Text("Skip — send as it is")
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
            restSecOverride: restEdited && !restOpen ? restSec : nil,
            restOpenOverride: restEdited ? restOpen : nil
        )
    }

    private func offerRow(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> some View {
        let isChecked = checkedKinds.contains(offer.kind)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggle(offer.kind)
            } label: {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17))
                        .foregroundColor(isChecked ? DailyDriver.lime : DailyDriver.foregroundMuted)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(offer.title)
                            .ddDisplayText(14, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                        Text(detail(for: offer))
                            .font(.system(size: 10.5))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .multilineTextAlignment(.leading)
                        if offer.wasTombstoned {
                            Text("You removed this before — tick to add it back.")
                                .font(.system(size: 10))
                                .foregroundColor(DailyDriver.amber)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
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
                .stroke(isChecked ? DailyDriver.lime.opacity(0.6) : DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
    }

    private var restOverride: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Rest until I press Lap", isOn: restOpenBinding)
                .tint(DailyDriver.lime)
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundMuted)
                .accessibilityIdentifier("af_enrichment_push_rest_open")

            if !restOpen {
                Stepper(
                    "\(restSec)s rest",
                    value: restSecBinding,
                    in: 15...600,
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
            set: { newValue in
                restOpen = newValue
                restEdited = true
            }
        )
    }

    private var restSecBinding: Binding<Int> {
        Binding(
            get: { restSec },
            set: { newValue in
                restSec = newValue
                restEdited = true
            }
        )
    }

    /// The rest row shows the live override so the user sees what will be sent.
    private func detail(for offer: WorkoutEnrichmentPushPlanner.Offer) -> String {
        guard offer.kind == .betweenSetRest, restEdited else { return offer.detail }
        return restOpen ? "Rest until Lap between sets" : "\(restSec)s between sets"
    }

    private func toggle(_ kind: EnrichmentKind) {
        if checkedKinds.contains(kind) {
            checkedKinds.remove(kind)
        } else {
            checkedKinds.insert(kind)
        }
    }
}

#if DEBUG
#Preview {
    WorkoutEnrichmentPushSheet(
        plan: WorkoutEnrichmentPushPlanner.Plan(
            offers: [
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .sessionWarmup,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "Jump Rope · until Lap",
                    tombstonedExerciseIds: []
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .betweenSetRest,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "60s between sets",
                    tombstonedExerciseIds: []
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .exerciseWarmupSets,
                    isChecked: false,
                    wasTombstoned: true,
                    detail: "2 warm-up sets (8 · 5 reps) on 3 exercises",
                    tombstonedExerciseIds: ["wex_1"]
                )
            ]
        ),
        prefs: .defaults,
        onConfirm: { _ in },
        onSkip: {},
        onClose: {}
    )
    .presentationDetents([.large])
}
#endif
