//
//  HomeViewModel.swift
//  AmakaFlow
//
//  AMA-1993: derives the Home screen state from existing workout data.
//

import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    enum ScreenState: Equatable {
        case loading
        case content
        case empty
        case error(CTAError)
    }

    @Published private(set) var state: ScreenState = .loading
    @Published private(set) var ctaError: CTAError?
    /// Composite readiness from today's DayState (`GET /v1/planning/days`). Nil when absent — never fabricated.
    @Published private(set) var readinessScore: Int?

    private let calendar: Calendar
    private let now: () -> Date
    private let apiService: APIServiceProviding

    init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        apiService: APIServiceProviding = AppDependencies.live.apiService
    ) {
        self.calendar = calendar
        self.now = now
        self.apiService = apiService
    }

    func loadReadiness() async {
        let todayKey = Self.dayKeyFormatter.string(from: now())
        do {
            let states = try await apiService.fetchDayStates(from: todayKey, to: todayKey)
            readinessScore = states.first?.readinessScore
        } catch {
            readinessScore = nil
        }
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func update(from workoutsViewModel: WorkoutsViewModel) {
        update(
            isLoading: workoutsViewModel.isLoading,
            hasLoadedWorkouts: workoutsViewModel.hasLoadedWorkouts,
            incomingWorkouts: workoutsViewModel.incomingWorkouts,
            upcomingWorkouts: workoutsViewModel.upcomingWorkouts,
            activeBlock: workoutsViewModel.activeBlock,
            loadError: workoutsViewModel.ctaError
        )
    }

    func update(
        isLoading: Bool,
        hasLoadedWorkouts: Bool = true,
        incomingWorkouts: [Workout],
        upcomingWorkouts: [ScheduledWorkout],
        activeBlock: TrainingBlock?,
        loadError: CTAError? = nil
    ) {
        let derivedState = Self.deriveState(
            incomingWorkouts: incomingWorkouts,
            upcomingWorkouts: upcomingWorkouts,
            activeBlock: activeBlock,
            calendar: calendar,
            now: now()
        )

        if derivedState == .content {
            ctaError = nil
            state = .content
            return
        }

        if isLoading || (!hasLoadedWorkouts && loadError == nil) {
            ctaError = nil
            state = .loading
            return
        }

        if let loadError {
            ctaError = loadError
            state = .error(loadError)
            return
        }

        ctaError = nil
        state = derivedState
    }

    func applyLoadFailure(_ error: Error) {
        let mapped = CTAError.map(error)
        ctaError = mapped
        state = .error(mapped)
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        reporter.report(
            action: "home_load",
            error: ctaError,
            endpoint: "/workouts",
            userId: PairingService.shared.userProfile?.id
        )
    }

    static func deriveState(
        incomingWorkouts: [Workout],
        upcomingWorkouts: [ScheduledWorkout],
        activeBlock: TrainingBlock?,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> ScreenState {
        let hasActivePlan = activeBlock != nil || !upcomingWorkouts.isEmpty
        let hasWorkoutToday = !incomingWorkouts.isEmpty || upcomingWorkouts.contains { scheduled in
            guard let scheduledDate = scheduled.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: now)
        }

        return (hasActivePlan || hasWorkoutToday) ? .content : .empty
    }
}
