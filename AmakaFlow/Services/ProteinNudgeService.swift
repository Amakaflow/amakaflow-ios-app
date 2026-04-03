//
//  ProteinNudgeService.swift
//  AmakaFlow
//
//  Protein nudge notification service (AMA-1293).
//  Schedules a local notification 30 minutes after workout completion
//  if the user's protein intake is below 60% of target.
//

import Foundation
import UserNotifications

@MainActor
final class ProteinNudgeService {
    static let shared = ProteinNudgeService()

    private let notificationCenter = UNUserNotificationCenter.current()
    private let nudgeIdentifier = "amakaflow.protein.nudge"
    private let delaySeconds: TimeInterval = 30 * 60  // 30 minutes

    private init() {}

    // MARK: - Public API

    /// Schedule a protein nudge check after workout completion.
    /// Calls POST /nutrition/protein-nudge/check and schedules a local
    /// notification if the user should be nudged.
    func schedulePostWorkoutNudge() async {
        do {
            let response = try await checkProteinNudge()

            guard response.shouldNudge else {
                print("[ProteinNudgeService] No nudge needed — protein at \(response.proteinCurrent)g/\(response.proteinTarget)g")
                return
            }

            await scheduleNotification(message: response.message)
            print("[ProteinNudgeService] Nudge scheduled — \(response.message)")
        } catch {
            print("[ProteinNudgeService] Failed to check nudge: \(error)")
        }
    }

    /// Cancel any pending protein nudge notifications.
    func cancelPendingNudges() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [nudgeIdentifier])
    }

    // MARK: - Notification Scheduling

    private func scheduleNotification(message: String) async {
        // Request permission if needed
        let settings = await notificationCenter.notificationSettings()
        if settings.authorizationStatus != .authorized &&
           settings.authorizationStatus != .provisional {
            do {
                let granted = try await notificationCenter.requestAuthorization(
                    options: [.alert, .sound]
                )
                guard granted else {
                    print("[ProteinNudgeService] Notification permission denied")
                    return
                }
            } catch {
                print("[ProteinNudgeService] Permission request failed: \(error)")
                return
            }
        }

        // Cancel any existing nudge
        cancelPendingNudges()

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Protein Check"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "PROTEIN_NUDGE"

        // Schedule 30 minutes from now
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: delaySeconds,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: nudgeIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("[ProteinNudgeService] Failed to schedule notification: \(error)")
        }
    }

    // MARK: - API

    private func checkProteinNudge() async throws -> ProteinNudgeResponse {
        let baseURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(baseURL)/nutrition/protein-nudge/check") else {
            throw APIError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        #if DEBUG
        if let testAuthSecret = TestAuthStore.shared.authSecret,
           let testUserId = TestAuthStore.shared.userId,
           !testAuthSecret.isEmpty {
            urlRequest.setValue(testAuthSecret, forHTTPHeaderField: "X-Test-Auth")
            urlRequest.setValue(testUserId, forHTTPHeaderField: "X-Test-User-Id")
        } else if let token = PairingService.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #else
        if let token = PairingService.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #endif

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ProteinNudgeResponse.self, from: data)
    }
}

