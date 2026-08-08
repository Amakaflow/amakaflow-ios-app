//
//  ActualsDogfoodHubView.swift
//  AmakaFlow
//
//  AMA-2387 DEBUG: simulator walkthrough — teach → connect → merge → map →
//  fill-in → verified (no Clerk / live OAuth required).
//  Launch: SIMCTL_CHILD_AMA2387_DEMO=true
//

#if DEBUG
import SwiftUI

/// Visual host for Actuals flow dogfood on Simulator.
struct ActualsDogfoodHubView: View {
    @StateObject private var sourceStore: ActualsSourceConnectionStore
    @StateObject private var syncStore = ActualsSyncProgressStore()
    @State private var path: [ActualsDogfoodRoute] = []
    @State private var mergeMemory = ActualsMergeMemory()
    @State private var fillInVM: ActualsFillInViewModel?
    @State private var statusLine = "Tap a step — or Run walkthrough"

    private let auth = StubActualsProviderAuth()
    private let healthKit = MockActualsHealthKitConnector(connectOutcomes: [.granted])
    private let repository: ActualsRepository

    init() {
        let suite = "ama2387.dogfood.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        _sourceStore = StateObject(wrappedValue: ActualsSourceConnectionStore(defaults: defaults))
        // Ephemeral in-memory DB for this session's fill-in / ghosts.
        let db = (try? AppDatabase.makeTestDatabase()) ?? AppDatabase.shared
        repository = ActualsRepository(database: db)
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
            // Optional: SIMCTL_CHILD_AMA2387_AUTORUN=true jumps straight into teach.
            if UITestEnvironment.isTruthy("AMA2387_AUTORUN"), path.isEmpty {
                runWalkthrough()
            }
        }
    }

    private var menu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("AMA-2387 dogfood")
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
                ActualsFillInView(
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
        case .verified:
            ActualsVerifiedView(session: Self.verifiedSampleSession(), sourceName: "Strava")
        case .editorGhosts:
            editorGhostDemo
        }
    }

    private var editorGhostDemo: some View {
        let previous = DDEditorSeed.ghostLookup
        let _ = { DDEditorSeed.ghostLookup = repository }()
        let seed = DDEditorSeed.initialState(mode: .backfill, workout: nil)
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
            .onDisappear { DDEditorSeed.ghostLookup = previous }
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
                Task { try? seedVerifiedForGhosts() }
            }
        }
        path.append(route)
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
            samplePhoneRecording,
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
            ),
        ]
    }

    private static func verifiedSampleSession() -> ActualsFillInSession {
        var session = ActualsFillInSession.lowerBodyPosteriorSample()
        session.exercises[0].confirmation = .adjusted
        session.exercises[0].actualWeightKg = 90
        for index in 1..<session.exercises.count {
            session.exercises[index].confirmation = .asPlanned
        }
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
        case .fillIn: return "6 · Fill-in actuals"
        case .verified: return "7 · Verified payoff"
        case .editorGhosts: return "8 · Editor ghosts"
        }
    }
}
#endif
