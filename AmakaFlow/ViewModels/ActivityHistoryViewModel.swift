//
//  ActivityHistoryViewModel.swift
//  AmakaFlow
//
//  ViewModel for activity history list with pagination and filtering
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "ActivityHistory")

// MARK: - Filter Options

enum ActivityHistoryFilter: String, CaseIterable {
    case all = "All"
    case thisWeek = "This Week"
    case thisMonth = "This Month"

    var dateThreshold: Date? {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .all:
            return nil
        case .thisWeek:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .thisMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        }
    }
}

// MARK: - Grouped Completions

struct CompletionGroup: Identifiable {
    let id: String
    let title: String
    let completions: [WorkoutCompletion]

    init(category: WorkoutCompletion.DateCategory, completions: [WorkoutCompletion]) {
        self.id = category.title
        self.title = category.title
        self.completions = completions.sorted { $0.startedAt > $1.startedAt }
    }
}

// MARK: - ViewModel

@MainActor
class ActivityHistoryViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var completions: [WorkoutCompletion] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    @Published var selectedFilter: ActivityHistoryFilter = .all
    @Published var useDemoMode: Bool = false

    // MARK: - Pagination

    private var currentOffset: Int = 0
    private let pageSize: Int = 20
    private var hasMoreData: Bool = true

    // MARK: - Dependencies

    private let dependencies: AppDependencies

    // MARK: - Initialization

    @MainActor
    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Computed Properties

    /// Completions filtered by the selected filter
    var filteredCompletions: [WorkoutCompletion] {
        guard let threshold = selectedFilter.dateThreshold else {
            return completions
        }
        return completions.filter { $0.startedAt >= threshold }
    }

    /// Completions grouped by date category
    var groupedCompletions: [CompletionGroup] {
        let grouped = Dictionary(grouping: filteredCompletions) { $0.dateCategory }

        return grouped.map { category, completions in
            CompletionGroup(category: category, completions: completions)
        }
        .sorted { $0.completions.first?.startedAt ?? Date() > $1.completions.first?.startedAt ?? Date() }
    }

    /// Weekly summary for the current week's completions
    var weeklySummary: WeeklySummary {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let thisWeekCompletions = completions.filter { $0.startedAt >= weekAgo }
        return WeeklySummary(completions: thisWeekCompletions)
    }

    /// Whether there are any completions to display
    var isEmpty: Bool {
        filteredCompletions.isEmpty && !isLoading
    }

    /// Whether we can load more data
    var canLoadMore: Bool {
        hasMoreData && !isLoadingMore && !isLoading
    }

    // MARK: - Data Loading

    /// Initial load of completions
    func loadCompletions() async {
        isLoading = true
        errorMessage = nil
        currentOffset = 0
        hasMoreData = true

        // Use demo mode only if explicitly enabled
        if useDemoMode {
            loadMockData()
            isLoading = false
            return
        }

        // Check if we have valid auth
        let hasAuth = dependencies.pairingService.isPaired

        // If not authenticated, show empty state (no mock data)
        if !hasAuth {
            completions = []
            hasMoreData = false
            isLoading = false
            return
        }

        do {
            logger.info("loadCompletions: Fetching from API...")
            let fetched = try await dependencies.apiService.fetchCompletions(limit: pageSize, offset: 0)
            completions = fetched
            hasMoreData = fetched.count >= pageSize
            currentOffset = fetched.count
            logger.info("loadCompletions: Got \(fetched.count) completions")
            // Log to DebugLogService for in-app visibility (AMA-271)
            DebugLogService.shared.log(
                "History: Loaded",
                details: "Got \(fetched.count) completions",
                metadata: nil
            )
        } catch is CancellationError {
            // Task was cancelled (view dismissed, new request started) - ignore silently
            logger.debug("loadCompletions cancelled")
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URL request was cancelled - ignore silently
            logger.debug("loadCompletions URL request cancelled")
        } catch let error as APIError {
            handleAPIError(error)
            logger.error("loadCompletions: API error \(error.localizedDescription)")
            DebugLogService.shared.log(
                "History: ERROR",
                details: error.localizedDescription,
                metadata: nil
            )
        } catch {
            errorMessage = "Failed to load activities: \(error.localizedDescription)"
            completions = []
            logger.error("loadCompletions: Error \(error.localizedDescription)")
            DebugLogService.shared.log(
                "History: ERROR",
                details: error.localizedDescription,
                metadata: nil
            )
        }

        isLoading = false
    }

    /// Refresh completions (pull-to-refresh)
    func refreshCompletions() async {
        await loadCompletions()
    }

    /// Load more completions (pagination)
    func loadMoreIfNeeded(currentItem: WorkoutCompletion?) async {
        guard canLoadMore else { return }

        // Load more when we're near the end of the list
        guard let currentItem = currentItem,
              let index = filteredCompletions.firstIndex(where: { $0.id == currentItem.id }),
              index >= filteredCompletions.count - 3 else {
            return
        }

        await loadMore()
    }

    /// Load next page of completions
    func loadMore() async {
        guard canLoadMore else { return }

        isLoadingMore = true

        // Check if we have valid auth
        let hasAuth = dependencies.pairingService.isPaired

        if useDemoMode || !hasAuth {
            // No more data to load in demo mode or when not authenticated
            hasMoreData = false
            isLoadingMore = false
            return
        }

        do {
            let fetched = try await dependencies.apiService.fetchCompletions(limit: pageSize, offset: currentOffset)
            completions.append(contentsOf: fetched)
            hasMoreData = fetched.count >= pageSize
            currentOffset += fetched.count
        } catch {
            // Silently fail on pagination errors
            print("[ActivityHistoryViewModel] Pagination error: \(error)")
        }

        isLoadingMore = false
    }

    // MARK: - Error Handling

    private func handleAPIError(_ error: APIError) {
        switch error {
        case .unauthorized:
            errorMessage = "Session expired. Please reconnect."
        case .networkError:
            errorMessage = "Network error. Please check your connection."
        default:
            errorMessage = error.localizedDescription
        }
        completions = []
    }

    // MARK: - Mock Data

    private func loadMockData() {
        completions = WorkoutCompletion.sampleData
        hasMoreData = false
    }

    /// Toggle demo mode
    func toggleDemoMode() {
        useDemoMode.toggle()
        Task {
            await loadCompletions()
        }
    }
}

