//
//  CreateFlowPresentation.swift
//  AmakaFlow
//
//  Routes CreateWorkoutSheet doors to import / add flows.
//

import SwiftUI

enum CreateFlowPresentation: Identifiable, Equatable {
    case createWithAI
    case socialImport(url: String?, platform: SocialImportPlatform?)
    case screenshot
    case knowledge
    case manualEditor
    /// AMA-2426: logbook from ＋ Add sheet.
    case logSession

    var id: String {
        switch self {
        case .createWithAI:
            return "create-with-ai"
        case .socialImport(let url, let platform):
            return "social-\(platform?.rawValue ?? "any")-\(url ?? "")"
        case .screenshot:
            return "screenshot"
        case .knowledge:
            return "knowledge"
        case .manualEditor:
            return "manual-editor"
        case .logSession:
            return "log-session"
        }
    }
}

extension Notification.Name {
    static let libraryContentDidChange = Notification.Name("libraryContentDidChange")
    /// AMA-2389: open an existing library workout after “Open yours” from a friend share.
    static let libraryOpenWorkout = Notification.Name("libraryOpenWorkout")
    /// WorkoutKit schedule mutated (delete / clear / move / send) — refresh On your watches counts.
    static let appleWatchScheduleDidChange = Notification.Name("appleWatchScheduleDidChange")
}

enum OpenCreateSheetKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openCreateSheet: () -> Void {
        get { self[OpenCreateSheetKey.self] }
        set { self[OpenCreateSheetKey.self] = newValue }
    }
}

struct CreateFlowSheetsModifier: ViewModifier {
    @Binding var showCreateSheet: Bool
    @Binding var activeFlow: CreateFlowPresentation?
    var onLibraryReload: () -> Void

    @State private var speakUnavailableAlert = false
    /// AMA-2389: From friends inbox (sheet, not a new top-level surface).
    @State private var showFriendsInbox = false
    @ObservedObject private var friendsStore = FriendsSharingStore.shared
    /// AMA-2426: library workouts for Log a session picker.
    @State private var logbookWorkouts: [Workout] = []
    @State private var showLogbookPicker = false
    @State private var logbookViewModel: LogbookViewModel?

    func body(content: Content) -> some View {
        content
            .ddBottomSheet(isPresented: $showCreateSheet, detents: createSheetDetents) {
                CreateWorkoutSheet(onSelect: openDoor)
            }
            .alert("Voice import not available yet", isPresented: $speakUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Use Import from URL or Build from scratch for now.")
            }
            .sheet(isPresented: $showFriendsInbox) {
                NavigationStack {
                    FriendsInboxView(store: friendsStore)
                }
                .presentationDetents(friendsSheetDetents)
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showLogbookPicker) {
                LogbookWorkoutPickerView(
                    workouts: logbookWorkouts,
                    onPick: { workout in
                        showLogbookPicker = false
                        openLogbook(from: workout)
                    },
                    onClose: { showLogbookPicker = false }
                )
            }
            .fullScreenCover(item: $activeFlow) { flow in
                switch flow {
                case .createWithAI:
                    CreateWithAIPromptView(onSaved: onLibraryReload)
                case .socialImport(let url, let platform):
                    SocialImportFlowView(
                        mode: .url(platformHint: platform),
                        initialURL: url,
                        onSaved: onLibraryReload
                    )
                case .screenshot:
                    ImageImportView(onSaved: onLibraryReload)
                case .knowledge:
                    AddKnowledgeView(
                        onSocialURLDetected: { detected in
                            activeFlow = .socialImport(
                                url: SocialImportPlatform.normalizeForIngest(detected),
                                platform: SocialImportPlatform.detect(from: detected)
                            )
                        },
                        onSaved: onLibraryReload
                    )
                case .manualEditor:
                    BuilderV3EntryView(onSaved: onLibraryReload)
                        .ddSuppressFloatingChrome()
                case .logSession:
                    if let logbookViewModel {
                        LogbookView(
                            viewModel: logbookViewModel,
                            onBack: { activeFlow = nil },
                            onSaved: { _ in
                                activeFlow = nil
                                onLibraryReload()
                            }
                        )
                    } else {
                        ProgressView()
                            .task { openLogbook(from: nil) }
                    }
                }
            }
    }

    private var createSheetDetents: Set<PresentationDetent> {
        // AMA-2389: sheet a11y — large under UITEST (iOS 26.1 medium gap).
        #if DEBUG
        if UITestEnvironment.isTruthy("UITEST_USE_FIXTURES")
            || UITestEnvironment.isTruthy("UITEST_SKIP_ONBOARDING") {
            return [.large, .medium]
        }
        #endif
        return [.medium]
    }

    private func openDoor(_ door: CreateWorkoutDoor) {
        switch door {
        case .createWithAI:
            activeFlow = .createWithAI
        case .importURL:
            activeFlow = .socialImport(url: nil, platform: nil)
        case .screenshot:
            activeFlow = .screenshot
        case .manual:
            activeFlow = .manualEditor
        case .speak:
            speakUnavailableAlert = true
        case .fromFriends:
            showFriendsInbox = true
        case .logSession:
            Task { await presentLogSessionPicker() }
        }
    }

    @MainActor
    private func presentLogSessionPicker() async {
        do {
            logbookWorkouts = try await APIService.shared.fetchWorkouts()
        } catch {
            logbookWorkouts = []
        }
        showLogbookPicker = true
    }

    private func openLogbook(from workout: Workout?) {
        let context = LogbookModeContext(
            phoneTrackerActive: false,
            watchPlanActiveWindow: WatchConnectivityManager.shared.isWatchReachable,
            existingSessionId: nil
        )
        let mode = LogbookModeInference.infer(context)
        let draft: LogDraft
        if let workout {
            draft = LogbookSeeding.draft(
                from: workout,
                mode: mode,
                ghostLookup: ActualsRepository(),
                loadPlanLookup: { key in
                    try? LogDraftRepository().loadPlan(workoutId: workout.id, exerciseKey: key)
                }
            )
        } else {
            draft = LogbookSeeding.blankDraft(mode: mode)
        }
        let unit: WeightUnit = {
            if let raw = UserDefaults.standard.string(forKey: DefaultsKey.userWeightUnit.rawValue),
               let parsed = WeightUnit(rawValue: raw) {
                return parsed
            }
            return .kg
        }()
        logbookViewModel = LogbookViewModel(
            draft: draft,
            draftRepository: LogDraftRepository(),
            actualsRepository: ActualsRepository(),
            weightUnit: unit
        )
        activeFlow = .logSession
    }
}

extension View {
    func createFlowSheets(
        showCreateSheet: Binding<Bool>,
        activeFlow: Binding<CreateFlowPresentation?>,
        onLibraryReload: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            CreateFlowSheetsModifier(
                showCreateSheet: showCreateSheet,
                activeFlow: activeFlow,
                onLibraryReload: onLibraryReload
            )
        )
    }
}
