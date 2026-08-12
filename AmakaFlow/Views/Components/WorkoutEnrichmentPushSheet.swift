// AMA-2336/2362/2371/2378/2408 — watch-ready enrichment offers before push.
// AMA-2385 — pin Confirm/Skip outside ScrollView so Rest expand keeps CTA visible.
// AMA-2408 — sheet is a dumb renderer of EnrichmentState + action dispatcher.

import SwiftUI

struct WorkoutEnrichmentPushSheet: View {
    let plan: WorkoutEnrichmentPushPlanner.Plan
    let prefs: WorkoutPreferences
    let workoutId: String
    let onConfirm: (WorkoutEnrichmentPushPlanner.Decision) -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    @State private var state: EnrichmentState
    @State private var route: Route?
    @State private var didRunLegacyMigration = false
    private let prefsStore: any EnrichmentPrefsStoring
    private let readinessStore: any WatchItemReadinessStoring

    private var target: EnrichmentPushTarget { plan.target }

    private enum Route: Hashable {
        case sequence(EnrichmentSequenceKind)
        case warmupPick
    }

    init(
        plan: WorkoutEnrichmentPushPlanner.Plan,
        prefs: WorkoutPreferences,
        workoutId: String = "",
        prefsStore: any EnrichmentPrefsStoring = EnrichmentPrefsStore.shared,
        readinessStore: any WatchItemReadinessStoring = WatchItemReadinessStore.shared,
        onConfirm: @escaping (WorkoutEnrichmentPushPlanner.Decision) -> Void,
        onSkip: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.plan = plan
        self.prefs = prefs
        self.workoutId = workoutId
        self.prefsStore = prefsStore
        self.readinessStore = readinessStore
        self.onConfirm = onConfirm
        self.onSkip = onSkip
        self.onClose = onClose
        // Side-effect free: seed from load only. Legacy migration persists in onAppear.
        _state = State(initialValue: Self.seededState(
            plan: plan,
            prefs: prefs,
            workoutId: workoutId,
            prefsStore: prefsStore,
            persistMigration: false
        ))
    }

    /// Pure seed helper. When `persistMigration` is true, materializes + saves
    /// legacy bridge drafts once (called from onAppear, not init).
    private static func seededState(
        plan: WorkoutEnrichmentPushPlanner.Plan,
        prefs: WorkoutPreferences,
        workoutId: String,
        prefsStore: any EnrichmentPrefsStoring,
        persistMigration: Bool
    ) -> EnrichmentState {
        let candidates = plan.offer(.exerciseWarmupSets)?.candidateExerciseNames ?? []
        let dedicated = prefsStore.loadDedicated(workoutID: workoutId)
        var saved = dedicated ?? prefsStore.load(workoutID: workoutId)
        if persistMigration,
           dedicated == nil,
           let existing = saved,
           existing.checkedKindSet.contains(.exerciseWarmupSets),
           existing.perExerciseRamps.isEmpty,
           !candidates.isEmpty {
            let migrated = LegacyOptInRampMigration.materializePersisted(
                existing,
                candidateNames: candidates,
                defaultSets: prefs.exerciseWarmupSets.defaultSets
            )
            prefsStore.save(workoutID: workoutId, prefs: migrated)
            LegacyOptInRampMigration.markMigrated(workoutID: workoutId)
            saved = migrated
        }
        return EnrichmentState.seed(
            workoutPrefs: saved,
            globalDefaults: prefs,
            plan: plan
        )
    }

    var body: some View {
        NavigationStack {
            sheetBody
                .navigationDestination(item: $route) { route in
                    switch route {
                    case .sequence(let kind):
                        EnrichmentSequenceScreen(
                            activities: sequenceBinding(kind),
                            kind: kind
                        )
                    case .warmupPick:
                        EnrichmentWarmupPickScreen(
                            ramps: rampsBinding,
                            exercises: state.candidateExerciseNames,
                            workingSetCounts: plan.offer(.exerciseWarmupSets)?.candidateWorkingSetCounts ?? []
                        )
                        .onDisappear { persistConfiguratorSave() }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !didRunLegacyMigration else { return }
            didRunLegacyMigration = true
            state = Self.seededState(
                plan: plan,
                prefs: prefs,
                workoutId: workoutId,
                prefsStore: prefsStore,
                persistMigration: true
            )
        }
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

            // AMA-2385: pin CTAs below scroll so Rest expand can't bury them.
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
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }

            VStack(spacing: 10) {
                Button {
                    dispatch(.confirm)
                    persistConfiguratorSave()
                    onConfirm(state.decision)
                } label: {
                    Text(WorkoutEnrichmentPushCopy.primaryCTA(checkedCount: state.checkedKinds.count))
                }
                .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                .accessibilityIdentifier("af_enrichment_push_confirm")

                Button {
                    dispatch(.skip)
                    onSkip()
                } label: {
                    Text(WorkoutEnrichmentPushCopy.sendAsIsCTA)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_enrichment_push_skip")
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(DailyDriver.screenBackground)
        .navigationBarHidden(true)
        .accessibilityIdentifier("af_enrichment_push_sheet")
    }

    private func dispatch(_ action: EnrichmentAction) {
        state = EnrichmentReducer.reduce(state, action)
    }

    /// Persist full decision on confirm AND configurator save (F3).
    private func persistConfiguratorSave() {
        guard !workoutId.isEmpty else { return }
        let persisted = state.persisted()
        prefsStore.save(workoutID: workoutId, prefs: persisted)
        // Keep Watch Item draft in lockstep (one store, every door).
        readinessStore.saveDraft(
            workoutID: workoutId,
            snapshot: WatchItemReadinessSnapshot(
                readiness: persisted.asReadiness(),
                config: persisted.asConfig(),
                snapshotPills: readinessStore.loadDraft(workoutID: workoutId)?.snapshotPills ?? [],
                updatedAt: Date()
            )
        )
    }

    @ViewBuilder
    private func offerRow(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> some View {
        if offer.kind == .betweenSetRest {
            restRow(offer)
        } else if offer.kind == .stationTransition {
            transitionRow(offer)
        } else {
            doorRow(offer)
        }
    }

    // MARK: - v1 inline rest row

    private func restRow(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> some View {
        EnrichmentRecoveryRow(
            title: offer.title,
            detail: liveSummary(for: offer.kind) ?? optionalOfferDetail(offer),
            showsTombstoneHint: offer.wasTombstoned && !offer.isChecked,
            rowIdentifier: doorRowIdentifier(for: offer.kind),
            toggleIdentifier: "af_enrichment_push_offer_\(offer.kind.rawValue)",
            isChecked: checkedBinding(for: offer.kind)
        ) {
            restOverride
        }
    }

    private var restOverride: some View {
        EnrichmentRecoveryOverride(
            openLabel: WorkoutEnrichmentPushCopy.restOpenSegmentLabel(target: target),
            timedLabel: WorkoutEnrichmentPushCopy.restTimedSegmentLabel,
            secondsRange: WorkoutEnrichmentPushCopy.restSecRange,
            openIdentifier: "af_enrichment_push_rest_open",
            secondsIdentifier: "af_enrichment_push_rest_sec",
            isOpen: restOpenBinding,
            seconds: restSecBinding
        )
    }

    private func optionalOfferDetail(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> String? {
        offer.kind == .betweenSetRest || offer.kind == .stationTransition ? offer.detail : nil
    }

    // MARK: - AMA-2423 v1 inline transitions row (mirrors restRow)

    private func transitionRow(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> some View {
        EnrichmentRecoveryRow(
            title: offer.title,
            detail: liveSummary(for: offer.kind) ?? optionalOfferDetail(offer),
            showsTombstoneHint: offer.wasTombstoned && !offer.isChecked,
            rowIdentifier: doorRowIdentifier(for: offer.kind),
            toggleIdentifier: "af_enrichment_push_offer_\(offer.kind.rawValue)",
            isChecked: checkedBinding(for: offer.kind)
        ) {
            transitionOverride
        }
    }

    private var transitionOverride: some View {
        EnrichmentRecoveryOverride(
            openLabel: WorkoutEnrichmentPushCopy.transitionOpenSegmentLabel(target: target),
            timedLabel: WorkoutEnrichmentPushCopy.transitionTimedSegmentLabel,
            secondsRange: WorkoutEnrichmentPushCopy.transitionSecRange,
            openIdentifier: "af_enrichment_push_transition_open",
            secondsIdentifier: "af_enrichment_push_transition_sec",
            isOpen: transitionOpenBinding,
            seconds: transitionSecBinding
        )
    }

    // MARK: - v2 door rows

    private func doorRow(_ offer: WorkoutEnrichmentPushPlanner.Offer) -> some View {
        let isChecked = state.checkedKinds.contains(offer.kind)
        let summary = liveSummary(for: offer.kind)
        let isAmberWarmupCTA = offer.kind == .exerciseWarmupSets && state.needsWarmupPick
        return HStack(spacing: 12) {
            Button {
                route = doorRoute(for: offer.kind)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(offer.title)
                            .ddDisplayText(14, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                        // Always reserve one summary line so OFF rows keep constant height.
                        Text(summary ?? " ")
                            .font(Theme.Typography.mono)
                            .foregroundColor(isAmberWarmupCTA ? DailyDriver.amber : DailyDriver.foregroundMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .accessibilityHidden(summary == nil)
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
        // Transitions is a v1 inline row (transitionRow), not a v2 door.
        case .stationTransition: return nil
        }
    }

    private func doorRowIdentifier(for kind: EnrichmentKind) -> String {
        switch kind {
        case .sessionWarmup: return "af_enhance_row_mobility"
        case .cooldown: return "af_enhance_row_cooldown"
        case .exerciseWarmupSets: return "af_enhance_row_warmup"
        case .betweenSetRest: return "af_enhance_row_rest"
        case .stationTransition: return "af_enhance_row_transition"
        }
    }

    /// AMA-2408 — single summary home. OFF → nil (title + toggle only).
    private func liveSummary(for kind: EnrichmentKind) -> String? {
        state.summary(for: kind)
    }

    // MARK: - Bindings

    private var restOpenBinding: Binding<Bool> {
        Binding(
            get: { state.restOpen },
            set: { dispatch(.setRest(open: $0, sec: state.restSec)) }
        )
    }

    private var restSecBinding: Binding<Int> {
        Binding(
            get: { state.restSec },
            set: {
                dispatch(.setRest(
                    open: state.restOpen,
                    sec: WorkoutEnrichmentPushCopy.normalizedRestSec($0)
                ))
            }
        )
    }

    private var transitionOpenBinding: Binding<Bool> {
        Binding(
            get: { state.transitionOpen },
            set: { dispatch(.setStationTransition(open: $0, sec: state.transitionSec)) }
        )
    }

    private var transitionSecBinding: Binding<Int> {
        Binding(
            get: { state.transitionSec },
            set: {
                dispatch(.setStationTransition(
                    open: state.transitionOpen,
                    sec: WorkoutEnrichmentPushCopy.normalizedTransitionSec($0)
                ))
            }
        )
    }

    private var rampsBinding: Binding<[PerExerciseRamp]> {
        Binding(
            get: { state.perExerciseRamps },
            set: {
                dispatch(.replaceRamps($0))
                persistConfiguratorSave()
            }
        )
    }

    private func sequenceBinding(_ kind: EnrichmentSequenceKind) -> Binding<[EnrichmentActivityPref]> {
        Binding(
            get: {
                switch kind {
                case .mobility: return state.mobilityActivities
                case .cooldown: return state.cooldownActivities
                }
            },
            set: {
                dispatch(.setSequence(kind, $0))
                persistConfiguratorSave()
            }
        )
    }

    private func checkedBinding(for kind: EnrichmentKind) -> Binding<Bool> {
        Binding(
            get: { state.checkedKinds.contains(kind) },
            set: { isOn in
                let currentlyOn = state.checkedKinds.contains(kind)
                if isOn != currentlyOn {
                    dispatch(.toggleRow(kind))
                }
                persistConfiguratorSave()
                // F2: first toggle of Warm-up ROW ON with empty picks → open pick screen.
                if isOn, kind == .exerciseWarmupSets, state.needsWarmupPick {
                    route = .warmupPick
                }
            }
        )
    }
}
