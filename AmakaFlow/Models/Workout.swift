//
//  Workout.swift
//  AmakaFlow
//
//  Data models matching TypeScript implementation
//

import Foundation

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
            let target = try container.decodeIfPresent(String.self, forKey: .target)
            self = .warmup(seconds: seconds, target: target)
            
        case "cooldown":
            let seconds = try container.decode(Int.self, forKey: .seconds)
            let target = try container.decodeIfPresent(String.self, forKey: .target)
            self = .cooldown(seconds: seconds, target: target)
            
        case "time":
            let seconds = try container.decode(Int.self, forKey: .seconds)
            let target = try container.decodeIfPresent(String.self, forKey: .target)
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
            let target = try container.decodeIfPresent(String.self, forKey: .target)
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
    case instagram
    case youtube
    case image
    case ai
    case coach
    case amaka
    case other

    // Handle unknown sources gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = WorkoutSource(rawValue: rawValue) ?? .other
    }
}

// MARK: - Workout Sport Type
enum WorkoutSport: String, Codable {
    case running
    case cycling
    case strength
    case mobility
    case swimming
    case cardio
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Handle alternative values from backend
        switch rawValue.lowercased() {
        case "running", "run":
            self = .running
        case "cycling", "bike", "biking":
            self = .cycling
        case "strength", "strengthtraining", "strength_training", "weights":
            self = .strength
        case "mobility", "yoga", "stretching", "flexibility":
            self = .mobility
        case "swimming", "swim":
            self = .swimming
        case "cardio", "hiit":
            self = .cardio
        default:
            self = .other
        }
    }
}

// MARK: - Workout Model
struct Workout: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let sport: WorkoutSport
    let duration: Int // seconds
    let intervals: [WorkoutInterval]
    let description: String?
    let source: WorkoutSource
    let sourceUrl: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        sport: WorkoutSport,
        duration: Int,
        intervals: [WorkoutInterval] = [],
        description: String? = nil,
        source: WorkoutSource,
        sourceUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.duration = duration
        self.intervals = intervals
        self.description = description
        self.source = source
        self.sourceUrl = sourceUrl
    }

    // Custom decoder to handle missing/null intervals
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sport = try container.decode(WorkoutSport.self, forKey: .sport)
        duration = try container.decode(Int.self, forKey: .duration)
        intervals = try container.decodeIfPresent([WorkoutInterval].self, forKey: .intervals) ?? []
        description = try container.decodeIfPresent(String.self, forKey: .description)
        source = try container.decode(WorkoutSource.self, forKey: .source)
        sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sport, duration, intervals, description, source, sourceUrl
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
