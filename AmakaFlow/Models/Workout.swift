//
//  Workout.swift
//  AmakaFlow
//
// swiftlint:disable file_length

//  Data models matching TypeScript implementation
//

import Foundation

enum CanonicalSource: String, Codable, Equatable, Hashable, Sendable {
    case auto
    case userPick = "user_pick"
    case preset
}

// MARK: - Workout Interval Types
enum WorkoutInterval: Codable, Hashable {
    case warmup(seconds: Int, target: String?)
    case cooldown(seconds: Int, target: String?)
    case time(seconds: Int, target: String?)
    case reps(sets: Int?, reps: Int, name: String, load: String?, restSec: Int?, followAlongUrl: String?)
    case distance(meters: Int, target: String?)
    case `repeat`(reps: Int, intervals: [WorkoutInterval])
    case rest(seconds: Int?)  // nil = manual rest, value = timed rest
    
    enum CodingKeys: String, CodingKey {
        case kind, seconds, target, sets, reps, name, load, restSec, meters, intervals, followAlongUrl
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        
        switch kind {
        case "warmup":
            let seconds = try container.decode(Int.self, forKey: .seconds)
            let target = Self.firstNonEmpty(
                try container.decodeIfPresent(String.self, forKey: .target),
                try container.decodeIfPresent(String.self, forKey: .name)
            )
            self = .warmup(seconds: seconds, target: target)
            
        case "cooldown":
            let seconds = try container.decode(Int.self, forKey: .seconds)
            let target = Self.firstNonEmpty(
                try container.decodeIfPresent(String.self, forKey: .target),
                try container.decodeIfPresent(String.self, forKey: .name)
            )
            self = .cooldown(seconds: seconds, target: target)
            
        case "time":
            let seconds = try container.decode(Int.self, forKey: .seconds)
            // Mapper `/workouts/incoming` sends machine names on `name` with
            // `target: null` for timed steps — prefer whichever is non-empty.
            let target = Self.firstNonEmpty(
                try container.decodeIfPresent(String.self, forKey: .target),
                try container.decodeIfPresent(String.self, forKey: .name)
            )
            self = .time(seconds: seconds, target: target)
            
        case "reps":
            let sets = try container.decodeIfPresent(Int.self, forKey: .sets)
            let reps = try container.decode(Int.self, forKey: .reps)
            let name = try container.decode(String.self, forKey: .name)
            let load = try container.decodeIfPresent(String.self, forKey: .load)
            let restSec = try container.decodeIfPresent(Int.self, forKey: .restSec)
            let followAlongUrl = try container.decodeIfPresent(String.self, forKey: .followAlongUrl)
            self = .reps(sets: sets, reps: reps, name: name, load: load, restSec: restSec, followAlongUrl: followAlongUrl)
            
        case "distance":
            let meters = try container.decode(Int.self, forKey: .meters)
            let target = Self.firstNonEmpty(
                try container.decodeIfPresent(String.self, forKey: .target),
                try container.decodeIfPresent(String.self, forKey: .name)
            )
            self = .distance(meters: meters, target: target)
            
        case "repeat":
            let reps = try container.decode(Int.self, forKey: .reps)
            let intervals = try container.decode([WorkoutInterval].self, forKey: .intervals)
            self = .repeat(reps: reps, intervals: intervals)

        case "rest":
            let seconds = try container.decodeIfPresent(Int.self, forKey: .seconds)
            self = .rest(seconds: seconds)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown interval kind: \(kind)"
            )
        }
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { continue }
            return trimmed
        }
        return nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .warmup(let seconds, let target):
            try container.encode("warmup", forKey: .kind)
            try container.encode(seconds, forKey: .seconds)
            try container.encodeIfPresent(target, forKey: .target)
            
        case .cooldown(let seconds, let target):
            try container.encode("cooldown", forKey: .kind)
            try container.encode(seconds, forKey: .seconds)
            try container.encodeIfPresent(target, forKey: .target)
            
        case .time(let seconds, let target):
            try container.encode("time", forKey: .kind)
            try container.encode(seconds, forKey: .seconds)
            try container.encodeIfPresent(target, forKey: .target)
            
        case .reps(let sets, let reps, let name, let load, let restSec, let followAlongUrl):
            try container.encode("reps", forKey: .kind)
            try container.encodeIfPresent(sets, forKey: .sets)
            try container.encode(reps, forKey: .reps)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(load, forKey: .load)
            try container.encodeIfPresent(restSec, forKey: .restSec)
            try container.encodeIfPresent(followAlongUrl, forKey: .followAlongUrl)
            
        case .distance(let meters, let target):
            try container.encode("distance", forKey: .kind)
            try container.encode(meters, forKey: .meters)
            try container.encodeIfPresent(target, forKey: .target)
            
        case .repeat(let reps, let intervals):
            try container.encode("repeat", forKey: .kind)
            try container.encode(reps, forKey: .reps)
            try container.encode(intervals, forKey: .intervals)

        case .rest(let seconds):
            try container.encode("rest", forKey: .kind)
            try container.encodeIfPresent(seconds, forKey: .seconds)
        }
    }
}

// MARK: - Workout Source
enum WorkoutSource: String, Codable {
    case manual
    case gymManualSync = "gym_manual_sync"
    case smartPlanner = "smart_planner"
    case suggestionAccepted = "suggestion_accepted"
    case trainingProgram = "training_program"
    case template
    case connectedCalendar = "connected_calendar"
    case instagram
    case tiktok
    case garmin
    case runna
    case stryd
    case gymClass = "gym_class"

    // AMA-2285: youtube / image / ai / coach badges; `amaka`/`other` for fixtures.
    case youtube
    case image
    case ai
    case coach
    case friend // AMA-2389 snapshot copy from a friend share
    case amaka
    case other

    // Handle unknown sources gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = WorkoutSource(rawValue: rawValue) ?? .other
    }
}

struct WorkoutSourceProvenance: Equatable {
    let rawValue: String
    let label: String

    static func badge(for source: String?) -> WorkoutSourceProvenance? {
        guard let normalized = normalize(source) else { return nil }
        let labels: [String: String] = [
            "manual": "Manual",
            "gym_manual_sync": "Manual",
            "ai": "AI",
            "coach": "Coach",
            "youtube": "YouTube",
            "image": "Screenshot",
            "smart_planner": "AI Coach",
            "amaka": "AI Coach",
            "suggestion_accepted": "AI Suggestion",
            "training_program": "Program",
            "template": "Program",
            "connected_calendar": "Calendar",
            "instagram": "Instagram",
            "tiktok": "TikTok",
            "garmin": "Garmin",
            "runna": "Runna",
            "stryd": "Stryd",
            "gym_class": "Gym Class", "friend": "Friend"
        ]
        guard let label = labels[normalized] else { return nil }
        return WorkoutSourceProvenance(rawValue: normalized, label: label)
    }

    static func isExternal(_ source: String?) -> Bool {
        guard let normalized = normalize(source) else { return false }
        return ["instagram", "tiktok", "youtube", "image", "garmin", "runna", "stryd"].contains(normalized)
    }

    static func externalLabel(for source: String?) -> String? {
        guard let normalized = normalize(source) else { return nil }
        switch normalized {
        case "instagram": return "Instagram"
        case "tiktok": return "TikTok"
        case "youtube": return "YouTube"
        case "image": return "Screenshot"
        case "garmin": return "Garmin"
        case "runna": return "Runna"
        case "stryd": return "Stryd"
        default: return nil
        }
    }

    static func externalURL(for workout: Workout) -> URL? {
        guard isExternal(workout.source.rawValue),
              let sourceUrl = workout.sourceUrl,
              let url = URL(string: sourceUrl),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else { return nil }
        return url
    }

    static func externalURLString(in payload: [String: WorkoutJSONValue]?) -> String? {
        guard let payload else { return nil }
        for key in ["sourceUrl", "source_url", "externalUrl", "external_url", "externalEventUrl", "external_event_url", "url", "link"] {
            if let value = payload[key]?.stringValue, URL(string: value)?.scheme != nil {
                return value
            }
        }
        return nil
    }

    private static func normalize(_ source: String?) -> String? {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

// MARK: - Workout Sport Type
/// App-level sport label (AMA-2393). Canonical wire values match mapper
/// `WorkoutSport`; aliases decode for older payloads.
enum WorkoutSport: String, Codable, CaseIterable, Identifiable, Hashable {
    case strength
    case conditioning
    case cardio
    case running = "run"
    case cycling = "ride"
    case swimming = "swim"
    case mobility
    case mixed
    case other

    var id: String { rawValue }

    /// Hero / picker label.
    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .conditioning: return "Conditioning"
        case .cardio: return "Cardio"
        case .running: return "Run"
        case .cycling: return "Ride"
        case .swimming: return "Swim"
        case .mobility: return "Mobility"
        case .mixed: return "Mixed"
        case .other: return "Other"
        }
    }

    /// Mono hero pill token.
    var heroPill: String {
        switch self {
        case .strength: return "STRENGTH"
        case .conditioning: return "CONDITIONING"
        case .cardio: return "CARDIO"
        case .running: return "RUN"
        case .cycling: return "RIDE"
        case .swimming: return "SWIM"
        case .mobility: return "MOBILITY"
        case .mixed: return "MIXED"
        case .other: return "WORKOUT"
        }
    }

    /// Choices offered by the editable type chip sheet.
    static var pickerOptions: [WorkoutSport] {
        [.strength, .conditioning, .cardio, .running, .cycling, .swimming, .mobility, .mixed]
    }

    /// AMA-2428 — Watch passive free-capture “What was this?” list order (Strength + Mixed first).
    static var passiveSessionPickerOptions: [WorkoutSport] {
        [.strength, .mixed, .conditioning, .cardio, .running, .cycling, .swimming, .mobility, .other]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self.parse(rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Canonical + legacy wire values. Prefer over `init(rawValue:)` (exact match only).
    static func parse(_ rawValue: String) -> WorkoutSport {
        let token = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch token {
        case "running", "run":
            return .running
        case "cycling", "bike", "biking", "ride":
            return .cycling
        case "strength", "strengthtraining", "traditionalstrengthtraining",
             "functionalstrengthtraining", "weights", "coretraining":
            return .strength
        case "conditioning", "metcon", "hiit", "highintensityintervaltraining":
            return .conditioning
        case "mobility", "yoga", "stretching", "flexibility":
            return .mobility
        case "swimming", "swim":
            return .swimming
        case "cardio", "rowing", "elliptical", "stairclimbing", "walking":
            return .cardio
        case "mixed", "mixedcardio", "swimbikerun":
            return .mixed
        case "other", "hyrox":
            // "hyrox" is a race brand, not a wire sport — fall through to other
            // so the type chip never shows a fake HYROX option.
            return .other
        default:
            return .other
        }
    }
}

// MARK: - Workout Model
struct Workout: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let sport: WorkoutSport
    /// AMA-2393 — `true` when wire `sport` was persisted (type chip / save), not inferred.
    let sportPersisted: Bool?
    let duration: Int // seconds
    let blocks: [Block]
    let description: String?
    let source: WorkoutSource
    let sourceUrl: String?
    /// Creator / coach name from import metadata when available.
    let creatorName: String?
    let createdAt: Date?
    /// Stable workout taxonomy identity, when the backend supplied one.
    let canonicalId: String?
    let canonicalSource: CanonicalSource?

    /// Computed flat interval list for playback (backward-compatible).
    var intervals: [WorkoutInterval] {
        BlockToIntervalConverter.flatten(blocks)
    }

    /// Total number of unique exercises across all blocks.
    var exerciseCount: Int {
        blocks.reduce(0) { $0 + $1.exercises.count }
    }

    /// Number of blocks in this workout.
    var blockCount: Int {
        blocks.count
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        sport: WorkoutSport,
        duration: Int,
        blocks: [Block] = [],
        description: String? = nil,
        source: WorkoutSource,
        sourceUrl: String? = nil,
        creatorName: String? = nil,
        createdAt: Date? = nil,
        canonicalId: String? = nil,
        canonicalSource: CanonicalSource? = nil,
        sportPersisted: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.sportPersisted = sportPersisted
        self.duration = duration
        self.blocks = blocks
        self.description = description
        self.source = source
        self.sourceUrl = sourceUrl
        self.creatorName = creatorName
        self.createdAt = createdAt
        self.canonicalId = canonicalId
        self.canonicalSource = canonicalSource
    }

    /// Legacy convenience init that accepts intervals and wraps them in blocks.
    init(
        id: String = UUID().uuidString,
        name: String,
        sport: WorkoutSport,
        duration: Int,
        intervals: [WorkoutInterval],
        description: String? = nil,
        source: WorkoutSource,
        sourceUrl: String? = nil,
        creatorName: String? = nil,
        createdAt: Date? = nil,
        canonicalId: String? = nil,
        canonicalSource: CanonicalSource? = nil,
        sportPersisted: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.sportPersisted = sportPersisted
        self.duration = duration
        self.blocks = Workout.blocksFromLegacyIntervals(intervals)
        self.description = description
        self.source = source
        self.sourceUrl = sourceUrl
        self.creatorName = creatorName
        self.createdAt = createdAt
        self.canonicalId = canonicalId
        self.canonicalSource = canonicalSource
    }

    // Custom decoder to handle missing/null fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let decoded = try container.decodeIfPresent(WorkoutSport.self, forKey: .sport) {
            sport = decoded
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .workoutType) {
            sport = WorkoutSport.parse(legacy)
        } else {
            sport = .other
        }
        sportPersisted = try container.decodeIfPresent(Bool.self, forKey: .sportPersisted)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        description = try container.decodeIfPresent(String.self, forKey: .description)
        source = try container.decodeIfPresent(WorkoutSource.self, forKey: .source) ?? .other
        sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl)
        creatorName = try container.decodeIfPresent(String.self, forKey: .creatorName)
            ?? (try? container.decodeIfPresent(String.self, forKey: .creator))
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? (try? container.decodeIfPresent(Date.self, forKey: .pushedAt))
        canonicalId = try container.decodeIfPresent(String.self, forKey: .canonicalId)
        canonicalSource = try container.decodeIfPresent(CanonicalSource.self, forKey: .canonicalSource)

        // Try blocks first (new format), fall back to legacy intervals
        if let decodedBlocks = try container.decodeIfPresent([Block].self, forKey: .blocks), !decodedBlocks.isEmpty {
            blocks = decodedBlocks
        } else if let legacyIntervals = try container.decodeIfPresent([WorkoutInterval].self, forKey: .intervals) {
            blocks = Workout.blocksFromLegacyIntervals(legacyIntervals)
        } else {
            blocks = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sport, forKey: .sport)
        try container.encodeIfPresent(sportPersisted, forKey: .sportPersisted)
        try container.encode(duration, forKey: .duration)
        try container.encode(blocks, forKey: .blocks)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(sourceUrl, forKey: .sourceUrl)
        try container.encodeIfPresent(creatorName, forKey: .creatorName)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(canonicalId, forKey: .canonicalId)
        try container.encodeIfPresent(canonicalSource, forKey: .canonicalSource)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sport, duration, blocks, intervals, description, source, sourceUrl
        case creatorName, creator, createdAt, pushedAt
        case canonicalId, canonicalSource
        case workoutType = "workout_type"
        case sportPersisted = "sport_persisted"
    }

    /// Convert legacy flat WorkoutInterval array into Block array.
    /// Groups intervals into separate blocks to preserve warmup/cooldown types and repeat structure.
    static func blocksFromLegacyIntervals(_ intervals: [WorkoutInterval]) -> [Block] {
        guard !intervals.isEmpty else { return [] }

        var blocks: [Block] = []
        var mainExercises: [Exercise] = []

        /// Flush accumulated main exercises into a block.
        func flushMain() {
            guard !mainExercises.isEmpty else { return }
            blocks.append(Block(label: nil, structure: .straight, rounds: 1, exercises: mainExercises))
            mainExercises = []
        }

        for interval in intervals {
            switch interval {
            case .warmup(let seconds, let target):
                flushMain()
                let exercise = Exercise(
                    name: target ?? "Warm Up",
                    canonicalName: nil, sets: nil, reps: nil,
                    durationSeconds: seconds, load: nil, restSeconds: nil,
                    distance: nil, notes: target, supersetGroup: nil
                )
                blocks.append(Block(label: "Warm-up", structure: .straight, rounds: 1, exercises: [exercise]))

            case .cooldown(let seconds, let target):
                flushMain()
                let exercise = Exercise(
                    name: target ?? "Cool Down",
                    canonicalName: nil, sets: nil, reps: nil,
                    durationSeconds: seconds, load: nil, restSeconds: nil,
                    distance: nil, notes: target, supersetGroup: nil
                )
                blocks.append(Block(label: "Cool-down", structure: .straight, rounds: 1, exercises: [exercise]))

            case .time(let seconds, let target):
                mainExercises.append(Exercise(
                    name: target ?? "Timed Work",
                    canonicalName: nil, sets: nil, reps: nil,
                    durationSeconds: seconds, load: nil, restSeconds: nil,
                    distance: nil, notes: target, supersetGroup: nil
                ))

            case .reps(let sets, let reps, let name, let load, let restSec, _):
                let resolved = Workout.resolveLegacyLoadAndInstruction(from: load)
                mainExercises.append(Exercise(
                    name: name,
                    canonicalName: nil, sets: sets, reps: "\(reps)",
                    durationSeconds: nil, load: resolved.load, restSeconds: restSec,
                    distance: nil, notes: resolved.instruction, focus: nil, supersetGroup: nil
                ))

            case .distance(let meters, let target):
                mainExercises.append(Exercise(
                    name: target ?? "Distance",
                    canonicalName: nil, sets: nil, reps: nil,
                    durationSeconds: nil, load: nil, restSeconds: nil,
                    distance: Double(meters), notes: target, supersetGroup: nil
                ))

            case .repeat(let reps, let subIntervals):
                flushMain()
                // AMA-2399: map nested rests onto restSeconds / restBetweenSeconds.
                let packed = Self.exercisesPreservingRests(from: subIntervals, rounds: reps)
                if !packed.exercises.isEmpty {
                    blocks.append(Block(
                        label: nil,
                        structure: .circuit,
                        rounds: reps,
                        exercises: packed.exercises,
                        restBetweenSeconds: packed.restBetweenSeconds
                    ))
                }

            case .rest:
                // Top-level rest is structural (nested rests handled in `.repeat` above).
                break
            }
        }

        flushMain()
        return blocks
    }

    // MARK: - Legacy conversion helpers

    /// Convert a single legacy interval into an Exercise (used for repeat sub-intervals).
    private static func exerciseFromLegacyInterval(_ interval: WorkoutInterval) -> Exercise? {
        switch interval {
        case .reps(let sets, let r, let name, let load, let restSec, _):
            let resolved = resolveLegacyLoadAndInstruction(from: load)
            return Exercise(name: name, canonicalName: nil, sets: sets, reps: "\(r)",
                            durationSeconds: nil, load: resolved.load, restSeconds: restSec,
                            distance: nil, notes: resolved.instruction, focus: nil, supersetGroup: nil)
        case .time(let seconds, let target):
            return Exercise(name: target ?? "Timed Work", canonicalName: nil, sets: nil, reps: nil,
                            durationSeconds: seconds, load: nil, restSeconds: nil,
                            distance: nil, notes: target, supersetGroup: nil)
        case .distance(let meters, let target):
            return Exercise(name: target ?? "Distance", canonicalName: nil, sets: nil, reps: nil,
                            durationSeconds: nil, load: nil, restSeconds: nil,
                            distance: Double(meters), notes: target, supersetGroup: nil)
        case .rest:
            // Handled by exercisesPreservingRests — not an exercise row.
            return nil
        default:
            return nil
        }
    }

    /// Split a legacy interval `load` field into numeric load vs free-text instruction.
    static func resolveLegacyLoadAndInstruction(from loadString: String?) -> (load: ExerciseLoad?, instruction: String?) {
        guard let loadString else { return (nil, nil) }
        let trimmed = loadString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        let parsed = parseLegacyLoad(trimmed)
        if parsed.value > 0, isRecognizedLoadUnit(parsed.unit) {
            return (parsed, nil)
        }
        return (nil, trimmed)
    }

    private static let recognizedLoadUnits: Set<String> = [
        "kg", "kgs", "kilogram", "kilograms", "lb", "lbs", "lbm", "pound", "pounds",
        "%", "bw", "bodyweight", "plate", "plates"
    ]

    static func isRecognizedLoadUnit(_ unit: String) -> Bool {
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if recognizedLoadUnits.contains(normalized) { return true }
        return recognizedLoadUnits.contains { normalized.hasSuffix($0) }
    }

    /// Parse a legacy load string like "80kg" or "135lbs" into an ExerciseLoad.
    /// Falls back to value 0 with the original string as unit if unparseable.
    static func parseLegacyLoad(_ loadString: String) -> ExerciseLoad {
        // Match a leading number (int or decimal) followed by a unit suffix
        let pattern = #"^(\d+(?:\.\d+)?)\s*(.+)$"#
        if let match = loadString.range(of: pattern, options: .regularExpression) {
            let str = String(loadString[match])
            // Extract numeric and unit parts
            let scanner = Scanner(string: str)
            if let value = scanner.scanDouble() {
                let unit = str[str.index(str.startIndex, offsetBy: scanner.currentIndex.utf16Offset(in: str))...]
                    .trimmingCharacters(in: .whitespaces)
                if !unit.isEmpty {
                    return ExerciseLoad(value: value, unit: unit)
                }
                return ExerciseLoad(value: value, unit: "")
            }
        }
        // Unparseable — store original string as unit, value 0
        return ExerciseLoad(value: 0, unit: loadString)
    }
}

// MARK: - Legacy repeat rest packing (AMA-2399)
extension Workout {
    /// Pack repeat children into exercises, attaching `.rest` to the preceding
    /// work interval. For multi-round repeats, the trailing rest becomes
    /// `restBetweenSeconds` so flatten emits it at the end of each round.
    fileprivate static func exercisesPreservingRests(
        from subIntervals: [WorkoutInterval],
        rounds: Int
    ) -> (exercises: [Exercise], restBetweenSeconds: Int?) {
        var exercises: [Exercise] = []
        for interval in subIntervals {
            switch interval {
            case .rest(let seconds):
                guard !exercises.isEmpty else { continue }
                let lastIndex = exercises.count - 1
                if exercises[lastIndex].restSeconds == nil {
                    exercises[lastIndex] = copyExercise(exercises[lastIndex], restSeconds: seconds)
                }
            default:
                if let mapped = exerciseFromLegacyInterval(interval) {
                    exercises.append(mapped)
                }
            }
        }

        var restBetween: Int?
        // Multi-round circuits restore end-of-round rest via restBetweenSeconds
        // (flatten does not emit the last exercise's restSeconds).
        if rounds > 1, let lastIndex = exercises.indices.last, let trailing = exercises[lastIndex].restSeconds {
            restBetween = trailing
            exercises[lastIndex] = copyExercise(exercises[lastIndex], restSeconds: nil)
        }
        return (exercises, restBetween)
    }

    private static func copyExercise(_ base: Exercise, restSeconds: Int?) -> Exercise {
        Exercise(
            name: base.name,
            canonicalName: base.canonicalName,
            sets: base.sets,
            reps: base.reps,
            durationSeconds: base.durationSeconds,
            load: base.load,
            restSeconds: restSeconds,
            distance: base.distance,
            notes: base.notes,
            focus: base.focus,
            supersetGroup: base.supersetGroup
        )
    }
}

// MARK: - Scheduled Workout Model
struct ScheduledWorkout: Identifiable, Codable, Hashable {
    let workout: Workout
    let scheduledDate: Date?
    let scheduledTime: String?
    let isRecurring: Bool
    let recurrenceDays: [Int]? // 0 = Sunday, 6 = Saturday
    let recurrenceWeeks: Int? // nil = indefinite
    let syncedToApple: Bool
    
    var id: String { workout.id }
    
    init(
        workout: Workout,
        scheduledDate: Date? = nil,
        scheduledTime: String? = nil,
        isRecurring: Bool = false,
        recurrenceDays: [Int]? = nil,
        recurrenceWeeks: Int? = nil,
        syncedToApple: Bool = false
    ) {
        self.workout = workout
        self.scheduledDate = scheduledDate
        self.scheduledTime = scheduledTime
        self.isRecurring = isRecurring
        self.recurrenceDays = recurrenceDays
        self.recurrenceWeeks = recurrenceWeeks
        self.syncedToApple = syncedToApple
    }

    init(plannedWorkout: PlannedWorkoutDTO) {
        self.workout = Workout(plannedWorkout: plannedWorkout)
        self.scheduledDate = Self.parsePlannedDate(plannedWorkout.date)
        self.scheduledTime = plannedWorkout.startTime.map { String($0.prefix(5)) }
        self.isRecurring = false
        self.recurrenceDays = nil
        self.recurrenceWeeks = nil
        self.syncedToApple = false
    }

    private static func parsePlannedDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        if let day = formatter.date(from: value) { return day }
        return ISO8601DateFormatter().date(from: value)
    }
}

struct PlannedWorkoutListDTO: Decodable {
    let workouts: [PlannedWorkoutDTO]
}

struct PlannedWorkoutDTO: Decodable, Equatable {
    let id: String
    let userId: String?
    let title: String?
    let date: String?
    let startTime: String?
    let endTime: String?
    let status: String?
    let source: String?
    let jsonPayload: [String: WorkoutJSONValue]?
    let clientGeneratedId: String?
    let serverVersion: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case title
        case date
        case startTime
        case endTime
        case status
        case source
        case jsonPayload
        case clientGeneratedId
        case serverVersion
    }
}

private extension Workout {
    init(plannedWorkout: PlannedWorkoutDTO) {
        let payloadWorkout = plannedWorkout.decodedPayloadWorkout
        let payload = plannedWorkout.jsonPayload
        let rawSource = plannedWorkout.source
        let source = rawSource.flatMap(WorkoutSource.init(rawValue:)) ?? payloadWorkout?.source ?? .other
        let sourceUrl = WorkoutSourceProvenance.externalURLString(in: payload) ?? payloadWorkout?.sourceUrl
        let sport = payloadWorkout?.sport ?? Self.sport(from: payload?.firstString(for: ["sport", "type", "workoutType", "workout_type"]))
        let decodedDuration = payloadWorkout?.duration
        let duration = (decodedDuration ?? 0) > 0 ? decodedDuration! : Self.durationSeconds(from: payload)

        self.init(
            id: plannedWorkout.id,
            name: payloadWorkout?.name
                ?? payload?.firstString(for: ["name", "title"])
                ?? plannedWorkout.title
                ?? "Planned workout",
            sport: sport,
            duration: duration,
            blocks: payloadWorkout?.blocks ?? [],
            description: payloadWorkout?.description ?? payload?.firstString(for: ["description", "summary"]),
            source: source,
            sourceUrl: sourceUrl
        )
    }

    private static func sport(from rawValue: String?) -> WorkoutSport {
        guard let rawValue,
              let data = try? JSONEncoder().encode(rawValue),
              let sport = try? JSONDecoder().decode(WorkoutSport.self, from: data)
        else { return .other }
        return sport
    }

    private static func durationSeconds(from payload: [String: WorkoutJSONValue]?) -> Int {
        if let seconds = payload?.firstInt(for: ["duration", "durationSeconds", "duration_seconds"]) {
            return seconds
        }
        if let minutes = payload?.firstInt(for: ["estimatedDurationMinutes", "estimated_duration_minutes", "durationMin", "duration_min"]) {
            return minutes * 60
        }
        return 0
    }
}

private extension PlannedWorkoutDTO {
    var decodedPayloadWorkout: Workout? {
        guard let jsonPayload,
              let data = try? JSONEncoder().encode(jsonPayload)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Workout.self, from: data)
    }
}

enum WorkoutJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: WorkoutJSONValue])
    case array([WorkoutJSONValue])
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
        } else if let value = try? container.decode([String: WorkoutJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([WorkoutJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported workout JSON value")
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

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }
}

private extension [String: WorkoutJSONValue] {
    func firstString(for keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func firstInt(for keys: [String]) -> Int? {
        for key in keys {
            if let value = self[key]?.intValue {
                return value
            }
        }
        return nil
    }
}

// MARK: - Workout Helpers
extension Workout {
    var formattedDuration: String {
        WorkoutHelpers.formatDuration(seconds: duration)
    }
    
    var intervalCount: Int {
        WorkoutHelpers.countIntervals(intervals)
    }
}

struct WorkoutHelpers {
    static func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    static func countIntervals(_ intervals: [WorkoutInterval]) -> Int {
        var count = 0
        for interval in intervals {
            switch interval {
            case .repeat(let reps, let subIntervals):
                count += reps * countIntervals(subIntervals)
            default:
                count += 1
            }
        }
        return count
    }
    
    static func formatDistance(meters: Int) -> String {
        if meters >= 1000 {
            let km = Double(meters) / 1000.0
            return String(format: "%.1f km", km)
        } else {
            return "\(meters)m"
        }
    }
}
