//
//  AppDelegate.swift
//  AmakaFlowCompanion
//
//  Handles APNs push notification registration and silent push delivery (AMA-567).
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Weak reference to the workouts view model, set by AmakaFlowCompanionApp on launch.
    /// Used to await sync completion before calling the silent push completion handler.
    weak var workoutsViewModel: WorkoutsViewModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Skip push registration in E2E test mode
        #if DEBUG
        if UITestEnvironment.shared.hasClerkTestUser || UITestEnvironment.shared.useFixtures {
            print("[AppDelegate] Test mode — skipping push notification registration")
            return true
        }
        #endif

        requestPushPermission(application)
        return true
    }

    // MARK: - Push Permission

    private func requestPushPermission(_ application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                print("[AppDelegate] Push permission error: \(error.localizedDescription)")
                return
            }
            print("[AppDelegate] Push permission granted: \(granted)")
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - APNs Token Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[AppDelegate] APNs token: \(tokenString.prefix(16))...")

        Task {
            await PairingService.shared.registerAPNsToken(tokenString)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Failed to register for push: \(error.localizedDescription)")
    }

    // MARK: - Silent Push Handling

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("[AppDelegate] Silent push received: \(userInfo)")

        // Determine notification type (AMA-1133)
        let notificationType = userInfo["type"] as? String ?? "unknown"
        print("[AppDelegate] Notification type: \(notificationType)")

        // Post notification for any foreground observers
        NotificationCenter.default.post(name: .refreshPendingWorkouts, object: nil, userInfo: userInfo)

        // Await the actual sync before telling iOS we're done,
        // so the system doesn't suspend us mid-fetch
        Task { @MainActor in
            if let vm = self.workoutsViewModel {
                await vm.checkPendingWorkouts()
                completionHandler(.newData)
            } else {
                completionHandler(.noData)
            }
        }
    }

    // MARK: - Foreground Notification Handling (AMA-1133)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let notificationType = userInfo["type"] as? String ?? "unknown"
        print("[AppDelegate] Foreground notification: \(notificationType)")

        // Show banner + sound for all notification types while app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let notificationType = userInfo["type"] as? String ?? "unknown"
        print("[AppDelegate] Notification tapped: \(notificationType)")

        // Post deep link notification based on type (AMA-1133)
        switch notificationType {
        case "workout_reminder":
            NotificationCenter.default.post(name: .deepLinkToWorkout, object: nil, userInfo: userInfo)
        case "sync_complete", "sync_failed":
            NotificationCenter.default.post(name: .deepLinkToSync, object: nil, userInfo: userInfo)
        case "conflict_detected":
            NotificationCenter.default.post(name: .deepLinkToCalendar, object: nil, userInfo: userInfo)
        case "readiness_update":
            NotificationCenter.default.post(name: .deepLinkToCalendar, object: nil, userInfo: userInfo)
        case "coach_message":
            NotificationCenter.default.post(name: .deepLinkToCoach, object: nil, userInfo: userInfo)
        case "nutrition_update":
            NotificationCenter.default.post(name: .deepLinkToNutrition, object: nil, userInfo: userInfo)
        default:
            NotificationCenter.default.post(name: .refreshPendingWorkouts, object: nil, userInfo: userInfo)
        }

        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let refreshPendingWorkouts = Notification.Name("refreshPendingWorkouts")
    // Deep link notifications (AMA-1133)
    static let deepLinkToWorkout = Notification.Name("deepLinkToWorkout")
    static let deepLinkToSync = Notification.Name("deepLinkToSync")
    static let deepLinkToCalendar = Notification.Name("deepLinkToCalendar")
    static let deepLinkToCoach = Notification.Name("deepLinkToCoach")
    static let deepLinkToNutrition = Notification.Name("deepLinkToNutrition")
}
