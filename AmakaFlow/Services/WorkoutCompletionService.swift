//
//  WorkoutCompletionService.swift
//  AmakaFlow
//
//  Handles posting workout completion data to the API
//  Includes offline queuing and retry logic
//

import Foundation
import Combine
import Network

// MARK: - Request/Response Models

struct WorkoutCompletionRequest: Codable {
    let workoutEventId: String?
    let workoutId: String?              // For regular workouts from /ios-companion/pending
    let followAlongWorkoutId: String?   // For follow-along video workouts
    let startedAt: String  // ISO8601
    let endedAt: String    // ISO8601
    let healthMetrics: HealthMetrics
    let source: String     // "apple_watch", "garmin", "phone"
    let deviceInfo: WorkoutDeviceInfo
    let heartRateSamples: [HRSample]?
    let workoutStructure: [WorkoutInterval]?  // Workout structure for "Run Again" (AMA-240)
    let workoutName: String?                  // Workout name for display (AMA-237)

    enum CodingKeys: String, CodingKey {
        case workoutEventId = "workout_event_id"
        case workoutId = "workout_id"
        case followAlongWorkoutId = "follow_along_workout_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case healthMetrics = "health_metrics"
        case source
        case deviceInfo = "device_info"
        case heartRateSamples = "heart_rate_samples"
        case workoutStructure = "workout_structure"
        case workoutName = "workout_name"
    }
}

struct HealthMetrics: Codable {
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let minHeartRate: Int?
    let activeCalories: Int?
    let totalCalories: Int?
    let distanceMeters: Int?
    let steps: Int?

    enum CodingKeys: String, CodingKey {
        case avgHeartRate = "avg_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case minHeartRate = "min_heart_rate"
        case activeCalories = "active_calories"
        case totalCalories = "total_calories"
        case distanceMeters = "distance_meters"
        case steps
    }
}

struct WorkoutDeviceInfo: Codable {
    let platform: String   // "ios", "watchos", "garmin"
    let model: String?
    let osVersion: String?

    enum CodingKeys: String, CodingKey {
        case platform
        case model
        case osVersion = "os_version"
    }
}

struct HRSample: Codable {
    let timestamp: String  // ISO8601
    let value: Int
}

struct WorkoutCompletionResponse: Codable {
    let completionId: String?
    let id: String?           // Alternative field name
    let status: String?
    let success: Bool?

    enum CodingKeys: String, CodingKey {
        case completionId = "completion_id"
        case id
        case status
        case success
    }

    /// Get the completion ID from whichever field is present
    var resolvedCompletionId: String {
        completionId ?? id ?? "unknown"
    }
}

// MARK: - Pending Completion (for offline queue)

struct PendingCompletion: Codable, Identifiable {
    let id: String
    let request: WorkoutCompletionRequest
    let createdAt: Date
    var retryCount: Int

    init(request: WorkoutCompletionRequest) {
        self.id = UUID().uuidString
        self.request = request
        self.createdAt = Date()
        self.retryCount = 0
    }
}

// MARK: - WorkoutCompletionService

@MainActor
class WorkoutCompletionService: ObservableObject {
    static let shared = WorkoutCompletionService()

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastError: Error?
    @Published private(set) var isProcessingQueue: Bool = false

    private let pendingQueueKey = "WorkoutCompletionPendingQueue"
    private let maxRetries = 3
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadPendingQueue()
        setupNetworkMonitoring()
    }

    // MARK: - Debug Logging

    private func logCompletionError(workoutId: String?, error: Error, context: String) {
        DebugLogService.shared.logCompletionError(workoutId: workoutId, error: error, context: context)
    }

    // MARK: - Public API

    /// Post workout completion from phone-controlled workout
    func postPhoneWorkoutCompletion(
        workoutId: String,
        workoutName: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        avgHeartRate: Int? = nil,
        activeCalories: Int? = nil,
        workoutStructure: [WorkoutInterval]? = nil  // (AMA-240) Workout structure for "Run Again"
    ) async throws -> WorkoutCompletionResponse? {
        let healthMetrics = HealthMetrics(
            avgHeartRate: avgHeartRate,
            maxHeartRate: nil,
            minHeartRate: nil,
            activeCalories: activeCalories,
            totalCalories: nil,
            distanceMeters: nil,
            steps: nil
        )

        let deviceInfo = WorkoutDeviceInfo(
            platform: "ios",
            model: getDeviceModel(),
            osVersion: getOSVersion()
        )

        let request = WorkoutCompletionRequest(
            workoutEventId: nil,
            workoutId: workoutId,
            followAlongWorkoutId: nil,
            startedAt: formatISO8601(startedAt),
            endedAt: formatISO8601(endedAt),
            healthMetrics: healthMetrics,
            source: "phone",
            deviceInfo: deviceInfo,
            heartRateSamples: nil,
            workoutStructure: workoutStructure,
            workoutName: workoutName
        )

        return try await postCompletion(request)
    }

    /// Post workout completion from Apple Watch standalone workout
    func postWatchWorkoutCompletion(
        summary: StandaloneWorkoutSummary,
        workoutStructure: [WorkoutInterval]? = nil,  // (AMA-240) Workout structure for "Run Again"
        workoutName: String? = nil
    ) async throws -> WorkoutCompletionResponse? {
        let healthMetrics = HealthMetrics(
            avgHeartRate: summary.averageHeartRate.map { Int($0) },
            maxHeartRate: nil,
            minHeartRate: nil,
            activeCalories: Int(summary.totalCalories),
            totalCalories: nil,
            distanceMeters: nil,
            steps: nil
        )

        let deviceInfo = WorkoutDeviceInfo(
            platform: "watchos",
            model: "Apple Watch",
            osVersion: nil
        )

        let request = WorkoutCompletionRequest(
            workoutEventId: nil,
            workoutId: summary.workoutId,
            followAlongWorkoutId: nil,
            startedAt: formatISO8601(summary.startDate),
            endedAt: formatISO8601(summary.endDate),
            healthMetrics: healthMetrics,
            source: "apple_watch",
            deviceInfo: deviceInfo,
            heartRateSamples: nil,
            workoutStructure: workoutStructure,
            workoutName: workoutName
        )

        return try await postCompletion(request)
    }

    /// Post workout completion from Garmin watch
    func postGarminWorkoutCompletion(
        workoutId: String,
        startedAt: Date,
        endedAt: Date,
        avgHeartRate: Int? = nil,
        activeCalories: Int? = nil,
        workoutStructure: [WorkoutInterval]? = nil,  // (AMA-240) Workout structure for "Run Again"
        workoutName: String? = nil
    ) async throws -> WorkoutCompletionResponse? {
        let healthMetrics = HealthMetrics(
            avgHeartRate: avgHeartRate,
            maxHeartRate: nil,
            minHeartRate: nil,
            activeCalories: activeCalories,
            totalCalories: nil,
            distanceMeters: nil,
            steps: nil
        )

        let deviceInfo = WorkoutDeviceInfo(
            platform: "garmin",
            model: GarminConnectManager.shared.connectedDeviceName,
            osVersion: nil
        )

        let request = WorkoutCompletionRequest(
            workoutEventId: nil,
            workoutId: workoutId,
            followAlongWorkoutId: nil,
            startedAt: formatISO8601(startedAt),
            endedAt: formatISO8601(endedAt),
            healthMetrics: healthMetrics,
            source: "garmin",
            deviceInfo: deviceInfo,
            heartRateSamples: nil,
            workoutStructure: workoutStructure,
            workoutName: workoutName
        )

        return try await postCompletion(request)
    }

    /// Retry all pending completions
    func retryPendingCompletions() async {
        guard !isProcessingQueue else { return }
        guard isNetworkAvailable else {
            print("[WorkoutCompletion] Network unavailable, skipping retry")
            return
        }
        // Don't retry if auth is invalid - wait for user to re-pair
        guard !PairingService.shared.needsReauth else {
            print("[WorkoutCompletion] Auth invalid, skipping retry until re-paired")
            return
        }

        isProcessingQueue = true
        defer { isProcessingQueue = false }

        var pending = loadPendingCompletions()
        var successful: [String] = []

        for completion in pending {
            do {
                _ = try await APIService.shared.postWorkoutCompletion(completion.request)
                successful.append(completion.id)
                print("[WorkoutCompletion] Successfully sent queued completion: \(completion.id)")
            } catch {
                print("[WorkoutCompletion] Failed to send queued completion: \(error)")
                // Update retry count
                if let index = pending.firstIndex(where: { $0.id == completion.id }) {
                    pending[index].retryCount += 1
                }
            }
        }

        // Remove successful ones and those that exceeded max retries
        pending.removeAll { completion in
            successful.contains(completion.id) || completion.retryCount >= maxRetries
        }

        savePendingCompletions(pending)
        pendingCount = pending.count
    }

    // MARK: - Private Methods

    private func postCompletion(_ request: WorkoutCompletionRequest) async throws -> WorkoutCompletionResponse? {
        guard PairingService.shared.isPaired else {
            print("[WorkoutCompletion] Not paired, skipping POST")
            return nil
        }

        // Try to post immediately
        if isNetworkAvailable {
            do {
                let response = try await APIService.shared.postWorkoutCompletion(request)
                print("[WorkoutCompletion] Successfully posted completion: \(response.resolvedCompletionId)")
                return response
            } catch {
                print("[WorkoutCompletion] Failed to post, queueing for retry: \(error)")
                lastError = error
                logCompletionError(workoutId: request.workoutId ?? request.followAlongWorkoutId, error: error, context: "postCompletion")
                queueForRetry(request)
                throw error
            }
        } else {
            // Queue for later
            print("[WorkoutCompletion] Network unavailable, queueing for later")
            logCompletionError(
                workoutId: request.workoutId ?? request.followAlongWorkoutId,
                error: NSError(domain: "WorkoutCompletion", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network unavailable"]),
                context: "Network unavailable - queued for later"
            )
            queueForRetry(request)
            return nil
        }
    }

    private func queueForRetry(_ request: WorkoutCompletionRequest) {
        var pending = loadPendingCompletions()
        pending.append(PendingCompletion(request: request))
        savePendingCompletions(pending)
        pendingCount = pending.count
        print("[WorkoutCompletion] Queued completion, pending count: \(pendingCount)")
    }

    // MARK: - Persistence

    private func loadPendingCompletions() -> [PendingCompletion] {
        guard let data = UserDefaults.standard.data(forKey: pendingQueueKey) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([PendingCompletion].self, from: data)
        } catch {
            print("[WorkoutCompletion] Failed to load pending queue: \(error)")
            return []
        }
    }

    private func savePendingCompletions(_ completions: [PendingCompletion]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(completions)
            UserDefaults.standard.set(data, forKey: pendingQueueKey)
        } catch {
            print("[WorkoutCompletion] Failed to save pending queue: \(error)")
        }
    }

    private func loadPendingQueue() {
        pendingCount = loadPendingCompletions().count
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasAvailable = self?.isNetworkAvailable ?? false
                self?.isNetworkAvailable = path.status == .satisfied

                // If network just became available, retry pending
                if !wasAvailable && path.status == .satisfied {
                    print("[WorkoutCompletion] Network restored, retrying pending completions")
                    await self?.retryPendingCompletions()
                }
            }
        }

        let queue = DispatchQueue(label: "WorkoutCompletionNetworkMonitor")
        networkMonitor.start(queue: queue)
    }

    // MARK: - Helpers

    private func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    private func getOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
