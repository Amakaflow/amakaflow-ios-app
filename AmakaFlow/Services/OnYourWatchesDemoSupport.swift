//
//  OnYourWatchesDemoSupport.swift
//  AmakaFlow
//
//  AMA-2375: fixture snapshot / queue / Apple rows for simulator dogfood
//  (`UITEST_FORCE_WATCH_MANAGER=true` or `AMA2375_DEMO=true`).
//

import Foundation

enum OnYourWatchesDemoSupport {
    static var isEnabled: Bool {
        UITestEnvironment.shared.forceWatchManagerDemo
    }

    static var snapshot: OnYourWatchesSnapshot {
        OnYourWatchesSnapshot(
            showsApple: true,
            showsGarmin: true,
            appleScheduledCount: 7,
            appleMaxAllowed: 15,
            appleNextLabel: "TODAY",
            garminOnWatch: 2,
            garminWaiting: 1,
            garminFailed: 1
        )
    }

    static func seedGarminQueueIfNeeded(
        store: any GarminWatchQueueStoring = GarminWatchQueueStore.shared
    ) {
        guard isEnabled else { return }
        guard store.load().isEmpty else { return }
        store.recordPush(workoutID: "demo-hyrox", title: "Hyrox workout")
        store.recordPush(workoutID: "demo-chest", title: "Chest Pump — 45")
        store.recordPush(workoutID: "demo-lower", title: "HYROX — Lower body")
        store.recordPush(workoutID: "demo-erg", title: "Erg Workout For Time")
    }

    static func demoStatus(for workoutID: String) -> Components.Schemas.WatchDeliveryStatus {
        switch workoutID {
        case "demo-hyrox":
            return Components.Schemas.WatchDeliveryStatus(
                state: .confirmedOnDevice,
                subtitle: "Downloaded Sat",
                title: "On watch"
            )
        case "demo-chest":
            return Components.Schemas.WatchDeliveryStatus(
                state: .fetchedByWidget,
                subtitle: "Downloaded today",
                title: "On watch"
            )
        case "demo-lower":
            return Components.Schemas.WatchDeliveryStatus(
                state: .pushed,
                subtitle: "Open the widget to download",
                title: "Sent"
            )
        case "demo-erg":
            return Components.Schemas.WatchDeliveryStatus(
                state: .failed,
                subtitle: "Open reps not supported",
                title: "Failed"
            )
        default:
            return Components.Schemas.WatchDeliveryStatus(
                state: .pushed,
                subtitle: "Queued",
                title: "Sent"
            )
        }
    }

    #if DEBUG
    static func makeAppleScheduler() -> MockWorkoutKitScheduler {
        let scheduler = MockWorkoutKitScheduler()
        scheduler.maxAllowedCount = 15
        let cal = Calendar.current
        let samples: [(String, DateComponents, String)] = [
            ("Chest Pump - 45", DateComponents(hour: 6, minute: 0), "tomorrow"),
            ("Interval repeats", DateComponents(hour: 0, minute: 0), "wed"),
            ("Hyrox Sim – Stations 1–4", DateComponents(hour: 10, minute: 0), "thu"),
            ("Full Body Aesthetics", DateComponents(), "none"),
            ("Zone 2 base run", DateComponents(hour: 0, minute: 0), "sat"),
            ("Engine EMOM", DateComponents(), "none"),
            ("Push day", DateComponents(hour: 7, minute: 30), "today")
        ]
        scheduler.rows = samples.enumerated().map { index, sample in
            let date: Date?
            var comps = sample.1
            switch sample.2 {
            case "today":
                date = cal.date(bySettingHour: comps.hour ?? 7, minute: comps.minute ?? 0, second: 0, of: Date())
            case "tomorrow":
                let base = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                date = cal.date(bySettingHour: comps.hour ?? 6, minute: comps.minute ?? 0, second: 0, of: base)
            case "wed", "thu", "sat":
                date = cal.date(byAdding: .day, value: index + 2, to: Date())
            default:
                date = nil
                comps = DateComponents()
            }
            if let date {
                comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            }
            return WorkoutScheduleRow(
                id: WorkoutScheduleRowID(planID: "demo-\(index)", date: comps),
                title: sample.0,
                dateComponents: comps,
                scheduledAt: date,
                isComplete: false
            )
        }
        return scheduler
    }
    #endif
}
