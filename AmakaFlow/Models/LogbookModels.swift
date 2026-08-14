//
//  LogbookModels.swift
//  AmakaFlow
//
//  AMA-2426: notebook-style set-by-set actuals — SetActual + LogDraft.
//

import Foundation

/// How an exercise is logged in the notebook.
enum LogbookLoggingKind: String, Equatable, Codable {
    /// SET · LAST TIME · KG · REPS · ✓
    case strength
    /// TIME / CAL (/ KM) strip — jump rope, bike cals, runs, etc.
    case metric
}

/// One logged (or target) set. Weight is always canonical kilograms.
struct SetActual: Identifiable, Equatable, Codable, Hashable {
    var index: Int
    var isWarmup: Bool
    var weightKg: Double?
    var reps: Int?
    /// Timed stations (jump rope, intervals) — seconds.
    var durationSeconds: Int?
    /// Calorie stations (Assault Bike, etc.).
    var calories: Int?
    /// Distance stations — meters.
    var distanceMeters: Double?
    /// Nil until the athlete checks ✓ — unchecked rows are targets, not history.
    var checkedAt: Date?

    var id: String { "\(isWarmup ? "w" : "s")_\(index)" }

    var isChecked: Bool { checkedAt != nil }

    init(
        index: Int,
        isWarmup: Bool = false,
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        calories: Int? = nil,
        distanceMeters: Double? = nil,
        checkedAt: Date? = nil
    ) {
        self.index = index
        self.isWarmup = isWarmup
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.calories = calories
        self.distanceMeters = distanceMeters
        self.checkedAt = checkedAt
    }
}

/// Ghost shown in LAST TIME / empty cells. Precedence: last actuals > prescription.
struct LogbookGhost: Equatable, Hashable, Codable {
    var weightKg: Double?
    var reps: Int?
    var durationSeconds: Int?
    var calories: Int?
    var distanceMeters: Double?
    var source: ActualsGhostSource

    init(
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        calories: Int? = nil,
        distanceMeters: Double? = nil,
        source: ActualsGhostSource
    ) {
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.calories = calories
        self.distanceMeters = distanceMeters
        self.source = source
    }

    var isEmpty: Bool {
        weightKg == nil
            && reps == nil
            && durationSeconds == nil
            && calories == nil
            && distanceMeters == nil
    }

    func displayLine(unit: WeightUnit) -> String {
        if durationSeconds != nil || calories != nil || distanceMeters != nil {
            return metricDisplayLine
        }
        let weightText: String
        if let weightKg {
            weightText = WeightUnitMath.formatWeight(kg: weightKg, unit: unit)
        } else {
            weightText = "—"
        }
        let repsText = reps.map(String.init) ?? "—"
        return "\(weightText) × \(repsText)"
    }

    var metricDisplayLine: String {
        var parts: [String] = []
        if let durationSeconds {
            parts.append(LogbookMetricFormat.duration(durationSeconds))
        }
        if let calories {
            parts.append("\(calories) CAL")
        }
        if let distanceMeters {
            parts.append(LogbookMetricFormat.distanceKm(distanceMeters))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

enum LogbookMetricFormat {
    static func duration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let secs = clamped % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    static func distanceKm(_ meters: Double) -> String {
        let km = meters / 1000
        if abs(km - km.rounded()) < 0.05 {
            return "\(Int(km.rounded())) KM"
        }
        return String(format: "%.1f KM", km)
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
    /// Strength grid vs TIME/CAL metric strip.
    var loggingKind: LogbookLoggingKind
    var plannedDurationSeconds: Int?
    var plannedCalories: Int?
    var plannedDistanceMeters: Int?
    /// Cardio strip (TIME/KM/CAL/HR) when device-filled — still editable unless noted.
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
        loggingKind: LogbookLoggingKind = .strength,
        plannedDurationSeconds: Int? = nil,
        plannedCalories: Int? = nil,
        plannedDistanceMeters: Int? = nil,
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
        self.loggingKind = loggingKind
        self.plannedDurationSeconds = plannedDurationSeconds
        self.plannedCalories = plannedCalories
        self.plannedDistanceMeters = plannedDistanceMeters
        self.cardioStrip = cardioStrip
    }

    enum CodingKeys: String, CodingKey {
        case id, name, planned, sets, ghosts
        case structureHeader, structureBlockIndex, supersetPartner
        case loggingKind, plannedDurationSeconds, plannedCalories, plannedDistanceMeters
        case cardioStrip
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        planned = try container.decode(ExerciseActualPlanned.self, forKey: .planned)
        sets = try container.decodeIfPresent([SetActual].self, forKey: .sets) ?? []
        ghosts = try container.decodeIfPresent([LogbookGhost].self, forKey: .ghosts) ?? []
        structureHeader = try container.decodeIfPresent(String.self, forKey: .structureHeader)
        structureBlockIndex = try container.decodeIfPresent(Int.self, forKey: .structureBlockIndex)
        supersetPartner = try container.decodeIfPresent(String.self, forKey: .supersetPartner)
        loggingKind = try container.decodeIfPresent(LogbookLoggingKind.self, forKey: .loggingKind) ?? .strength
        plannedDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .plannedDurationSeconds)
        plannedCalories = try container.decodeIfPresent(Int.self, forKey: .plannedCalories)
        plannedDistanceMeters = try container.decodeIfPresent(Int.self, forKey: .plannedDistanceMeters)
        cardioStrip = try container.decodeIfPresent(LogbookCardioStrip.self, forKey: .cardioStrip)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(planned, forKey: .planned)
        try container.encode(sets, forKey: .sets)
        try container.encode(ghosts, forKey: .ghosts)
        try container.encodeIfPresent(structureHeader, forKey: .structureHeader)
        try container.encodeIfPresent(structureBlockIndex, forKey: .structureBlockIndex)
        try container.encodeIfPresent(supersetPartner, forKey: .supersetPartner)
        try container.encode(loggingKind, forKey: .loggingKind)
        try container.encodeIfPresent(plannedDurationSeconds, forKey: .plannedDurationSeconds)
        try container.encodeIfPresent(plannedCalories, forKey: .plannedCalories)
        try container.encodeIfPresent(plannedDistanceMeters, forKey: .plannedDistanceMeters)
        try container.encodeIfPresent(cardioStrip, forKey: .cardioStrip)
    }

    var isMetric: Bool { loggingKind == .metric }

    var plannedLine: String {
        if isMetric {
            if let plannedDurationSeconds {
                return "PLANNED \(LogbookMetricFormat.duration(plannedDurationSeconds))"
            }
            if let plannedCalories {
                return "PLANNED \(plannedCalories) CAL"
            }
            if let plannedDistanceMeters {
                return "PLANNED \(LogbookMetricFormat.distanceKm(Double(plannedDistanceMeters)))"
            }
            return "PLANNED TIME / CAL"
        }
        return "PLANNED \(planned.displayLine)"
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

enum LogbookWheelMode: String, Equatable, Hashable, Codable {
    case weightReps
    case metric
}

/// Wheel sheet focus.
struct LogbookWheelFocus: Equatable, Hashable {
    var exerciseID: String
    var setIndex: Int
    var mode: LogbookWheelMode

    init(exerciseID: String, setIndex: Int, mode: LogbookWheelMode = .weightReps) {
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.mode = mode
    }
}
