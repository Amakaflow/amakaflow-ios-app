//
//  WorkoutsViewModel.swift
//  AmakaFlow
//
//  Manages workout state and business logic
//

import Foundation
import Combine

@MainActor
class WorkoutsViewModel: ObservableObject {
    @Published var upcomingWorkouts: [ScheduledWorkout] = []
    @Published var incomingWorkouts: [Workout] = []
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var useDemoMode: Bool = false
    @Published var pendingWorkoutsStatus: String = ""  // Debug status for pending workouts

    private let calendarManager = CalendarManager()
    private let apiService = APIService.shared

    init() {
        // Start with empty data - will load from API or demo mode
    }

    // MARK: - Data Loading

    /// Load workouts from API or demo mode
    func loadWorkouts() async {
        isLoading = true
        errorMessage = nil

        // Only show mock data if explicitly in demo mode OR not paired
        if useDemoMode {
            print("[WorkoutsViewModel] Demo mode enabled, loading mock data")
            loadMockData()
            isLoading = false
            return
        }

        if !PairingService.shared.isPaired {
            print("[WorkoutsViewModel] Not paired, loading mock data")
            loadMockData()
            isLoading = false
            return
        }

        print("[WorkoutsViewModel] Fetching workouts from API...")

        do {
            async let fetchedWorkouts = apiService.fetchWorkouts()
            async let fetchedScheduled = apiService.fetchScheduledWorkouts()

            let (workouts, scheduled) = try await (fetchedWorkouts, fetchedScheduled)

            print("[WorkoutsViewModel] Fetched \(workouts.count) workouts, \(scheduled.count) scheduled")
            incomingWorkouts = workouts
            upcomingWorkouts = scheduled
        } catch let error as APIError {
            print("[WorkoutsViewModel] API error: \(error.localizedDescription)")
            if case .unauthorized = error {
                // Token expired, user needs to re-pair
                errorMessage = "Session expired. Please reconnect."
            } else {
                errorMessage = error.localizedDescription
                // Don't fall back to mock data - show empty state instead
                incomingWorkouts = []
                upcomingWorkouts = []
            }
        } catch {
            print("[WorkoutsViewModel] Error: \(error.localizedDescription)")
            errorMessage = "Failed to load workouts: \(error.localizedDescription)"
            // Don't fall back to mock data - show empty state instead
            incomingWorkouts = []
            upcomingWorkouts = []
        }

        isLoading = false
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

        guard PairingService.shared.isPaired else {
            pendingWorkoutsStatus = "Not paired - skipping"
            print("[WorkoutsViewModel] Not paired, skipping pending workout check")
            return
        }

        print("[WorkoutsViewModel] Checking for pending workouts...")

        do {
            let pendingWorkouts = try await apiService.fetchPendingWorkouts()

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

            for workout in pendingWorkouts {
                // Sync to Watch
                await WatchConnectivityManager.shared.sendWorkout(workout)
                print("[WorkoutsViewModel] Sent '\(workout.name)' to Watch")

                // Save to WorkoutKit (iOS 18+)
                if #available(iOS 18.0, *) {
                    do {
                        try await WorkoutKitConverter.shared.saveToWorkoutKit(workout)
                        print("[WorkoutsViewModel] Saved '\(workout.name)' to WorkoutKit")
                    } catch {
                        print("[WorkoutsViewModel] Failed to save to WorkoutKit: \(error.localizedDescription)")
                    }
                }

                // Add to local workouts list if not already present
                if !incomingWorkouts.contains(where: { $0.id == workout.id }) {
                    incomingWorkouts.append(workout)
                    print("[WorkoutsViewModel] Added '\(workout.name)' to incoming workouts")
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
