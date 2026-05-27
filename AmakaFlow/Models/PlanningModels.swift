//
//  PlanningModels.swift
//  AmakaFlow
//
//  Models for planning/day-state, conflict detection, and week generation APIs (AMA-1147)
//

import Foundation

// MARK: - Day State

/// Represents the training state for a single day.
///
/// AMA-1932: this is the single iOS DayState model. It now decodes the BFF
/// `/v1/planning/days` camelCase contract (`plannedSessions`,
/// `completedSessions`, `readinessScore`, etc.) while keeping the older
/// iOS-facing properties (`plannedWorkouts`, `completedWorkouts`,
/// `fatigueScore`) used by Calendar/Fatigue screens.
struct DayState: Codable, Identifiable {
    let date: String
    let readiness: ReadinessLevel
    let plannedWorkouts: [PlannedWorkout]
    let completedWorkouts: [String]
    let fatigueScore: Double?
    let notes: String?

    // BFF-owned DayState fields (camelCase on the wire).
    let plannedSessions: [PlannedWorkout]
    let completedSessions: [CompletedSession]
    let readinessScore: Int?
    let availableBlocks: [TimeBlock]
    let constraints: [String]
    let goalPhase: String?
    let acuteLoad: Double?
    let chronicLoad: Double?

    var id: String { date }

    init(
        date: String,
        readiness: ReadinessLevel,
        plannedWorkouts: [PlannedWorkout],
        completedWorkouts: [String],
        fatigueScore: Double?,
        notes: String?,
        plannedSessions: [PlannedWorkout]? = nil,
        completedSessions: [CompletedSession] = [],
        readinessScore: Int? = nil,
        availableBlocks: [TimeBlock] = [],
        constraints: [String] = [],
        goalPhase: String? = nil,
        acuteLoad: Double? = nil,
        chronicLoad: Double? = nil
    ) {
        self.date = date
        self.readiness = readiness
        self.plannedWorkouts = plannedWorkouts
        self.completedWorkouts = completedWorkouts
        self.fatigueScore = fatigueScore
        self.notes = notes
        self.plannedSessions = plannedSessions ?? plannedWorkouts
        self.completedSessions = completedSessions
        self.readinessScore = readinessScore
        self.availableBlocks = availableBlocks
        self.constraints = constraints
        self.goalPhase = goalPhase
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case readiness
        case plannedWorkouts
        case completedWorkouts
        case fatigueScore
        case notes
        case plannedSessions
        case completedSessions
        case readinessScore
        case availableBlocks
        case constraints
        case goalPhase
        case acuteLoad
        case chronicLoad
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        date = try container.decode(String.self, forKey: .date)
        readinessScore = try container.decodeIfPresent(Int.self, forKey: .readinessScore)

        let decodedReadiness = try container.decodeIfPresent(ReadinessLevel.self, forKey: .readiness)
        readiness = decodedReadiness ?? Self.readinessLevel(from: readinessScore)

        let bffPlannedSessions = try container.decodeIfPresent([PlannedWorkout].self, forKey: .plannedSessions) ?? []
        let legacyPlannedWorkouts = try container.decodeIfPresent([PlannedWorkout].self, forKey: .plannedWorkouts)
        plannedSessions = bffPlannedSessions
        plannedWorkouts = legacyPlannedWorkouts ?? bffPlannedSessions

        completedSessions = try container.decodeIfPresent([CompletedSession].self, forKey: .completedSessions) ?? []
        let legacyCompletedWorkouts = try container.decodeIfPresent([String].self, forKey: .completedWorkouts)
        completedWorkouts = legacyCompletedWorkouts ?? completedSessions.map(\.id)

        fatigueScore = try container.decodeIfPresent(Double.self, forKey: .fatigueScore)
            ?? readinessScore.map(Double.init)
        constraints = try container.decodeIfPresent([String].self, forKey: .constraints) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
            ?? (constraints.isEmpty ? nil : constraints.joined(separator: ", "))
        availableBlocks = try container.decodeIfPresent([TimeBlock].self, forKey: .availableBlocks) ?? []
        goalPhase = try container.decodeIfPresent(String.self, forKey: .goalPhase)
        acuteLoad = try container.decodeIfPresent(Double.self, forKey: .acuteLoad)
        chronicLoad = try container.decodeIfPresent(Double.self, forKey: .chronicLoad)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(readiness, forKey: .readiness)
        try container.encode(plannedWorkouts, forKey: .plannedWorkouts)
        try container.encode(completedWorkouts, forKey: .completedWorkouts)
        try container.encodeIfPresent(fatigueScore, forKey: .fatigueScore)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(plannedSessions, forKey: .plannedSessions)
        try container.encode(completedSessions, forKey: .completedSessions)
        try container.encodeIfPresent(readinessScore, forKey: .readinessScore)
        try container.encode(availableBlocks, forKey: .availableBlocks)
        try container.encode(constraints, forKey: .constraints)
        try container.encodeIfPresent(goalPhase, forKey: .goalPhase)
        try container.encodeIfPresent(acuteLoad, forKey: .acuteLoad)
        try container.encodeIfPresent(chronicLoad, forKey: .chronicLoad)
    }

    private static func readinessLevel(from score: Int?) -> ReadinessLevel {
        guard let score else { return .unknown }
        switch score {
        case 67...100: return .green
        case 34...66: return .yellow
        case 0...33: return .red
        default: return .unknown
        }
    }
}

enum ReadinessLevel: String, Codable {
    case green
    case yellow
    case red
    case rest
    case unknown
}

struct PlannedWorkout: Codable, Identifiable {
    let id: String
    let name: String
    let sport: String
    let estimatedDurationMinutes: Int?
    let scheduledTime: String?
    let priority: WorkoutPriority?

    init(
        id: String,
        name: String,
        sport: String,
        estimatedDurationMinutes: Int?,
        scheduledTime: String?,
        priority: WorkoutPriority?
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.scheduledTime = scheduledTime
        self.priority = priority
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sport
        case type
        case intensity
        case rationale
        case estimatedDurationMinutes
        case durationMin
        case scheduledTime
        case priority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let decodedSport = try container.decodeIfPresent(String.self, forKey: .sport)
            ?? container.decodeIfPresent(String.self, forKey: .type)
            ?? "other"
        sport = decodedSport

        let intensity = try container.decodeIfPresent(String.self, forKey: .intensity)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .rationale)
            ?? [intensity, decodedSport].compactMap { $0 }.joined(separator: " ").capitalized

        estimatedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedDurationMinutes)
            ?? container.decodeIfPresent(Int.self, forKey: .durationMin)
        scheduledTime = try container.decodeIfPresent(String.self, forKey: .scheduledTime)
        priority = try container.decodeIfPresent(WorkoutPriority.self, forKey: .priority)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sport, forKey: .sport)
        try container.encodeIfPresent(estimatedDurationMinutes, forKey: .estimatedDurationMinutes)
        try container.encodeIfPresent(scheduledTime, forKey: .scheduledTime)
        try container.encodeIfPresent(priority, forKey: .priority)
    }
}

struct CompletedSession: Codable, Identifiable {
    let id: String
    let source: String
    let date: String
    let type: String
    let durationMin: Int
    let actualData: [String: JSONValue]?
}

struct TimeBlock: Codable, Identifiable {
    let start: String
    let end: String
    let label: String?

    var id: String { "\(start)-\(end)" }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

enum WorkoutPriority: String, Codable {
    case key
    case normal
    case optional
}

// MARK: - Week Plan Generation

struct GenerateWeekRequest: Codable {
    let startDate: String?
    let preferences: WeekPreferences?
}

struct WeekPreferences: Codable {
    let maxDaysPerWeek: Int?
    let preferredRestDays: [Int]?
    let longRunDay: Int?
}

struct ProposedPlan: Codable {
    let weekStartDate: String
    let days: [ProposedDay]
    let rationale: String?
    let totalLoadScore: Double?
}

struct ProposedDay: Codable, Identifiable {
    let date: String
    let workouts: [PlannedWorkout]
    let isRestDay: Bool
    let rationale: String?

    var id: String { date }
}

// MARK: - Conflict Detection

struct DetectConflictsRequest: Codable {
    let startDate: String
    let endDate: String
}

struct Conflict: Codable, Identifiable {
    let id: String
    let date: String
    let type: ConflictType
    let description: String
    let severity: ConflictSeverity
    let suggestion: String?
}

enum ConflictType: String, Codable {
    case preFatigue = "pre_fatigue"
    case consecutiveHard = "consecutive_hard"
    case sameMuscleGroup = "same_muscle_group"
    case overload
    case noRecovery = "no_recovery"

    // Legacy mapper-api values kept for backward compatibility with fixtures/tests.
    case backToBack = "back_to_back"
    case missingRecovery = "missing_recovery"
    case intensityClash = "intensity_clash"

    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ConflictSeverity: String, Codable {
    case warning
    case critical

    // Legacy mapper-api values kept for backward compatibility with fixtures/tests.
    case low
    case medium
    case high

    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Parse Workout

struct ParseTextRequest: Codable {
    let text: String
    let source: String?
}

struct ParseTextResult: Codable {
    let success: Bool
    let exercises: [ParsedExercise]
    let detectedFormat: String?
    let confidence: Double
    let source: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case exercises
        case detectedFormat
        case confidence
        case source
    }

    init(
        success: Bool,
        exercises: [ParsedExercise],
        detectedFormat: String?,
        confidence: Double,
        source: String?
    ) {
        self.success = success
        self.exercises = exercises
        self.detectedFormat = detectedFormat
        self.confidence = confidence
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        exercises = try container.decodeIfPresent([ParsedExercise].self, forKey: .exercises) ?? []
        detectedFormat = try container.decodeIfPresent(String.self, forKey: .detectedFormat)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }
}

struct ParsedExercise: Codable {
    let rawName: String
    let sets: Int?
    let reps: String?
    let distance: String?
    let supersetGroup: String?
    let order: Int
    let weight: String?
    let weightUnit: String?
    let rpe: Double?
    let notes: String?
    let restSeconds: Int?

    private enum CodingKeys: String, CodingKey {
        case rawName
        case sets
        case reps
        case distance
        case supersetGroup
        case order
        case weight
        case weightUnit
        case rpe
        case notes
        case restSeconds
    }

    init(
        rawName: String,
        sets: Int? = nil,
        reps: String? = nil,
        distance: String? = nil,
        supersetGroup: String? = nil,
        order: Int,
        weight: String? = nil,
        weightUnit: String? = nil,
        rpe: Double? = nil,
        notes: String? = nil,
        restSeconds: Int? = nil
    ) {
        self.rawName = rawName
        self.sets = sets
        self.reps = reps
        self.distance = distance
        self.supersetGroup = supersetGroup
        self.order = order
        self.weight = weight
        self.weightUnit = weightUnit
        self.rpe = rpe
        self.notes = notes
        self.restSeconds = restSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawName = try container.decodeIfPresent(String.self, forKey: .rawName) ?? ""
        sets = try container.decodeIfPresent(Int.self, forKey: .sets)
        reps = try container.decodeIfPresent(String.self, forKey: .reps)
        distance = try container.decodeIfPresent(String.self, forKey: .distance)
        supersetGroup = try container.decodeIfPresent(String.self, forKey: .supersetGroup)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        weight = try container.decodeIfPresent(String.self, forKey: .weight)
        weightUnit = try container.decodeIfPresent(String.self, forKey: .weightUnit)
        rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
    }
}
