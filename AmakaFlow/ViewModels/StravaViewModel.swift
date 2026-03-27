//
//  StravaViewModel.swift
//  AmakaFlow
//
//  ViewModel for the Strava integration screen.
//  Manages connection state, athlete info, and activities list.
//  AMA-1235
//

import Foundation
import Combine
import UIKit
import os.log

private let logger = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "StravaViewModel")

@MainActor
class StravaViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isLoading: Bool = false
    @Published var isConnected: Bool = false
    @Published var athlete: StravaAthlete?
    @Published var activities: [StravaActivity] = []
    @Published var errorMessage: String?
    @Published var isConnecting: Bool = false

    private let stravaService = StravaService.shared

    // MARK: - Lifecycle

    func checkConnectionStatus() async {
        isLoading = true
        errorMessage = nil

        let fetchedAthlete = await stravaService.getAthlete()

        if let fetchedAthlete {
            athlete = fetchedAthlete
            isConnected = true
            logger.info("Strava connected: \(fetchedAthlete.displayName)")

            // Fetch activities once connected
            await fetchActivities()
        } else {
            athlete = nil
            isConnected = false
            activities = []
        }

        isLoading = false
    }

    // MARK: - Connect

    func connect() async {
        isConnecting = true
        errorMessage = nil

        do {
            let authURL = try await stravaService.initiateOAuth()

            // Open in Safari (SFSafariViewController or system browser)
            // The OAuth callback is handled by the backend, which redirects
            // to the frontend URL. For the mobile app, we just open the URL
            // and re-check connection status when the user returns.
            await MainActor.run {
                UIApplication.shared.open(authURL)
            }

            logger.info("Opened Strava OAuth URL in browser")

            // Wait a moment for the user to complete OAuth, then check status
            // The actual re-check happens in onAppear/task when the user returns
        } catch {
            logger.error("Connect failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }

    // MARK: - Fetch Activities

    func fetchActivities() async {
        do {
            let fetchedActivities = try await stravaService.getActivities(limit: 20)
            activities = fetchedActivities
            logger.info("Fetched \(fetchedActivities.count) Strava activities")
        } catch {
            logger.error("Fetch activities failed: \(error.localizedDescription)")
            if case StravaError.notAuthenticated = error {
                isConnected = false
                athlete = nil
                activities = []
            } else {
                errorMessage = "Failed to load activities"
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        stravaService.disconnect()
        isConnected = false
        athlete = nil
        activities = []
        errorMessage = nil
        logger.info("Strava disconnected")
    }

    // MARK: - Refresh

    func refresh() async {
        await checkConnectionStatus()
    }
}
