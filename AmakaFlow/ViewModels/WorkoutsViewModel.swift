//
//  WorkoutsViewModel.swift
//  AmakaFlow
//
//  Manages workout state and business logic
//

import Foundation
import Combine

// MARK: - Notification Names (AMA-237)

extension Notification.Name {
    static let workoutCompleted = Notification.Name("workoutCompleted")
}

// MARK: - Training Block (AMA-1641)

/// Represents the user's current training block (a multi-week mesocycle
/// segment, e.g. "Block 2 of 4"). Populated by the planner API when block
/// metadata is returned alongside scheduled workouts.
struct TrainingBlock: Equatable {
    /// Display name for the block, e.g. "Build" or "Deload".
    let name: String
    /// 1-based block index within the mesocycle (e.g. 2 of 4).
    let index: Int
    /// Total blocks in the mesocycle.
    let total: Int
    /// Workouts scoped to this block.
    let scheduledWorkouts: [ScheduledWorkout]
}

@MainActor
class WorkoutsViewModel: ObservableObject {
    @Published var upcomingWorkouts: [ScheduledWorkout] = []
    @Published var incomingWorkouts: [Workout] = []
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var useDemoMode: Bool = false
    @Published var pendingWorkoutsStatus: String = ""  // Debug status for pending workouts

    // AMA-1640: deep-link payload state. Views observe these and clear
    // them after consuming so the next deep-link fires a fresh trigger.
    @Published var pendingCalendarDate: Date?
    @Published var pendingDeepLinkWorkoutId: String?

    // AMA-1641: current training block scoping for the Workouts pivot.
    // Populated when the planner API returns block info; nil otherwise so
    // the Block view falls back to "all upcoming" without faking a count.
    @Published var activeBlock: TrainingBlock?

    private let dependencies: AppDependencies
    private let calendarManager = CalendarManager()
    private var cancellables = Set<AnyCancellable>()

    /// Repository handles for the local-first read path (AMA-1792). Reads
    /// hydrate `incomingWorkouts` from `workout_events` (status='planned',
    /// source='suggestion_accepted'); writes go through the repos which
    /// auto-enqueue to `sync_queue` for the SyncEngine to flush.
    private var acceptedRepo: AcceptedSuggestionsRepository {
        dependencies.acceptedSuggestionsRepository
    }
    private var eventsRepo: WorkoutEventsRepository {
        dependencies.workoutEventsRepository
    }
    private var currentUserId: String? {
        dependencies.pairingService.userProfile?.id
    }

    /// Initialize with dependencies for dependency injection
    /// - Parameter dependencies: App dependencies container (defaults to .live for production)
    init(
        dependencies: AppDependencies = .live
    ) {
        self.dependencies = dependencies

        // AMA-1792: hydrate Home from the local DB before the network
        // round-trip. The SyncEngine reconciles in the background.
        UserDefaultsAcceptedMigration.runIfNeeded(
            userId: dependencies.pairingService.userProfile?.id,
            acceptedRepo: dependencies.acceptedSuggestionsRepository,
            eventsRepo: dependencies.workoutEventsRepository
        )
        self.incomingWorkouts = Self.hydrateIncoming(
            userId: dependencies.pairingService.userProfile?.id,
            eventsRepo: dependencies.workoutEventsRepository
        )

        // Observe workout completion notifications (AMA-237)
        NotificationCenter.default.publisher(for: .workoutCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                print("[WorkoutsViewModel] Received workoutCompleted notification")
                if let workoutId = notification.userInfo?["workoutId"] as? String {
                    print("[WorkoutsViewModel] Marking workout \(workoutId) as completed")
                    self?.markWorkoutCompleted(workoutId)
                } else {
                    print("[WorkoutsViewModel] ERROR: No workoutId in notification")
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Loading

    /// AMA-1792: Home reads from the local DB. The network refresh runs
    /// alongside but no longer gates UI — a failed fetch leaves the
    /// already-rendered list untouched.
    func loadWorkouts() async {
        isLoading = true
        errorMessage = nil

        if useDemoMode {
            print("[WorkoutsViewModel] Demo mode enabled, loading mock data")
            loadMockData()
            isLoading = false
            return
        }

        // Local-first hydrate. Always reflect what the repo has, even if
        // the user isn't yet authenticated — the migration step seeded
        // these rows from UserDefaults if any existed.
        let localIncoming = Self.hydrateIncoming(userId: currentUserId, eventsRepo: eventsRepo)
        incomingWorkouts = localIncoming

        if !dependencies.pairingService.isPaired {
            print("[WorkoutsViewModel] Not authenticated yet; serving \(localIncoming.count) row(s) from local repo")
            upcomingWorkouts = []
            isLoading = false
            return
        }

        print("[WorkoutsViewModel] Refreshing from API on top of \(localIncoming.count) local row(s)...")

        do {
            async let fetchedWorkouts = dependencies.apiService.fetchWorkouts()
            async let fetchedScheduled = dependencies.apiService.fetchScheduledWorkouts()

            let (workouts, scheduled) = try await (fetchedWorkouts, fetchedScheduled)

            print("[WorkoutsViewModel] Fetched \(workouts.count) workouts, \(scheduled.count) scheduled")
            DebugLogService.shared.log(
                "Workouts refreshed",
                details: "fetched=\(workouts.count) scheduled=\(scheduled.count) localCount=\(localIncoming.count)",
                metadata: ["source": "WorkoutsViewModel.loadWorkouts"]
            )
            // Server merge: surface any server-side workouts the local repo
            // doesn't know about yet (e.g. a workout pushed to this device
            // from another client). Local rows always win on id collision —
            // the SyncEngine reconciles authoritative state separately.
            let localIDs = Set(localIncoming.map(\.id))
            let serverExtras = workouts.filter { !localIDs.contains($0.id) }
            incomingWorkouts = localIncoming + serverExtras
            upcomingWorkouts = scheduled
        } catch let error as APIError {
            print("[WorkoutsViewModel] API error: \(error.localizedDescription)")
            if case .unauthorized = error {
                errorMessage = "Session expired. Please reconnect."
            } else {
                errorMessage = error.localizedDescription
                // Local repo already populated incomingWorkouts above; leave
                // it untouched on refresh failure.
                DebugLogService.shared.log(
                    "Workouts refresh failed; serving local repo only",
                    details: "error=\(error.localizedDescription), localCount=\(incomingWorkouts.count)",
                    metadata: ["source": "WorkoutsViewModel.loadWorkouts.catch.APIError"]
                )
            }
        } catch {
            print("[WorkoutsViewModel] Error: \(error.localizedDescription)")
            errorMessage = "Failed to load workouts: \(error.localizedDescription)"
            DebugLogService.shared.log(
                "Workouts refresh threw; serving local repo only",
                details: "error=\(error.localizedDescription), localCount=\(incomingWorkouts.count)",
                metadata: ["source": "WorkoutsViewModel.loadWorkouts.catch.generic"]
            )
        }

        isLoading = false
    }

    /// Decode planned `workout_events` rows for `userId` into the UI's
    /// `Workout` shape. Returns the empty list when there is no signed-in
    /// user — pre-auth launches show nothing rather than leaking another
    /// user's data.
    fileprivate static func hydrateIncoming(userId: String?, eventsRepo: WorkoutEventsRepository) -> [Workout] {
        guard let userId, !userId.isEmpty else { return [] }
        let events: [LocalWorkoutEvent]
        do {
            events = try eventsRepo.todayPlan(userId: userId)
        } catch {
            print("[WorkoutsViewModel] hydrate failed: \(error.localizedDescription)")
            return []
        }
        let decoder = JSONDecoder()
        return events.compactMap { event -> Workout? in
            guard event.deletedAt == nil,
                  event.status == "planned",
                  let data = event.jsonPayload.data(using: .utf8) else { return nil }
            return try? decoder.decode(Workout.self, from: data)
        }
    }

    /// Refresh workouts from API
    func refreshWorkouts() async {
        await loadWorkouts()
    }

    /// Toggle demo mode
    func toggleDemoMode() {
        useDemoMode.toggle()
        if useDemoMode {
            loadMockData()
        } else {
            Task {
                await loadWorkouts()
            }
        }
    }
    
    // MARK: - Computed Properties
    var filteredUpcoming: [ScheduledWorkout] {
        guard !searchQuery.isEmpty else { return upcomingWorkouts }
        return upcomingWorkouts.filter { scheduled in
            scheduled.workout.name.localizedCaseInsensitiveContains(searchQuery) ||
            scheduled.workout.sport.rawValue.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    var filteredIncoming: [Workout] {
        guard !searchQuery.isEmpty else { return incomingWorkouts }
        return incomingWorkouts.filter { workout in
            workout.name.localizedCaseInsensitiveContains(searchQuery) ||
            workout.sport.rawValue.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    // MARK: - Actions
    func scheduleWorkout(_ workout: Workout, date: Date, time: String) async {
        do {
            let success = try await calendarManager.scheduleWorkout(
                workout: workout,
                date: date,
                time: time
            )
            
            if success {
                // Move from incoming to upcoming
                if let index = incomingWorkouts.firstIndex(where: { $0.id == workout.id }) {
                    incomingWorkouts.remove(at: index)
                }
                // AMA-1792: tombstone the local rows so the workout doesn't
                // resurface in `hydrateIncoming` on the next launch. Repo
                // tombstones auto-enqueue a delete to sync_queue.
                tombstoneLocalSuggestion(workoutId: workout.id, reason: "scheduled")
                
                let scheduled = ScheduledWorkout(
                    workout: workout,
                    scheduledDate: date,
                    scheduledTime: time,
                    syncedToApple: true
                )
                upcomingWorkouts.append(scheduled)
                upcomingWorkouts.sort { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
            }
        } catch {
            errorMessage = "Failed to schedule workout: \(error.localizedDescription)"
        }
    }
    
    func sendToWatch(_ workout: Workout) async {
        await WatchConnectivityManager.shared.sendWorkout(workout)
    }

    /// Check for pending workouts from iOS companion endpoint and sync to Watch + WorkoutKit
    func checkPendingWorkouts() async {
        pendingWorkoutsStatus = "Checking..."

        // Check for valid auth
        let hasAuth = dependencies.pairingService.isPaired

        guard hasAuth else {
            pendingWorkoutsStatus = "Not authenticated - skipping"
            print("[WorkoutsViewModel] Not authenticated, skipping pending workout check")
            return
        }

        print("[WorkoutsViewModel] Checking for pending workouts...")

        do {
            let pendingWorkouts = try await dependencies.apiService.fetchPendingWorkouts()

            guard !pendingWorkouts.isEmpty else {
                pendingWorkoutsStatus = "No pending workouts"
                print("[WorkoutsViewModel] No pending workouts found")
                return
            }

            // Build debug info about intervals
            var debugInfo = "Found \(pendingWorkouts.count) workout(s)\n"
            if let firstWorkout = pendingWorkouts.first {
                debugInfo += "First: \(firstWorkout.name)\n"
                for (i, interval) in firstWorkout.intervals.enumerated() {
                    if case .reps(let sets, let reps, let name, _, let restSec, _) = interval {
                        debugInfo += "[\(i)] \(name): sets=\(sets ?? -1), reps=\(reps), restSec=\(restSec ?? -999)\n"
                    }
                }
            }
            pendingWorkoutsStatus = debugInfo
            print("[WorkoutsViewModel] Found \(pendingWorkouts.count) pending workouts, syncing...")

            // Get device preference to determine if we should sync to Apple Watch
            let devicePref = UserDefaults.standard.string(forKey: "devicePreference").flatMap { DevicePreference(rawValue: $0) } ?? .appleWatchPhone

            for workout in pendingWorkouts {
                var syncSuccessful = true
                var syncError: String?

                // Only sync to Apple Watch if user has selected Apple Watch mode
                if devicePref == .appleWatchPhone || devicePref == .appleWatchOnly {
                    await WatchConnectivityManager.shared.sendWorkout(workout)
                    print("[WorkoutsViewModel] Sent '\(workout.name)' to Watch")
                } else {
                    print("[WorkoutsViewModel] Skipping Watch sync for '\(workout.name)' - device preference is \(devicePref.rawValue)")
                }

                // Save to WorkoutKit (iOS 18+)
                // Skip in test mode to avoid WorkoutKit authorization system dialog
                #if DEBUG
                let skipWorkoutKit = UITestEnvironment.shared.hasClerkTestUser
                #else
                let skipWorkoutKit = false
                #endif
                if !skipWorkoutKit, #available(iOS 18.0, *) {
                    do {
                        try await WorkoutKitConverter.shared.saveToWorkoutKit(workout)
                        print("[WorkoutsViewModel] Saved '\(workout.name)' to WorkoutKit")
                    } catch {
                        print("[WorkoutsViewModel] Failed to save to WorkoutKit: \(error.localizedDescription)")
                        syncSuccessful = false
                        syncError = "WorkoutKit save failed: \(error.localizedDescription)"
                    }
                }

                // Add to local workouts list if not already present
                if !incomingWorkouts.contains(where: { $0.id == workout.id }) {
                    incomingWorkouts.append(workout)
                    print("[WorkoutsViewModel] Added '\(workout.name)' to incoming workouts")
                }

                // Confirm or report sync status to backend (AMA-307)
                if syncSuccessful {
                    do {
                        try await dependencies.apiService.confirmSync(workoutId: workout.id)
                        print("[WorkoutsViewModel] Confirmed sync for '\(workout.name)'")
                    } catch {
                        print("[WorkoutsViewModel] Failed to confirm sync: \(error.localizedDescription)")
                        // Non-fatal - workout was still synced locally
                    }
                } else if let error = syncError {
                    do {
                        try await dependencies.apiService.reportSyncFailed(workoutId: workout.id, error: error)
                        print("[WorkoutsViewModel] Reported sync failure for '\(workout.name)'")
                    } catch {
                        print("[WorkoutsViewModel] Failed to report sync failure: \(error.localizedDescription)")
                    }
                }
            }

            // Keep debug info visible, just append sync status
            pendingWorkoutsStatus = debugInfo + "\n✅ Synced!"
            print("[WorkoutsViewModel] Finished syncing \(pendingWorkouts.count) pending workouts")
        } catch {
            // Show more detailed error info including raw response
            if case APIError.serverErrorWithBody(_, let body) = error {
                pendingWorkoutsStatus = body
            } else if case APIError.decodingError(let decodeError) = error {
                pendingWorkoutsStatus = "Decode: \(decodeError)"
            } else {
                pendingWorkoutsStatus = "Error: \(error.localizedDescription)"
            }
            print("[WorkoutsViewModel] Failed to fetch pending workouts: \(error)")
        }
    }

    func deleteWorkout(_ workout: ScheduledWorkout) {
        upcomingWorkouts.removeAll { $0.id == workout.id }
    }

    /// Mark a workout as completed - removes from incoming and upcoming lists (AMA-237)
    /// Called after WorkoutCompletionService.submitCompletion() succeeds
    func markWorkoutCompleted(_ workoutId: String) {
        let incomingBefore = incomingWorkouts.count
        let upcomingBefore = upcomingWorkouts.count

        // Remove from incoming (if present)
        incomingWorkouts.removeAll { $0.id == workoutId }

        // Remove from upcoming (scheduled workouts)
        upcomingWorkouts.removeAll { $0.workout.id == workoutId }

        // AMA-1792: tombstone the local rows so a completed workout doesn't
        // re-hydrate from `workout_events` on next launch.
        tombstoneLocalSuggestion(workoutId: workoutId, reason: "completed")

        let incomingRemoved = incomingBefore - incomingWorkouts.count
        let upcomingRemoved = upcomingBefore - upcomingWorkouts.count

        print("[WorkoutsViewModel] Marked workout \(workoutId) as completed")
        print("[WorkoutsViewModel] Removed: \(incomingRemoved) incoming, \(upcomingRemoved) upcoming")

        // Log to DebugLogService for in-app visibility (AMA-271)
        DebugLogService.shared.log(
            "Workout: Completed",
            details: "Removed from incoming: \(incomingRemoved), upcoming: \(upcomingRemoved)",
            metadata: ["workoutId": workoutId]
        )
    }
    
    // MARK: - Accepted suggestions (AMA-1792 local-first)

    /// Persist an accepted Suggest-Workout result through the GRDB-backed
    /// repos. The accepted_suggestions row carries the canonical record
    /// for the SyncEngine's POST /workouts/accept-suggestion call; the
    /// workout_events row drives the Home read path (status='planned',
    /// source='suggestion_accepted').
    func acceptSuggestedWorkout(_ workout: Workout) {
        guard let userId = currentUserId, !userId.isEmpty else {
            DebugLogService.shared.log(
                "Accepted suggestion skipped — no signed-in user",
                details: "workoutId=\(workout.id)",
                metadata: ["source": "WorkoutsViewModel.acceptSuggestedWorkout"]
            )
            return
        }

        let timestamp = Date()
        let dateString = WorkoutEventsRepository.dayString(timestamp)
        let clientId = UUID().uuidString
        let payload = (try? encodeToJSONString(workout)) ?? "{}"

        let suggestion = LocalAcceptedSuggestion(
            id: workout.id,
            userId: userId,
            suggestionId: nil,
            workoutEventId: workout.id,
            status: "accepted",
            clientGeneratedId: clientId,
            serverVersion: 0,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )
        let event = LocalWorkoutEvent(
            id: workout.id,
            userId: userId,
            date: dateString,
            startTime: nil,
            endTime: nil,
            status: "planned",
            source: "suggestion_accepted",
            jsonPayload: payload,
            clientGeneratedId: clientId,
            serverVersion: 0,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )

        do {
            // FK: accepted_suggestions.workout_event_id → workout_events.id.
            // Upsert the event first or the parent insert violates the FK.
            _ = try eventsRepo.upsert(event, enqueueSync: true)
            _ = try acceptedRepo.insert(suggestion, enqueueSync: true)
            DebugLogService.shared.log(
                "Accepted suggestion persisted (local-first)",
                details: "userId=\(userId) clientId=\(clientId)",
                metadata: ["workoutId": workout.id, "workoutName": workout.name]
            )
        } catch {
            DebugLogService.shared.log(
                "Accepted suggestion local write failed",
                details: error.localizedDescription,
                metadata: ["workoutId": workout.id]
            )
        }

        if !incomingWorkouts.contains(where: { $0.id == workout.id }) {
            incomingWorkouts.append(workout)
        }
    }

    /// Tombstone both the accepted_suggestion and workout_event rows for a
    /// given workout id. Each repo enqueues its own delete to sync_queue.
    private func tombstoneLocalSuggestion(workoutId: String, reason: String) {
        do {
            try acceptedRepo.tombstone(id: workoutId, enqueueSync: true)
        } catch {
            DebugLogService.shared.log(
                "Tombstone accepted_suggestion failed",
                details: error.localizedDescription,
                metadata: ["workoutId": workoutId, "reason": reason]
            )
        }
        do {
            try eventsRepo.tombstone(id: workoutId, enqueueSync: true)
        } catch {
            DebugLogService.shared.log(
                "Tombstone workout_event failed",
                details: error.localizedDescription,
                metadata: ["workoutId": workoutId, "reason": reason]
            )
        }
    }

    // MARK: - Deep-link helpers (AMA-1640)

    private static let deepLinkISODayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Persist a calendar date selection from a deep link so CalendarView /
    /// WorkoutsView can read it on appear. ISO 8601 yyyy-MM-dd or full ISO
    /// timestamps are accepted; parsing failures are silent no-ops.
    func preselectCalendarDate(_ isoDateString: String) {
        print("[deeplink] preselectCalendarDate(\(isoDateString))")
        if let parsed = Self.deepLinkISODayFormatter.date(from: isoDateString) {
            pendingCalendarDate = parsed
            return
        }
        let isoFull = ISO8601DateFormatter()
        if let parsed = isoFull.date(from: isoDateString) {
            pendingCalendarDate = parsed
        }
    }

    /// Mark a workout as the deep-link target. WorkoutsView observes this and
    /// presents the detail sheet on next render. No-op if the id is unknown.
    func selectWorkout(byId id: String) {
        print("[deeplink] selectWorkout(byId: \(id))")
        let inUpcoming = upcomingWorkouts.contains { $0.workout.id == id }
        let inIncoming = incomingWorkouts.contains { $0.id == id }
        guard inUpcoming || inIncoming else { return }
        pendingDeepLinkWorkoutId = id
    }

    func addSampleWorkout() {
        let sampleWorkout = Workout(
            name: "Sample Full Body Strength",
            sport: .strength,
            duration: 1890,
            intervals: [
                .warmup(seconds: 300, target: nil),
                .reps(sets: nil, reps: 8, name: "Squat", load: "80% 1RM", restSec: 90, followAlongUrl: nil),
                .reps(sets: nil, reps: 8, name: "Bench Press", load: nil, restSec: 90, followAlongUrl: nil),
                .reps(sets: nil, reps: 8, name: "Romanian Deadlift", load: nil, restSec: 90, followAlongUrl: nil),
                .repeat(reps: 3, intervals: [
                    .reps(sets: nil, reps: 10, name: "Dumbbell Row", load: nil, restSec: 60, followAlongUrl: nil),
                    .time(seconds: 60, target: nil),
                    .reps(sets: nil, reps: 12, name: "Push Up", load: nil, restSec: nil, followAlongUrl: nil)
                ]),
                .cooldown(seconds: 300, target: nil)
            ],
            description: "Sample workout for testing sync functionality",
            source: .ai
        )
        
        let scheduled = ScheduledWorkout(
            workout: sampleWorkout,
            scheduledDate: Date(),
            scheduledTime: nil,
            syncedToApple: false
        )
        
        upcomingWorkouts.append(scheduled)
        upcomingWorkouts.sort { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }
    
    // MARK: - Mock Data
    private func loadMockData() {
        upcomingWorkouts = [
            ScheduledWorkout(
                workout: Workout(
                    name: "Full Body Strength Workout",
                    sport: .strength,
                    duration: 1890,
                    intervals: [
                        .warmup(seconds: 300, target: nil),
                        .reps(sets: nil, reps: 8, name: "Squat", load: nil, restSec: 90, followAlongUrl: nil),
                        .reps(sets: nil, reps: 8, name: "Bench Press", load: nil, restSec: 90, followAlongUrl: nil),
                        .reps(sets: nil, reps: 8, name: "Romanian Deadlift", load: nil, restSec: 90, followAlongUrl: nil),
                        .repeat(reps: 3, intervals: [
                            .reps(sets: nil, reps: 10, name: "Dumbbell Row", load: nil, restSec: 60, followAlongUrl: nil),
                            .time(seconds: 60, target: nil),
                            .reps(sets: nil, reps: 12, name: "Push Up", load: nil, restSec: nil, followAlongUrl: nil)
                        ]),
                        .cooldown(seconds: 300, target: nil)
                    ],
                    description: "Complete full body workout with compound movements",
                    source: .coach
                ),
                scheduledDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                scheduledTime: "09:00",
                syncedToApple: true
            ),
            
            ScheduledWorkout(
                workout: Workout(
                    name: "Monday Long Run",
                    sport: .running,
                    duration: 3600,
                    intervals: [
                        .warmup(seconds: 300, target: nil),
                        .time(seconds: 2700, target: "Zone 2"),
                        .cooldown(seconds: 600, target: nil)
                    ],
                    description: "Easy conversational pace",
                    source: .coach
                ),
                scheduledDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                scheduledTime: "07:00",
                syncedToApple: true
            ),
            
            ScheduledWorkout(
                workout: Workout(
                    name: "Upper Body Push Day",
                    sport: .strength,
                    duration: 2280,
                    intervals: [
                        .repeat(reps: 4, intervals: [
                            .reps(sets: nil, reps: 6, name: "Bench Press", load: nil, restSec: 120, followAlongUrl: nil),
                            .time(seconds: 120, target: nil),
                            .reps(sets: nil, reps: 8, name: "Overhead Press", load: nil, restSec: 90, followAlongUrl: nil)
                        ]),
                        .repeat(reps: 3, intervals: [
                            .reps(sets: nil, reps: 10, name: "Incline Dumbbell Press", load: nil, restSec: 60, followAlongUrl: nil),
                            .time(seconds: 60, target: nil),
                            .reps(sets: nil, reps: 12, name: "Tricep Dips", load: nil, restSec: nil, followAlongUrl: nil)
                        ])
                    ],
                    description: "Focus on chest, shoulders, and triceps",
                    source: .instagram,
                    sourceUrl: "@strengthcoach"
                ),
                scheduledDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                scheduledTime: "18:00",
                syncedToApple: true
            ),
            
            // HIIT Follow-Along Workout with Instagram links
            ScheduledWorkout(
                workout: Workout(
                    name: "HIIT Follow-Along Workout",
                    sport: .strength,
                    duration: 1800,
                    intervals: [
                        .warmup(seconds: 300, target: nil),
                        .reps(sets: nil, reps: 20, name: "Jumping Jacks", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                        .reps(sets: nil, reps: 15, name: "Burpees", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                        .reps(sets: nil, reps: 30, name: "Mountain Climbers", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                        .reps(sets: nil, reps: 20, name: "High Knees", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                        .reps(sets: nil, reps: 10, name: "Push-ups", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                        .cooldown(seconds: 300, target: nil)
                    ],
                    description: "Follow-along HIIT workout with video links for each exercise",
                    source: .instagram,
                    sourceUrl: "https://www.instagram.com/"
                ),
                scheduledDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()),
                scheduledTime: "10:00",
                syncedToApple: false
            )
        ]
        
        incomingWorkouts = [
            Workout(
                name: "Tuesday Speed Work",
                sport: .running,
                duration: 2640,
                intervals: [
                    .warmup(seconds: 600, target: nil),
                    .repeat(reps: 6, intervals: [
                        .distance(meters: 400, target: nil),
                        .time(seconds: 120, target: nil)
                    ]),
                    .cooldown(seconds: 600, target: nil)
                ],
                description: "400m repeats for speed endurance",
                source: .coach
            ),
            
            Workout(
                name: "Hyrox Training Session",
                sport: .strength,
                duration: 1380,
                intervals: [
                    .warmup(seconds: 180, target: nil),
                    .distance(meters: 1000, target: nil),
                    .reps(sets: nil, reps: 100, name: "Wall Ball", load: nil, restSec: nil, followAlongUrl: nil),
                    .distance(meters: 100, target: nil),
                    .reps(sets: nil, reps: 80, name: "Walking Lunge", load: nil, restSec: nil, followAlongUrl: nil),
                    .distance(meters: 100, target: nil),
                    .reps(sets: nil, reps: 100, name: "Burpee Broad Jump", load: nil, restSec: nil, followAlongUrl: nil),
                    .distance(meters: 1000, target: nil),
                    .cooldown(seconds: 300, target: nil)
                ],
                description: "Race-specific functional fitness training",
                source: .youtube,
                sourceUrl: "Hyrox Training"
            ),
            
            Workout(
                name: "Recovery Yoga Flow",
                sport: .mobility,
                duration: 1800,
                intervals: [
                    .warmup(seconds: 300, target: "Breathing exercises"),
                    .time(seconds: 1200, target: "Flow sequence"),
                    .cooldown(seconds: 300, target: "Savasana")
                ],
                description: "Gentle flow for active recovery",
                source: .ai
            ),
            
            // Mock Follow-Along Workout with Instagram links
            Workout(
                name: "HIIT Follow-Along Workout",
                sport: .strength,
                duration: 1800,
                intervals: [
                    .warmup(seconds: 300, target: nil),
                    .reps(sets: nil, reps: 20, name: "Jumping Jacks", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                    .reps(sets: nil, reps: 15, name: "Burpees", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                    .reps(sets: nil, reps: 30, name: "Mountain Climbers", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                    .reps(sets: nil, reps: 20, name: "High Knees", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                    .reps(sets: nil, reps: 10, name: "Push-ups", load: nil, restSec: 30, followAlongUrl: "https://www.instagram.com/"),
                    .cooldown(seconds: 300, target: nil)
                ],
                description: "Follow-along HIIT workout with video links for each exercise",
                source: .instagram,
                sourceUrl: "https://www.instagram.com/"
            )
        ]
    }
}
