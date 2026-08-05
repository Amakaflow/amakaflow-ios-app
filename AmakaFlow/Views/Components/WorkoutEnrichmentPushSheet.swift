//
//  WorkoutEnrichmentPushSheet.swift
//  AmakaFlow
//
//  AMA-2336 — the offer shown before a Garmin push when a workout is missing
//  something the user has asked for (spec §5).
//  AMA-2362 — Apple Start uses Open-rest copy + open default (not Garmin Lap).
//  AMA-2371 — Peloton-style toggle rows + live "Add N & send" (redesign 2026-08-02).
//  AMA-2378 — v2 rows-as-doors: mobility/cooldown/warm-up-sets rows show a live
//  mono summary and open a configurator; between-set rest keeps its v1 inline
//  anatomy. Toggles retain local config when switched off (design 2026-08-04
//  `make-it-watch-ready-v2-design.md` §Surface 1).
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

    /// v2 door state — local edits, seeded from standing prefs when the sheet
    /// is created and retained even while the row's toggle is off (design
    /// §Surface 1 "retained-config toggles"). Task 4/5 fill in the screens
    /// that actually mutate these; Task 3 only wires the round-trip.
    @State private var mobilityActivities: [EnrichmentActivityPref]
    @State private var cooldownActivities: [EnrichmentActivityPref]
    @State private var perExerciseRamps: [PerExerciseRamp]
    @State private var route: Route?

    private var target: EnrichmentPushTarget { plan.target }

    private enum Route: Hashable {
        case sequence(EnrichmentSequenceKind)
        case warmupPick
    }

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
        _restSec = State(initialValue: WorkoutEnrichmentPushCopy.normalizedRestSec(prefs.betweenSetRest.restSec))
        _restOpen = State(
            initialValue: WorkoutEnrichmentPushCopy.initialRestOpen(
                standing: prefs.betweenSetRest,
                target: plan.target
            )
        )
        _mobilityActivities = State(initialValue: prefs.sessionWarmup.activities)
        _cooldownActivities = State(initialValue: prefs.cooldown.activities)
        _perExerciseRamps = State(initialValue: prefs.exerciseWarmupSets.perExercise ?? [])
    }

    var body: some View {
        NavigationStack {
            sheetBody
                .navigationDestination(item: $route) { route in
                    switch route {
                    case .sequence(let kind):
                        EnrichmentSequenceScreen(
                            activities: kind == .mobility ? $mobilityActivities : $cooldownActivities,
                            kind: kind
                        )
                    case .warmupPick:
                        EnrichmentWarmupPickScreen(
                            ramps: $perExerciseRamps,
                            exercises: warmupCandidateNames,
                            workingSetCounts: plan.offer(.exerciseWarmupSets)?.candidateWorkingSetCounts ?? []
                        )
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

extension WorkoutEnrichmentPushSheet {
    private var sheetBody: some View {
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
                    Text(WorkoutEnrichmentPushCopy.sheetIntroV2)
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
        .navigationBarHidden(true)
        .accessibilityIdentifier("af_enrichment_push_sheet")
    }

    /// AMA-2378 Task 6 — door-screen edits only ride along when their kind is
    /// checked (an unchecked kind's local state stays retained but unsent,
    /// same pattern as the rest override above).
    private var decision: WorkoutEnrichmentPushPlanner.Decision {
        WorkoutEnrichmentPushPlanner.Decision(
            checkedKinds: checkedKinds,
            restSecOverride: checkedKinds.contains(.betweenSetRest) && !restOpen ? restSec : nil,
            restOpenOverride: checkedKinds.contains(.betweenSetRest) ? restOpen : nil,
            sessionWarmupActivities: checkedKinds.contains(.sessionWarmup) ? mobilityActivities : nil,
            cooldownActivities: checkedKinds.contains(.cooldown) ? cooldownActivities : nil,
            perExerciseRamps: checkedKinds.contains(.exerciseWarmupSets) ? perExerciseRamps : nil
        )
    }

    @ViewBuilder
    private func offerRow(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> some View {
        if offer.kind == .betweenSetRest {
            restRow(offer)
        } else {
            doorRow(offer)
        }
    }

    // MARK: - v1 inline rest row (unchanged anatomy — design §Surface 1 exception)

    private func restRow(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> some View {
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

            if isChecked {
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
        .accessibilityIdentifier("af_enhance_row_rest")
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
                    in: WorkoutEnrichmentPushCopy.restSecRange,
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

    /// The rest row shows the live override so the user sees what will be sent.
    private func detail(for offer: WorkoutEnrichmentPushPlanner.Offer) -> String {
        guard checkedKinds.contains(.betweenSetRest) else { return offer.detail }
        return WorkoutEnrichmentPushCopy.liveRestDetail(
            restOpen: restOpen,
            restSec: restSec,
            target: target
        )
    }

    // MARK: - v2 door rows (mobility / cooldown / warm-up sets)

    private func doorRow(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> some View {
        let isChecked = checkedKinds.contains(offer.kind)
        return HStack(spacing: 12) {
            Button {
                route = doorRoute(for: offer.kind)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(offer.title)
                            .ddDisplayText(14, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                        Text(liveSummary(for: offer.kind))
                            .font(Theme.Typography.mono)
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if offer.wasTombstoned, !isChecked {
                            Text("You removed this before — tick to add it back.")
                                .font(.system(size: 10))
                                .foregroundColor(DailyDriver.amber)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(doorRowIdentifier(for: offer.kind))
            .accessibilityHint("Opens the \(offer.title) configurator")

            Toggle("", isOn: checkedBinding(for: offer.kind))
                .labelsHidden()
                .tint(DailyDriver.lime)
                .accessibilityIdentifier("af_enrichment_push_offer_\(offer.kind.rawValue)")
                .accessibilityLabel(offer.title)
                .accessibilityAddTraits(isChecked ? [.isSelected] : [])
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

    private func doorRoute(for kind: EnrichmentKind) -> Route? {
        switch kind {
        case .sessionWarmup: return .sequence(.mobility)
        case .cooldown: return .sequence(.cooldown)
        case .exerciseWarmupSets: return .warmupPick
        case .betweenSetRest: return nil
        }
    }

    private func doorRowIdentifier(for kind: EnrichmentKind) -> String {
        switch kind {
        case .sessionWarmup: return "af_enhance_row_mobility"
        case .cooldown: return "af_enhance_row_cooldown"
        case .exerciseWarmupSets: return "af_enhance_row_warmup"
        case .betweenSetRest: return "af_enhance_row_rest"
        }
    }

    /// Live mono caps summary for a door row — reflects local edit state, not
    /// the plan snapshot from when the sheet opened (design §Surface 1).
    private func liveSummary(for kind: EnrichmentKind) -> String {
        switch kind {
        case .sessionWarmup:
            return WorkoutEnrichmentPushCopy.sequenceSummary(
                mobilityActivities.map(EnrichmentActivity.init(pref:))
            )
        case .cooldown:
            return WorkoutEnrichmentPushCopy.sequenceSummary(
                cooldownActivities.map(EnrichmentActivity.init(pref:)),
                suffix: WorkoutEnrichmentPushCopy.cooldownRowSummarySuffix
            )
        case .exerciseWarmupSets:
            // Untouched door (no pick edits) still applies v1 global 8·5 —
            // don't render every candidate as SKIPPED.
            guard !perExerciseRamps.isEmpty else {
                return offer(for: .exerciseWarmupSets)?.detail ?? "NO EXERCISES"
            }
            return WorkoutEnrichmentPushCopy.warmupSetsSummaryV2(warmupExercisesForSummary)
        case .betweenSetRest:
            return offer(for: kind)?.detail ?? ""
        }
    }

    private func offer(for kind: EnrichmentKind) -> WorkoutEnrichmentPushPlanner.Offer? {
        plan.offer(kind)
    }

    private var warmupCandidateNames: [String] {
        plan.offer(.exerciseWarmupSets)?.candidateExerciseNames ?? []
    }

    /// Pairs every warm-up candidate's name with its local ramp (matched by
    /// normalized name — see `PerExerciseRamp.exerciseRef` doc). Missing ramps
    /// render as "SKIPPED" via `warmupExerciseTag`, matching the design.
    private var warmupExercisesForSummary: [(name: String, ramp: PerExerciseRamp?)] {
        warmupCandidateNames.map { name in
            let key = ExerciseKeyNormalizer.normalize(name)
            let ramp = perExerciseRamps.first { ExerciseKeyNormalizer.normalize($0.exerciseRef) == key }
            return (name: name, ramp: ramp)
        }
    }

    // MARK: - Bindings

    private var restOpenBinding: Binding<Bool> {
        Binding(
            get: { restOpen },
            set: { restOpen = $0 }
        )
    }

    private var restSecBinding: Binding<Int> {
        Binding(
            get: { restSec },
            // Defensive: Stepper keeps its own increments in-range, but clamp
            // here too so nothing else can push `restSec` out of the
            // supported grid before it reaches `decision`.
            set: { restSec = WorkoutEnrichmentPushCopy.normalizedRestSec($0) }
        )
    }

    private func checkedBinding(for kind: EnrichmentKind) -> Binding<Bool> {
        Binding(
            get: { checkedKinds.contains(kind) },
            set: { isOn in
                // Toggling off never clears `mobilityActivities` /
                // `cooldownActivities` / `perExerciseRamps` — only membership
                // in `checkedKinds` changes, so re-enabling restores exactly
                // what was there before (design §Surface 1 "retained config").
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
                    candidateExerciseIds: [],
                    candidateExerciseNames: ["Deadlift", "Overhead Press", "Leg Press"],
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
