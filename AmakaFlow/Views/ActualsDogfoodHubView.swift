//
//  ActualsDogfoodHubView.swift
//  AmakaFlow
//
//  AMA-2387 DEBUG: simulator walkthrough — teach → connect → merge → map →
//  fill-in → verified (no Clerk / live OAuth required).
//  Launch: SIMCTL_CHILD_AF_DEMO_ACTUALS_HUB=true
//  Optional: SIMCTL_CHILD_AF_DEMO_AUTORUN=fixture jumps straight into Logbook.
//

#if DEBUG
import SwiftUI

// Visual host for Actuals flow dogfood on Simulator.
// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
struct ActualsDogfoodHubView: View {
    @StateObject private var sourceStore: ActualsSourceConnectionStore
    @StateObject private var syncStore = ActualsSyncProgressStore()
    @State private var path: [ActualsDogfoodRoute] = []
    @State private var mergeMemory = ActualsMergeMemory()
    @State private var fillInVM: ActualsFillInViewModel?
    @State private var logbookVM: LogbookViewModel?
    @State private var statusLine = "Tap a step — or Run walkthrough"

    private let auth = StubActualsProviderAuth()
    private let healthKit = MockActualsHealthKitConnector(connectOutcomes: [.granted])
    private let repository: ActualsRepository
    private let draftRepository: LogDraftRepository

    init() {
        let suite = "ama2387.dogfood.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        _sourceStore = StateObject(wrappedValue: ActualsSourceConnectionStore(defaults: defaults))
        // Ephemeral in-memory DB for this session's fill-in / ghosts.
        // Never fall back to AppDatabase.shared — seeding would pollute the user DB.
        let database: AppDatabase
        do {
            database = try AppDatabase.makeTestDatabase()
        } catch {
            preconditionFailure("Dogfood test DB failed: \(error)")
        }
        repository = ActualsRepository(database: database)
        draftRepository = LogDraftRepository(database: database)
    }

    var body: some View {
        NavigationStack(path: $path) {
            menu
                .navigationDestination(for: ActualsDogfoodRoute.self) { route in
                    destination(for: route)
                }
        }
        .preferredColorScheme(.dark)
        .ddToastHost()
        .accessibilityIdentifier("af_actuals_dogfood_hub")
        .task {
            guard path.isEmpty,
                  case .actualsDogfood(let autorun)? = LaunchConfig.active?.demoHost
            else { return }
            switch autorun {
            case .live: open(.logbookLive)
            case .companion: open(.logbookCompanion)
            case .fixture: open(.logbook)
            case .walkthrough: runWalkthrough()
            case nil: break
            }
        }
    }

    private var menu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("AMA-2387 / 2426 dogfood")
                    .ddDisplayText(28, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)

                Text(statusLine)
                    .font(.system(size: 12))
                    .foregroundColor(DailyDriver.foregroundMuted)

                Button {
                    runWalkthrough()
                } label: {
                    Text("Run walkthrough ›")
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DailyDriver.lime)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_actuals_dogfood_walkthrough")

                Button {
                    open(.logbook)
                } label: {
                    Text("Mock Logbook fill-in ›")
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DailyDriver.amber)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_actuals_dogfood_logbook_cta")

                Button {
                    open(.logbookLive)
                } label: {
                    Text("Live logbook (phone tracking) ›")
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DailyDriver.lime)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_actuals_dogfood_logbook_live_cta")

                Button {
                    open(.logbookCompanion)
                } label: {
                    Text("Companion beside watch ›")
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DailyDriver.card)
                        .overlay(
                            Capsule().stroke(DailyDriver.lime.opacity(0.55), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_actuals_dogfood_logbook_companion_cta")

                Text("OR OPEN ONE STEP")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.top, 8)

                ForEach(ActualsDogfoodRoute.allCases) { route in
                    Button {
                        open(route)
                    } label: {
                        HStack {
                            Text(route.title)
                                .ddDisplayText(14, weight: .bold)
                                .foregroundColor(DailyDriver.foreground)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(DailyDriver.foregroundDim)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(DailyDriver.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(DailyDriver.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_actuals_dogfood_\(route.rawValue)")
                }
            }
            .padding(18)
            .padding(.bottom, 48)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    @ViewBuilder
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func destination(for route: ActualsDogfoodRoute) -> some View {
        switch route {
        case .teach:
            ScrollView {
                ActualsTeachCard {
                    path.append(.connect)
                }
                .padding(18)
            }
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .ddSuppressFloatingChrome()
        case .connect:
            ActualsConnectSourcesView(
                store: sourceStore,
                healthKit: healthKit,
                providerAuth: auth
            ) { provider in
                sourceStore.markConnected(provider)
                ActualsLinkFeedback.announceLinked(provider, toast: .shared)
                syncStore.beginBackfill(total: 4)
                syncStore.recordIngestedSession()
                syncStore.recordIngestedSession()
                statusLine = "\(ActualsCopy.sourceDisplayName(provider)) linked — counter at 2/4"
                if !path.contains(.mergeAsk) {
                    path.append(.mergeAsk)
                }
            }
        case .mergeAsk:
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let progress = syncStore.progress, progress.shouldShowBanner {
                        ActualsSyncCounterBanner(progress: progress)
                    }
                    ActualsMergeAskCard(
                        left: Self.sampleWatchRecording,
                        right: Self.samplePhoneRecording,
                        onMerge: {
                            statusLine = "Merged — opening detail"
                            path.append(.merged)
                        },
                        onKeepBoth: {
                            ActualsMergeClassifier.applyKeepBoth(
                                Self.sampleWatchRecording,
                                Self.samplePhoneRecording,
                                memory: &mergeMemory
                            )
                            statusLine = "Keep both sticky — re-ask suppressed"
                        }
                    )
                }
                .padding(18)
            }
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .ddSuppressFloatingChrome()
        case .merged:
            ActualsMergedDetailView(
                session: Self.sampleMergedSession,
                onSplit: { _ in
                    statusLine = "Split restored recordings"
                    path = [.mergeAsk]
                },
                onFillIn: {
                    prepareFillIn()
                    path.append(.fillIn)
                }
            )
        case .map:
            ActualsMapToPlanView(
                activity: Self.sampleUnmapped,
                matches: ActualsPlanMatcher.rank(
                    activity: Self.sampleUnmapped,
                    candidates: Self.samplePlanCandidates
                ),
                onSelect: { match in
                    statusLine = "Mapped to \(match.candidate.title)"
                    prepareFillIn()
                    path.append(.fillIn)
                },
                onKeepAsIs: {
                    statusLine = "Kept as unmapped run"
                }
            )
        case .fillIn:
            if let fillInVM {
                // Mode select → Quick or Set by set (AMA-2426).
                ActualsFillInFlowView(
                    viewModel: fillInVM,
                    onSaved: { _ in
                        statusLine = "Saved verified — ghosts ready"
                    },
                    presentsVerifiedOnSave: true
                )
            } else {
                Color.clear.onAppear {
                    prepareFillIn()
                }
            }
        case .logbook, .logbookLive, .logbookCompanion:
            if let logbookVM {
                LogbookView(
                    viewModel: logbookVM,
                    onBack: { path.removeAll() },
                    onSaved: { _ in
                        statusLine = "Logbook saved verified — ghosts ready"
                        path = [.verified]
                    }
                )
            } else {
                Color.clear.onAppear {
                    prepareLogbook(mode: mode(for: route))
                }
            }
        case .verified:
            ActualsVerifiedView(session: Self.verifiedSampleSession(), sourceName: "Strava")
        case .editorGhosts:
            editorGhostDemo
        }
    }

    private var editorGhostDemo: some View {
        let seed = DDEditorSeed.initialState(
            mode: .backfill,
            workout: nil,
            ghostLookup: repository
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Editor ghosts")
                    .ddDisplayText(22, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                Text("After a verified save, backfill seed pulls last actuals.")
                    .font(.system(size: 12))
                    .foregroundColor(DailyDriver.foregroundMuted)
                ForEach(seed.blocks.flatMap(\.exercises)) { exercise in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .ddDisplayText(14, weight: .bold)
                                .foregroundColor(DailyDriver.foreground)
                            Text(exercise.summaryLine)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(
                                    exercise.showsLastTime
                                        ? DailyDriver.foregroundDim
                                        : DailyDriver.foregroundMuted
                                )
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(DailyDriver.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(18)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .ddSuppressFloatingChrome()
    }

    private func runWalkthrough() {
        sourceStore.markDisconnected(.appleHealth)
        sourceStore.markDisconnected(.strava)
        sourceStore.markDisconnected(.garmin)
        syncStore.clear()
        statusLine = "Walkthrough: teach → connect → …"
        path = [.teach]
    }

    private func open(_ route: ActualsDogfoodRoute) {
        if route == .fillIn || route == .editorGhosts {
            prepareFillIn()
            if route == .editorGhosts {
                do {
                    try seedVerifiedForGhosts()
                } catch {
                    statusLine = "Ghost seed failed: \(error.localizedDescription)"
                    return
                }
            }
        }
        if route == .logbook || route == .logbookLive || route == .logbookCompanion {
            prepareLogbook(mode: mode(for: route))
        }
        path.append(route)
    }

    private func mode(for route: ActualsDogfoodRoute) -> LogbookMode {
        switch route {
        case .logbookLive: return .live
        case .logbookCompanion: return .companionPending
        default: return .after
        }
    }

    private func prepareFillIn() {
        var session = ActualsFillInSession.lowerBodyPosteriorSample(
            id: "dogfood_\(UUID().uuidString.prefix(8))"
        )
        // Pre-mark squat adjusted to 90 so verified deltas look like the rig.
        session.exercises[0].confirmation = .adjusted
        session.exercises[0].actualWeightKg = 90
        fillInVM = ActualsFillInViewModel(session: session, repository: repository)
    }

    private func prepareLogbook(mode: LogbookMode = .after) {
        // Prior verified session → LAST TIME differs from plan so Same as last time is obvious.
        try? seedLogbookGhostHistory()
        let session = ActualsFillInSession.lowerBodyPosteriorSample(
            id: "dogfood_log_\(UUID().uuidString.prefix(8))"
        )
        let draft = LogbookSeeding.draft(
            from: session,
            mode: mode,
            ghostLookup: repository
        )
        logbookVM = LogbookViewModel(
            draft: draft,
            draftRepository: draftRepository,
            actualsRepository: repository,
            weightUnit: .kg
        )
        switch mode {
        case .live:
            statusLine = "LIVE — elapsed header ticks; Log sets feel while phone tracks"
        case .companionPending:
            statusLine = "COMPANION — pending banner; notepad beside watch (no live Workout channel)"
        case .after:
            statusLine = "Logbook — tap cells for wheels, ✓ sets, then Save log"
        }
    }

    /// Distinct last-time loads (not the prescription) for dogfood Same as last time.
    private func seedLogbookGhostHistory() throws {
        var prior = ActualsFillInSession.lowerBodyPosteriorSample(id: "dogfood_logbook_ghosts")
        prior.exercises[0].confirmation = .adjusted
        prior.exercises[0].actualWeightKg = 100
        prior.exercises[0].actualReps = 6
        prior.exercises[1].confirmation = .adjusted
        prior.exercises[1].actualWeightKg = 72.5
        prior.exercises[1].actualReps = 8
        prior.exercises[2].confirmation = .adjusted
        prior.exercises[2].actualWeightKg = 20
        prior.exercises[2].actualReps = 10
        prior.exercises[3].confirmation = .adjusted
        prior.exercises[3].actualWeightKg = nil
        prior.exercises[3].actualReps = 6
        prior.rpe = 7
        prior.verified = true
        try repository.saveVerifiedSession(prior)
    }

    private func seedVerifiedForGhosts() throws {
        var session = ActualsFillInSession.lowerBodyPosteriorSample(id: "dogfood_ghost_seed")
        session.exercises[0].confirmation = .adjusted
        session.exercises[0].actualWeightKg = 90
        for index in 1..<session.exercises.count {
            session.exercises[index].confirmation = .asPlanned
        }
        session.rpe = 8
        session.verified = true
        try repository.saveVerifiedSession(session)
        statusLine = "Seeded verified back squat 90 kg for ghosts"
    }

    // MARK: - Sample data

    private static var sampleWatchRecording: ActualsSourceRecording {
        ActualsSourceRecording(
            id: "dogfood_aw",
            provider: .appleHealth,
            deviceKind: .watch,
            title: "Hyrox Sim",
            startDate: Date().addingTimeInterval(-3600),
            durationSeconds: 44 * 60,
            distanceMeters: 5_200,
            streamRichness: 5
        )
    }

    private static var samplePhoneRecording: ActualsSourceRecording {
        ActualsSourceRecording(
            id: "dogfood_strava",
            provider: .strava,
            deviceKind: .phone,
            title: "Hyrox Sim",
            startDate: Date().addingTimeInterval(-3600 + 45),
            durationSeconds: 44 * 60,
            distanceMeters: 5_180,
            streamRichness: 2
        )
    }

    private static var sampleMergedSession: ActualsSession {
        ActualsMergeClassifier.merge([
            sampleWatchRecording,
            ActualsSourceRecording(
                id: "dogfood_garmin",
                provider: .garmin,
                deviceKind: .watch,
                title: "Hyrox",
                startDate: Date().addingTimeInterval(-3600),
                durationSeconds: 44 * 60,
                streamRichness: 4
            ),
            samplePhoneRecording
        ])
    }

    private static var sampleUnmapped: ActualsUnmappedActivity {
        ActualsUnmappedActivity(
            title: "Afternoon Run",
            provider: .strava,
            startDate: Date().addingTimeInterval(-7200),
            durationSeconds: 32 * 60,
            distanceMeters: 6_400,
            calories: 520,
            avgHR: 148,
            type: .run
        )
    }

    private static var samplePlanCandidates: [ActualsPlanCandidate] {
        let start = Date().addingTimeInterval(-7200)
        return [
            ActualsPlanCandidate(
                id: "c1",
                title: "Zone 2 endurance",
                sourceLabel: "MY WORKOUTS · TODAY",
                scheduledStart: start,
                durationSeconds: 35 * 60,
                distanceMeters: 6_500,
                type: .run,
                targetAvgHR: 145
            ),
            ActualsPlanCandidate(
                id: "c2",
                title: "Tempo intervals",
                sourceLabel: "STRYD · EARLIER",
                scheduledStart: start.addingTimeInterval(-800),
                durationSeconds: 40 * 60,
                distanceMeters: 8_000,
                type: .run,
                targetAvgHR: 165
            )
        ]
    }

    private static func verifiedSampleSession() -> ActualsFillInSession {
        let checkedAt = Date()
        var session = ActualsFillInSession.lowerBodyPosteriorSample()
        // Per-set logbook payload — WHAT YOU DID lists each weight×reps, not one rollup.
        session.exercises[0].confirmation = .adjusted
        session.exercises[0].actualWeightKg = 90
        session.exercises[0].sets = [
            SetActual(index: 1, weightKg: 100, reps: 6, checkedAt: checkedAt),
            SetActual(index: 2, weightKg: 127.5, reps: 5, checkedAt: checkedAt),
            SetActual(index: 3, weightKg: 90, reps: 5, checkedAt: checkedAt)
        ]
        session.exercises[1].confirmation = .asPlanned
        session.exercises[1].sets = [
            SetActual(index: 1, weightKg: 70, reps: 8, checkedAt: checkedAt),
            SetActual(index: 2, weightKg: 70, reps: 8, checkedAt: checkedAt),
            SetActual(index: 3, weightKg: 70, reps: 8, checkedAt: checkedAt)
        ]
        session.exercises[2].confirmation = .asPlanned
        session.exercises[2].sets = [
            SetActual(index: 1, weightKg: 20, reps: 10, checkedAt: checkedAt),
            SetActual(index: 2, weightKg: 20, reps: 10, checkedAt: checkedAt)
        ]
        session.exercises[3].confirmation = .asPlanned
        session.exercises[3].sets = [
            SetActual(index: 1, reps: 6, checkedAt: checkedAt),
            SetActual(index: 2, reps: 6, checkedAt: checkedAt)
        ]
        session.rpe = 8
        session.verified = true
        return session
    }
}

enum ActualsDogfoodRoute: String, CaseIterable, Identifiable, Hashable {
    case teach
    case connect
    case mergeAsk
    case merged
    case map
    case fillIn
    case logbook
    case logbookLive
    case logbookCompanion
    case verified
    case editorGhosts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teach: return "1 · Teach card"
        case .connect: return "2 · Connect sources"
        case .mergeAsk: return "3 · Merge ask"
        case .merged: return "4 · Merged detail"
        case .map: return "5 · Map to plan"
        case .fillIn: return "6 · Fill-in (mode select → Quick / Logbook)"
        case .logbook: return "6b · Logbook grid + wheels (after)"
        case .logbookLive: return "6c · Live logbook (phone tracking)"
        case .logbookCompanion: return "6d · Companion beside watch"
        case .verified: return "7 · Verified payoff"
        case .editorGhosts: return "8 · Editor ghosts"
        }
    }
}
#endif
