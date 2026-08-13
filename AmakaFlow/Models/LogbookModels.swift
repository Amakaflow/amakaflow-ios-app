//
//  LogbookModels.swift
//  AmakaFlow
//
//  AMA-2426: notebook-style set-by-set actuals — SetActual + LogDraft.
//

import Foundation

/// One logged (or target) set. Weight is always canonical kilograms.
struct SetActual: Identifiable, Equatable, Codable, Hashable {
    var index: Int
    var isWarmup: Bool
    var weightKg: Double?
    var reps: Int?
    /// Nil until the athlete checks ✓ — unchecked rows are targets, not history.
    var checkedAt: Date?

    var id: String { "\(isWarmup ? "w" : "s")_\(index)" }

    var isChecked: Bool { checkedAt != nil }

    init(
        index: Int,
        isWarmup: Bool = false,
        weightKg: Double? = nil,
        reps: Int? = nil,
        checkedAt: Date? = nil
    ) {
        self.index = index
        self.isWarmup = isWarmup
        self.weightKg = weightKg
        self.reps = reps
        self.checkedAt = checkedAt
    }
}

/// Ghost shown in LAST TIME / empty cells. Precedence: last actuals > prescription.
struct LogbookGhost: Equatable, Hashable, Codable {
    var weightKg: Double?
    var reps: Int?
    var source: ActualsGhostSource

    var isEmpty: Bool { weightKg == nil && reps == nil }

    func displayLine(unit: WeightUnit) -> String {
        let weightText: String
        if let weightKg {
            weightText = WeightUnitMath.formatWeight(kg: weightKg, unit: unit)
        } else {
            weightText = "—"
        }
        let repsText = reps.map(String.init) ?? "—"
        return "\(weightText) × \(repsText)"
    }
}

enum LogDraftState: String, Equatable, Codable {
    case live
    case pending
    case committed
}

/// AMA-2426 session-state modes. Inferred — never user-picked.
enum LogbookMode: String, Equatable, Codable {
    /// Phone is the tracker (elapsed header).
    case live
    /// Native watch Workout app is running our plan — phone is a dumb terminal.
    /// HARD CONSTRAINT: Apple provides NO live channel into a native Workout-app
    /// session; do NOT observe or write into it. Reconcile when HK/Garmin/Strava arrives.
    case companionPending
    /// Editing an existing synced/manual session's actuals.
    case after
}

/// Durable companion / live log draft. Pending drafts must NOT render as Today cards.
struct LogDraft: Identifiable, Equatable, Codable {
    var id: String
    var workoutId: String?
    var title: String
    var subtitle: String
    var startedAt: Date
    var lastEditedAt: Date
    var state: LogDraftState
    var mode: LogbookMode
    /// Attached existing actuals session id when mode == .after (or after reconcile).
    var attachedSessionId: String?
    var entries: [LogbookExerciseEntry]
    var note: String
    var rpe: Int?
    /// Device metrics attached on reconcile (duration/HR/calories/distance).
    var deviceMetrics: LogDraftDeviceMetrics?

    init(
        id: String = UUID().uuidString,
        workoutId: String? = nil,
        title: String,
        subtitle: String = "",
        startedAt: Date = Date(),
        lastEditedAt: Date = Date(),
        state: LogDraftState = .pending,
        mode: LogbookMode = .after,
        attachedSessionId: String? = nil,
        entries: [LogbookExerciseEntry] = [],
        note: String = "",
        rpe: Int? = nil,
        deviceMetrics: LogDraftDeviceMetrics? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.title = title
        self.subtitle = subtitle
        self.startedAt = startedAt
        self.lastEditedAt = lastEditedAt
        self.state = state
        self.mode = mode
        self.attachedSessionId = attachedSessionId
        self.entries = entries
        self.note = note
        self.rpe = rpe
        self.deviceMetrics = deviceMetrics
    }

    var checkedSetCount: Int {
        entries.reduce(0) { $0 + $1.sets.filter(\.isChecked).count }
    }

    var totalSetCount: Int {
        entries.reduce(0) { $0 + $1.sets.count }
    }

    var saveCTATitle: String {
        "Save log · \(checkedSetCount) of \(totalSetCount) sets"
    }

    /// Active window for overlap merge with device sessions.
    var activeWindow: DateInterval {
        let end = max(lastEditedAt, startedAt.addingTimeInterval(60))
        return DateInterval(start: startedAt, end: end)
    }
}

struct LogDraftDeviceMetrics: Equatable, Codable {
    var durationSeconds: TimeInterval?
    var distanceMeters: Double?
    var averageHeartRate: Double?
    var activeCalories: Double?
    var sourceLabel: String?
}

struct LogbookExerciseEntry: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var planned: ExerciseActualPlanned
    var sets: [SetActual]
    /// Per-set ghosts (same length as sets, or empty → derive from planned).
    var ghosts: [LogbookGhost]
    var structureHeader: String?
    var structureBlockIndex: Int?
    /// Partner name for SUPERSET · W/ X tag.
    var supersetPartner: String?
    /// Cardio strip (TIME/KM/CAL/HR) when this entry is device-filled cardio.
    var cardioStrip: LogbookCardioStrip?

    init(
        id: String,
        name: String,
        planned: ExerciseActualPlanned,
        sets: [SetActual] = [],
        ghosts: [LogbookGhost] = [],
        structureHeader: String? = nil,
        structureBlockIndex: Int? = nil,
        supersetPartner: String? = nil,
        cardioStrip: LogbookCardioStrip? = nil
    ) {
        self.id = id
        self.name = name
        self.planned = planned
        self.sets = sets
        self.ghosts = ghosts
        self.structureHeader = structureHeader
        self.structureBlockIndex = structureBlockIndex
        self.supersetPartner = supersetPartner
        self.cardioStrip = cardioStrip
    }

    var plannedLine: String {
        "PLANNED \(planned.displayLine)"
    }

    var supersetTag: String? {
        guard let partner = supersetPartner, !partner.isEmpty else { return nil }
        return "SUPERSET · W/ \(partner.uppercased())"
    }
}

struct LogbookCardioStrip: Equatable, Codable {
    var timeText: String?
    var distanceText: String?
    var caloriesText: String?
    var heartRateText: String?
    var sourceNote: String?
}

/// Wheel sheet focus.
struct LogbookWheelFocus: Equatable, Hashable {
    var exerciseID: String
    var setIndex: Int
}
