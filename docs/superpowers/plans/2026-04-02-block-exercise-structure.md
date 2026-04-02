# AMA-1409: Block/Exercise/Superset Structure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Block/Exercise/Superset data model to iOS app and render workouts hierarchically instead of as flat intervals.

**Architecture:** Approach C — Blocks are the primary stored model, intervals are a computed property derived from blocks via `BlockToIntervalConverter`. The backend API is updated to include raw `blocks` in the `/workouts/incoming` response. Legacy workouts without blocks are wrapped in a single block for backward compatibility.

**Tech Stack:** Swift, SwiftUI, Codable, XCTest

**Spec:** `docs/superpowers/specs/2026-04-02-block-exercise-structure-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `AmakaFlow/Models/Block.swift` | Block and BlockStructure types |
| `AmakaFlow/Models/Exercise.swift` | Exercise and ExerciseLoad types |
| `AmakaFlow/Services/BlockToIntervalConverter.swift` | Converts blocks → flat WorkoutInterval array |
| `AmakaFlow/Views/Components/BlockSectionView.swift` | Renders a block header + exercises |
| `AmakaFlow/Views/Components/ExerciseRowView.swift` | Renders a single exercise within a block |
| `AmakaFlowCompanionTests/BlockToIntervalConverterTests.swift` | Unit tests for converter |
| `AmakaFlowCompanionTests/WorkoutCodableTests.swift` | Unit tests for Codable decode/encode |

### Modified Files
| File | Change |
|------|--------|
| `AmakaFlow/Models/Workout.swift` | Replace stored `intervals` with stored `blocks`, add computed `intervals` |
| `AmakaFlow/Views/WorkoutDetailView.swift` | Replace flat interval list with block section rendering |
| `AmakaFlow/Views/Components/WorkoutCard.swift` | Show exercise/block count from blocks |
| Backend: `services/mapper-api/api/routers/workouts.py` | Add `blocks` field to /workouts/incoming response |

---

## Task 1: Create Exercise Model

**Files:**
- Create: `AmakaFlow/Models/Exercise.swift`

- [ ] **Step 1: Create Exercise.swift with ExerciseLoad and Exercise structs**

```swift
// AmakaFlow/Models/Exercise.swift

import Foundation

struct ExerciseLoad: Codable, Hashable {
    let value: Double
    let unit: String // "kg", "lbs", "bodyweight"
}

struct Exercise: Codable, Hashable, Identifiable {
    let name: String
    let canonicalName: String?
    let sets: Int?
    let reps: String? // Supports ranges like "8-10"
    let durationSeconds: Int?
    let load: ExerciseLoad?
    let restSeconds: Int?
    let distance: Double?
    let notes: String?
    let supersetGroup: Int?

    var id: String { "\(name)-\(sets ?? 0)-\(reps ?? "")" }

    enum CodingKeys: String, CodingKey {
        case name
        case canonicalName = "canonical_name"
        case sets
        case reps
        case durationSeconds = "duration_seconds"
        case load
        case restSeconds = "rest_seconds"
        case distance
        case notes
        case supersetGroup = "superset_group"
    }

    /// Formatted display string: "3x10" or "3x8-10" or "60 sec" or "500m"
    var formattedDetail: String {
        if let sets = sets, let reps = reps {
            return "\(sets)x\(reps)"
        } else if let reps = reps {
            return "\(reps) reps"
        } else if let duration = durationSeconds {
            if duration >= 60 {
                return "\(duration / 60) min"
            }
            return "\(duration) sec"
        } else if let distance = distance {
            if distance >= 1000 {
                return String(format: "%.1f km", distance / 1000)
            }
            return "\(Int(distance))m"
        }
        return ""
    }

    /// Formatted load string: "@ 100kg"
    var formattedLoad: String? {
        guard let load = load else { return nil }
        if load.unit == "bodyweight" { return "BW" }
        return "@ \(load.value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(load.value)) : String(load.value))\(load.unit)"
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app/AmakaFlowCompanion && xcodebuild -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build 2>&1 | tail -5`

Expected: Build succeeds (warnings OK, no errors)

- [ ] **Step 3: Commit**

```bash
cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Models/Exercise.swift
git commit -m "feat(AMA-1409): Add Exercise and ExerciseLoad models"
```

---

## Task 2: Create Block Model

**Files:**
- Create: `AmakaFlow/Models/Block.swift`

- [ ] **Step 1: Create Block.swift with BlockStructure enum and Block struct**

```swift
// AmakaFlow/Models/Block.swift

import Foundation

enum BlockStructure: String, Codable, CaseIterable {
    case straight
    case superset
    case circuit
    case amrap
    case emom
    case tabata

    var displayName: String {
        switch self {
        case .straight: return "Straight"
        case .superset: return "Superset"
        case .circuit: return "Circuit"
        case .amrap: return "AMRAP"
        case .emom: return "EMOM"
        case .tabata: return "Tabata"
        }
    }
}

struct Block: Codable, Hashable, Identifiable {
    let label: String?
    let structure: BlockStructure
    let rounds: Int
    let exercises: [Exercise]
    let restBetweenSeconds: Int?

    var id: String { label ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case label
        case structure
        case rounds
        case exercises
        case restBetweenSeconds = "rest_between_sec"
        // Also handle "rest_between_seconds" from some API responses
    }

    init(label: String?, structure: BlockStructure = .straight, rounds: Int = 1, exercises: [Exercise], restBetweenSeconds: Int? = nil) {
        self.label = label
        self.structure = structure
        self.rounds = rounds
        self.exercises = exercises
        self.restBetweenSeconds = restBetweenSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        // Structure may come as string or be missing (default to straight)
        structure = try container.decodeIfPresent(BlockStructure.self, forKey: .structure) ?? .straight
        rounds = try container.decodeIfPresent(Int.self, forKey: .rounds) ?? 1
        exercises = try container.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
        restBetweenSeconds = try container.decodeIfPresent(Int.self, forKey: .restBetweenSeconds)
    }

    /// Total exercise count in this block
    var exerciseCount: Int { exercises.count }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app/AmakaFlowCompanion && xcodebuild -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build 2>&1 | tail -5`

Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Models/Block.swift
git commit -m "feat(AMA-1409): Add Block and BlockStructure models"
```

---

## Task 3: Create BlockToIntervalConverter

**Files:**
- Create: `AmakaFlow/Services/BlockToIntervalConverter.swift`

- [ ] **Step 1: Create the converter**

```swift
// AmakaFlow/Services/BlockToIntervalConverter.swift

import Foundation

/// Converts Block/Exercise hierarchy to flat WorkoutInterval array.
/// Used by Workout.intervals computed property to maintain compatibility
/// with WorkoutKit, Apple Watch, and the workout player.
enum BlockToIntervalConverter {

    /// Flatten an array of blocks into a flat interval array for playback.
    static func flatten(_ blocks: [Block]) -> [WorkoutInterval] {
        var intervals: [WorkoutInterval] = []

        for block in blocks {
            let blockIntervals = convertBlock(block)
            intervals.append(contentsOf: blockIntervals)
        }

        return intervals
    }

    private static func convertBlock(_ block: Block) -> [WorkoutInterval] {
        // Determine if this is a warmup/cooldown block by label
        let labelLower = (block.label ?? "").lowercased()
        let isWarmup = labelLower.contains("warm")
        let isCooldown = labelLower.contains("cool")

        var exerciseIntervals: [WorkoutInterval] = []

        for (index, exercise) in block.exercises.enumerated() {
            let interval = convertExercise(exercise, isWarmup: isWarmup, isCooldown: isCooldown)
            exerciseIntervals.append(interval)

            // Add rest between exercises (not after the last one)
            if index < block.exercises.count - 1 {
                if let restSec = exercise.restSeconds ?? block.restBetweenSeconds {
                    exerciseIntervals.append(.rest(seconds: restSec))
                }
            }
        }

        // Wrap in repeat if block has multiple rounds
        switch block.structure {
        case .superset, .circuit:
            if block.rounds > 1 {
                return [.repeat(reps: block.rounds, intervals: exerciseIntervals)]
            }
            return exerciseIntervals

        case .amrap, .emom:
            // For time-capped formats, wrap exercises in a repeat
            // The time cap is handled at the player level
            if block.rounds > 1 {
                return [.repeat(reps: block.rounds, intervals: exerciseIntervals)]
            }
            return exerciseIntervals

        case .straight, .tabata:
            return exerciseIntervals
        }
    }

    private static func convertExercise(_ exercise: Exercise, isWarmup: Bool, isCooldown: Bool) -> WorkoutInterval {
        // Duration-based exercises
        if let duration = exercise.durationSeconds {
            if isWarmup {
                return .warmup(seconds: duration, target: exercise.name)
            }
            if isCooldown {
                return .cooldown(seconds: duration, target: exercise.name)
            }
            return .time(seconds: duration, target: exercise.name)
        }

        // Distance-based exercises
        if let distance = exercise.distance {
            return .distance(meters: Int(distance), target: exercise.name)
        }

        // Rep-based exercises (default)
        let repsInt = parseReps(exercise.reps)
        let loadStr = exercise.load.map { load in
            if load.unit == "bodyweight" { return "BW" }
            return "\(load.value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(load.value)) : String(load.value)) \(load.unit)"
        }

        if isWarmup {
            return .warmup(seconds: repsInt * 3, target: exercise.name) // Estimate 3s per rep for warmup
        }

        return .reps(
            sets: exercise.sets,
            reps: repsInt,
            name: exercise.name,
            load: loadStr,
            restSec: exercise.restSeconds,
            followAlongUrl: nil
        )
    }

    /// Parse reps string like "10" or "8-10" to an Int (uses the higher end of range)
    private static func parseReps(_ reps: String?) -> Int {
        guard let reps = reps else { return 1 }
        // Handle range format "8-10" → take higher end
        if reps.contains("-") {
            let parts = reps.split(separator: "-")
            if let last = parts.last, let value = Int(last) {
                return value
            }
        }
        return Int(reps) ?? 1
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app/AmakaFlowCompanion && xcodebuild -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build 2>&1 | tail -5`

Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Services/BlockToIntervalConverter.swift
git commit -m "feat(AMA-1409): Add BlockToIntervalConverter for blocks→intervals"
```

---

## Task 4: Update Workout Model

**Files:**
- Modify: `AmakaFlow/Models/Workout.swift:174-220`

- [ ] **Step 1: Update Workout struct to use blocks as primary, intervals as computed**

Replace the Workout struct (lines 174-220) with:

```swift
struct Workout: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let sport: WorkoutSport
    let duration: Int // seconds
    let blocks: [Block] // PRIMARY — stored
    let description: String?
    let source: WorkoutSource
    let sourceUrl: String?

    /// COMPUTED — derived from blocks, never stored.
    /// Used by WorkoutPlayer, WorkoutKitConverter, and Apple Watch sync.
    var intervals: [WorkoutInterval] {
        BlockToIntervalConverter.flatten(blocks)
    }

    /// Total exercise count across all blocks
    var exerciseCount: Int {
        blocks.reduce(0) { $0 + $1.exerciseCount }
    }

    /// Number of blocks in this workout
    var blockCount: Int {
        blocks.count
    }

    /// Formatted duration string
    var formattedDuration: String {
        if duration >= 3600 {
            return "\(duration / 3600)h \((duration % 3600) / 60)m"
        }
        return "\(duration / 60)m"
    }

    /// Number of intervals (for backward compat with existing UI)
    var intervalCount: Int {
        intervals.count
    }

    init(
        id: String,
        name: String,
        sport: WorkoutSport = .other,
        duration: Int = 0,
        blocks: [Block] = [],
        description: String? = nil,
        source: WorkoutSource = .other,
        sourceUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.duration = duration
        self.blocks = blocks
        self.description = description
        self.source = source
        self.sourceUrl = sourceUrl
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sport, duration, blocks, description, source, sourceUrl
        case intervals // For legacy decoding only
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sport = try container.decodeIfPresent(WorkoutSport.self, forKey: .sport) ?? .other
        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        description = try container.decodeIfPresent(String.self, forKey: .description)
        source = try container.decodeIfPresent(WorkoutSource.self, forKey: .source) ?? .other
        sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl)

        // Try blocks first (new format), fall back to intervals (legacy)
        if let decodedBlocks = try container.decodeIfPresent([Block].self, forKey: .blocks),
           !decodedBlocks.isEmpty {
            blocks = decodedBlocks
        } else if let legacyIntervals = try container.decodeIfPresent([WorkoutInterval].self, forKey: .intervals),
                  !legacyIntervals.isEmpty {
            // Wrap legacy intervals in a single block
            blocks = [Block(label: nil, structure: .straight, exercises: [], restBetweenSeconds: nil)]
            // Store the raw intervals as a fallback — we'll handle this via a stored property
            // Actually: we can't compute intervals from an empty block. Use a different approach.
            // Store legacy intervals directly by creating exercises from them.
            blocks = Self.blocksFromLegacyIntervals(legacyIntervals)
        } else {
            blocks = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sport, forKey: .sport)
        try container.encode(duration, forKey: .duration)
        try container.encode(blocks, forKey: .blocks)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(sourceUrl, forKey: .sourceUrl)
    }

    /// Convert legacy WorkoutInterval array into blocks for backward compat
    private static func blocksFromLegacyIntervals(_ intervals: [WorkoutInterval]) -> [Block] {
        var exercises: [Exercise] = []
        for interval in intervals {
            switch interval {
            case .reps(let sets, let reps, let name, let load, let restSec, _):
                exercises.append(Exercise(
                    name: name, canonicalName: nil, sets: sets,
                    reps: String(reps), durationSeconds: nil,
                    load: nil, restSeconds: restSec,
                    distance: nil, notes: nil, supersetGroup: nil
                ))
            case .time(let seconds, let target):
                exercises.append(Exercise(
                    name: target ?? "Timed Exercise", canonicalName: nil, sets: nil,
                    reps: nil, durationSeconds: seconds,
                    load: nil, restSeconds: nil,
                    distance: nil, notes: nil, supersetGroup: nil
                ))
            case .warmup(let seconds, let target):
                exercises.append(Exercise(
                    name: target ?? "Warm-up", canonicalName: nil, sets: nil,
                    reps: nil, durationSeconds: seconds,
                    load: nil, restSeconds: nil,
                    distance: nil, notes: nil, supersetGroup: nil
                ))
            case .cooldown(let seconds, let target):
                exercises.append(Exercise(
                    name: target ?? "Cool-down", canonicalName: nil, sets: nil,
                    reps: nil, durationSeconds: seconds,
                    load: nil, restSeconds: nil,
                    distance: nil, notes: nil, supersetGroup: nil
                ))
            case .distance(let meters, let target):
                exercises.append(Exercise(
                    name: target ?? "Distance", canonicalName: nil, sets: nil,
                    reps: nil, durationSeconds: nil,
                    load: nil, restSeconds: nil,
                    distance: Double(meters), notes: nil, supersetGroup: nil
                ))
            case .repeat(_, let nestedIntervals):
                // Recursively flatten nested intervals
                let nestedBlocks = blocksFromLegacyIntervals(nestedIntervals)
                for block in nestedBlocks {
                    exercises.append(contentsOf: block.exercises)
                }
            case .rest:
                break // Skip rest intervals — they're structural, not exercises
            }
        }
        guard !exercises.isEmpty else { return [] }
        return [Block(label: nil, structure: .straight, exercises: exercises)]
    }
}
```

- [ ] **Step 2: Fix any compilation errors from callers**

Search for direct references to `Workout(... intervals: ...)` in the codebase and update them to use `blocks:` instead. Key places to check:
- `APIService.swift` — fixture/mock workout creation
- `WorkoutCard.swift` — may reference `workout.intervals.count`
- Test fixtures

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app/AmakaFlowCompanion && xcodebuild -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build 2>&1 | tail -5`

Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Models/Workout.swift
git add -A # catch any callers that needed updating
git commit -m "feat(AMA-1409): Update Workout model — blocks primary, intervals computed"
```

---

## Task 5: Create BlockSectionView and ExerciseRowView

**Files:**
- Create: `AmakaFlow/Views/Components/BlockSectionView.swift`
- Create: `AmakaFlow/Views/Components/ExerciseRowView.swift`

- [ ] **Step 1: Create ExerciseRowView**

```swift
// AmakaFlow/Views/Components/ExerciseRowView.swift

import SwiftUI

struct ExerciseRowView: View {
    let exercise: Exercise
    let index: Int
    let showSupersetIndicator: Bool

    init(exercise: Exercise, index: Int, showSupersetIndicator: Bool = false) {
        self.exercise = exercise
        self.index = index
        self.showSupersetIndicator = showSupersetIndicator
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showSupersetIndicator {
                Rectangle()
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                if let rest = exercise.restSeconds, rest > 0 {
                    Text("\(rest)s rest")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(exercise.formattedDetail)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.cyan)

                if let loadStr = exercise.formattedLoad {
                    Text(loadStr)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 2: Create BlockSectionView**

```swift
// AmakaFlow/Views/Components/BlockSectionView.swift

import SwiftUI

struct BlockSectionView: View {
    let block: Block
    let blockIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Block header
            HStack(spacing: 8) {
                if let label = block.label {
                    Text(label)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Text(block.structure.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.2))
                    .foregroundColor(badgeColor)
                    .clipShape(Capsule())

                if block.rounds > 1 {
                    Text("\(block.rounds) \(block.structure == .straight ? "sets" : "rounds")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6).opacity(0.5))

            // Exercises
            let isSuperset = block.structure == .superset
            ForEach(Array(block.exercises.enumerated()), id: \.offset) { index, exercise in
                ExerciseRowView(
                    exercise: exercise,
                    index: index,
                    showSupersetIndicator: isSuperset
                )

                if index < block.exercises.count - 1 {
                    Divider()
                        .padding(.leading, isSuperset ? 27 : 12)
                }
            }

            // Rest between rounds
            if let rest = block.restBetweenSeconds, rest > 0, block.rounds > 1 {
                HStack {
                    Spacer()
                    Text("\(rest)s rest between \(block.structure == .straight ? "sets" : "rounds")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    private var badgeColor: Color {
        switch block.structure {
        case .straight: return .green
        case .superset: return .blue
        case .circuit: return .orange
        case .amrap: return .red
        case .emom: return .purple
        case .tabata: return .pink
        }
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app/AmakaFlowCompanion && xcodebuild -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build 2>&1 | tail -5`

Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Views/Components/BlockSectionView.swift AmakaFlow/Views/Components/ExerciseRowView.swift
git commit -m "feat(AMA-1409): Add BlockSectionView and ExerciseRowView components"
```

---

## Task 6: Update WorkoutDetailView

**Files:**
- Modify: `AmakaFlow/Views/WorkoutDetailView.swift:34-66`

- [ ] **Step 1: Replace the interval list with block sections**

In WorkoutDetailView.swift, find the "Step-by-Step Breakdown" section (around lines 34-66) and replace it with:

```swift
// Block-by-Block Structure
Section {
    if workout.blocks.isEmpty {
        Text("No workout structure available")
            .foregroundColor(.secondary)
            .italic()
    } else {
        VStack(spacing: 12) {
            ForEach(Array(workout.blocks.enumerated()), id: \.offset) { index, block in
                BlockSectionView(block: block, blockIndex: index)
            }
        }
        .padding(.vertical, 4)
    }
} header: {
    HStack {
        Text("Workout Structure")
            .font(.headline)
        Spacer()
        Text("\(workout.exerciseCount) exercises")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

- [ ] **Step 2: Update the header stats**

Find where `workout.intervalCount` or `workout.intervals.count` is referenced in the header area and update to use `workout.exerciseCount` and `workout.blockCount` where appropriate.

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app/AmakaFlowCompanion && xcodebuild -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build 2>&1 | tail -5`

Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app
git add AmakaFlow/Views/WorkoutDetailView.swift
git commit -m "feat(AMA-1409): Update WorkoutDetailView to render block structure"
```

---

## Task 7: Update Backend API to Include Blocks

**Files:**
- Modify: `services/mapper-api/api/routers/workouts.py:540-550` (the transformed.append dict)

- [ ] **Step 1: Add blocks to the /workouts/incoming response**

In `/Users/davidmini/amakaflow-backend/services/mapper-api/api/routers/workouts.py`, find the `transformed.append({...})` call inside the `/workouts/incoming` endpoint (around line 540) and add the `blocks` field:

```python
        transformed.append({
            "id": workout_record.get("id"),
            "name": title,
            "sport": sport,
            "duration": total_duration,
            "source": "amakaflow",
            "sourceUrl": None,
            "blocks": workout_data.get("blocks", []),  # NEW — raw blocks for iOS
            "intervals": intervals,  # KEEP — for old iOS versions
            "pushedAt": workout_record.get("ios_companion_synced_at"),
            "createdAt": workout_record.get("created_at"),
        })
```

- [ ] **Step 2: Also update /sync/pending endpoint if it exists**

Check `api/routers/sync.py` for the `/sync/pending` endpoint that also returns workouts to iOS. Add `blocks` there too using the same pattern.

- [ ] **Step 3: Run backend tests to verify no regressions**

Run: `cd /Users/davidmini/amakaflow-backend/services/mapper-api && docker run --rm -v "$(pwd):/app" -w /app python:3.11-slim sh -c "apt-get update -qq && apt-get install -y -qq git >/dev/null 2>&1 && pip install --no-cache-dir -q -r requirements.txt -r requirements-dev.txt 2>&1 >/dev/null && python -m pytest tests/ -m 'not e2e' --tb=short -q 2>&1 | tail -5"`

Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
cd /Users/davidmini/amakaflow-backend
git checkout -b feat/AMA-1409-blocks-in-api-response
git add services/mapper-api/api/routers/workouts.py services/mapper-api/api/routers/sync.py
git commit -m "feat(AMA-1409): Include raw blocks in /workouts/incoming response for iOS"
```

---

## Task 8: Unit Tests

**Files:**
- Create: `AmakaFlowCompanionTests/BlockToIntervalConverterTests.swift`
- Create: `AmakaFlowCompanionTests/WorkoutCodableTests.swift`

- [ ] **Step 1: Create BlockToIntervalConverterTests**

```swift
// AmakaFlowCompanionTests/BlockToIntervalConverterTests.swift

import XCTest
@testable import AmakaFlowCompanion

final class BlockToIntervalConverterTests: XCTestCase {

    func testStraightBlockProducesSequentialIntervals() {
        let block = Block(
            label: "Main",
            structure: .straight,
            exercises: [
                Exercise(name: "Squat", canonicalName: nil, sets: 3, reps: "10", durationSeconds: nil, load: nil, restSeconds: 60, distance: nil, notes: nil, supersetGroup: nil),
                Exercise(name: "Bench Press", canonicalName: nil, sets: 3, reps: "10", durationSeconds: nil, load: nil, restSeconds: 60, distance: nil, notes: nil, supersetGroup: nil),
            ]
        )

        let intervals = BlockToIntervalConverter.flatten([block])

        // Should produce: reps, rest, reps (no rest after last exercise)
        XCTAssertEqual(intervals.count, 3)
        if case .reps(_, let reps, let name, _, _, _) = intervals[0] {
            XCTAssertEqual(name, "Squat")
            XCTAssertEqual(reps, 10)
        } else { XCTFail("Expected reps interval") }

        if case .rest(let seconds) = intervals[1] {
            XCTAssertEqual(seconds, 60)
        } else { XCTFail("Expected rest interval") }
    }

    func testTimedExerciseProducesTimeInterval() {
        let block = Block(
            label: "Cooldown",
            structure: .straight,
            exercises: [
                Exercise(name: "Stretch", canonicalName: nil, sets: nil, reps: nil, durationSeconds: 300, load: nil, restSeconds: nil, distance: nil, notes: nil, supersetGroup: nil),
            ]
        )

        let intervals = BlockToIntervalConverter.flatten([block])
        XCTAssertEqual(intervals.count, 1)
        if case .cooldown(let seconds, let target) = intervals[0] {
            XCTAssertEqual(seconds, 300)
            XCTAssertEqual(target, "Stretch")
        } else { XCTFail("Expected cooldown interval") }
    }

    func testCircuitWithRoundsWrapsInRepeat() {
        let block = Block(
            label: "Circuit",
            structure: .circuit,
            rounds: 3,
            exercises: [
                Exercise(name: "Burpees", canonicalName: nil, sets: nil, reps: "10", durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, supersetGroup: nil),
                Exercise(name: "Jump Rope", canonicalName: nil, sets: nil, reps: nil, durationSeconds: 60, load: nil, restSeconds: nil, distance: nil, notes: nil, supersetGroup: nil),
            ]
        )

        let intervals = BlockToIntervalConverter.flatten([block])
        XCTAssertEqual(intervals.count, 1) // Single repeat wrapping the circuit
        if case .repeat(let reps, let nested) = intervals[0] {
            XCTAssertEqual(reps, 3)
            XCTAssertEqual(nested.count, 2) // Two exercises, no rest between (none specified)
        } else { XCTFail("Expected repeat interval") }
    }

    func testEmptyBlocksProducesEmptyIntervals() {
        let intervals = BlockToIntervalConverter.flatten([])
        XCTAssertTrue(intervals.isEmpty)
    }

    func testRepsRangeUsesHigherEnd() {
        let block = Block(
            label: nil,
            structure: .straight,
            exercises: [
                Exercise(name: "Curls", canonicalName: nil, sets: 3, reps: "8-12", durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, supersetGroup: nil),
            ]
        )

        let intervals = BlockToIntervalConverter.flatten([block])
        if case .reps(_, let reps, _, _, _, _) = intervals[0] {
            XCTAssertEqual(reps, 12) // Higher end of 8-12
        } else { XCTFail("Expected reps interval") }
    }
}
```

- [ ] **Step 2: Create WorkoutCodableTests**

```swift
// AmakaFlowCompanionTests/WorkoutCodableTests.swift

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutCodableTests: XCTestCase {

    func testDecodeWorkoutWithBlocks() throws {
        let json = """
        {
            "id": "w-123",
            "name": "Full Body",
            "sport": "strength",
            "duration": 2700,
            "blocks": [
                {
                    "label": "Main",
                    "structure": "straight",
                    "rounds": 1,
                    "exercises": [
                        { "name": "Squat", "sets": 3, "reps": "10" }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let workout = try decoder.decode(Workout.self, from: json)

        XCTAssertEqual(workout.id, "w-123")
        XCTAssertEqual(workout.blocks.count, 1)
        XCTAssertEqual(workout.blocks[0].label, "Main")
        XCTAssertEqual(workout.blocks[0].exercises.count, 1)
        XCTAssertEqual(workout.blocks[0].exercises[0].name, "Squat")
        // Computed intervals should work
        XCTAssertFalse(workout.intervals.isEmpty)
    }

    func testDecodeWorkoutWithLegacyIntervals() throws {
        let json = """
        {
            "id": "w-legacy",
            "name": "Old Workout",
            "sport": "strength",
            "duration": 1800,
            "intervals": [
                { "kind": "reps", "sets": 3, "reps": 10, "name": "Push-up" },
                { "kind": "rest", "seconds": 60 }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let workout = try decoder.decode(Workout.self, from: json)

        XCTAssertEqual(workout.id, "w-legacy")
        // Should have been wrapped in a block
        XCTAssertFalse(workout.blocks.isEmpty)
        XCTAssertEqual(workout.blocks[0].exercises[0].name, "Push-up")
    }

    func testDecodeWorkoutWithBothBlocksAndIntervals() throws {
        let json = """
        {
            "id": "w-both",
            "name": "Dual Format",
            "sport": "strength",
            "duration": 1800,
            "blocks": [
                {
                    "label": "Main",
                    "exercises": [{ "name": "Deadlift", "sets": 5, "reps": "5" }]
                }
            ],
            "intervals": [
                { "kind": "reps", "sets": 5, "reps": 5, "name": "Deadlift" }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let workout = try decoder.decode(Workout.self, from: json)

        // Should prefer blocks over intervals
        XCTAssertEqual(workout.blocks.count, 1)
        XCTAssertEqual(workout.blocks[0].exercises[0].name, "Deadlift")
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app/AmakaFlowCompanion && xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AmakaFlowCompanionTests 2>&1 | tail -20`

Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app
git add AmakaFlowCompanionTests/
git commit -m "test(AMA-1409): Add unit tests for BlockToIntervalConverter and Workout Codable"
```

---

## Task 9: Update Fixture Data + Maestro E2E

**Files:**
- Modify: Fixture workout data (wherever UITEST_FIXTURES are defined)
- Modify: `flows/ios/ama-1218-pairing-navigation.yaml` in amakaflow-automation (optional)

- [ ] **Step 1: Find where fixture workouts are defined in the iOS app**

Search for `UITEST_FIXTURES` or `FixtureWorkoutRepository` or `amrap_10min` in the iOS codebase to find where mock workouts are created.

- [ ] **Step 2: Update fixture workouts to include blocks**

Add `blocks` to the fixture workout JSON/data so the detail view renders block structure in test mode.

- [ ] **Step 3: Run Maestro smoke test to verify app still works**

```bash
xcrun simctl shutdown all
xcrun simctl boot "iPhone 17 Pro"
# Install latest build
xcrun simctl install "iPhone 17 Pro" ~/Library/Developer/Xcode/DerivedData/AmakaFlowCompanion-*/Build/Products/Debug-iphonesimulator/AmakaFlowCompanion.app
# Run smoke test
cd /Users/davidmini/.openclaw/workspace/amakaflow-automation
UITEST_AUTH_SECRET="e2e-test-secret-dev-only" UITEST_USER_ID="user_37lZCcU9AJ9b7MX2H71dZ2CuX2u" ~/.maestro/bin/maestro test flows/ios/ama-1218-pairing-navigation.yaml
xcrun simctl shutdown all
```

Expected: All steps pass, screenshots show block-structured workout detail

- [ ] **Step 4: Commit**

```bash
cd /Users/davidmini/.openclaw/workspace/amakaflow-ios-app
git add -A
git commit -m "feat(AMA-1409): Update fixtures with block structure + verify E2E"
```

---

## Summary

| Task | Description | Files |
|------|------------|-------|
| 1 | Exercise model | `Models/Exercise.swift` |
| 2 | Block model | `Models/Block.swift` |
| 3 | BlockToIntervalConverter | `Services/BlockToIntervalConverter.swift` |
| 4 | Update Workout model | `Models/Workout.swift` (modify) |
| 5 | UI components | `Views/Components/BlockSectionView.swift`, `ExerciseRowView.swift` |
| 6 | Update WorkoutDetailView | `Views/WorkoutDetailView.swift` (modify) |
| 7 | Backend API change | `api/routers/workouts.py` (modify) |
| 8 | Unit tests | `Tests/BlockToIntervalConverterTests.swift`, `WorkoutCodableTests.swift` |
| 9 | Fixtures + E2E | Fixture data + Maestro verification |
