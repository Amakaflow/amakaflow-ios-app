# AMA-1409: Block/Exercise/Superset Data Model + UI Rendering

**Date:** 2026-04-02
**Status:** Approved
**Approach:** C — Blocks as primary model, intervals as computed property

## Summary

Add Block/Exercise/Superset support to the iOS app. The backend already stores workouts in block structure — this change brings iOS in line with the web app and Android by receiving and rendering blocks natively. Intervals become a computed property derived from blocks, preserving compatibility with WorkoutKit, Apple Watch, and the workout player.

## Architecture Decision

**Blocks are the primary model. Intervals are derived.**

This matches the backend's own pattern: it stores blocks internally and converts to intervals for device export. The iOS app will do the same — store blocks, compute intervals on demand. New features (programs, analytics, AI coach) read blocks. Device integrations (WorkoutKit, Watch) read intervals. They stay in sync because intervals are always computed from blocks.

## Data Models

### New: Block (AmakaFlow/Models/Block.swift)

```swift
struct Block: Codable, Hashable, Identifiable {
    var id: String { label ?? UUID().uuidString }
    let label: String?           // "Warm-up", "Big Lifts", "Superset Cluster 1"
    let structure: BlockStructure // straight, superset, circuit, amrap, emom, tabata
    let rounds: Int              // default 1
    let exercises: [Exercise]
    let restBetweenSeconds: Int?

    enum BlockStructure: String, Codable {
        case straight
        case superset
        case circuit
        case amrap
        case emom
        case tabata
    }
}
```

### New: Exercise (AmakaFlow/Models/Exercise.swift)

```swift
struct Exercise: Codable, Hashable, Identifiable {
    var id: String { name + String(sets ?? 0) }
    let name: String
    let canonicalName: String?
    let sets: Int?
    let reps: String?            // Supports "8-10" ranges
    let durationSeconds: Int?
    let load: ExerciseLoad?
    let restSeconds: Int?
    let distance: Double?
    let notes: String?
    let supersetGroup: Int?      // Groups exercises within a block
}

struct ExerciseLoad: Codable, Hashable {
    let value: Double
    let unit: String             // "kg", "lbs", "bodyweight"
}
```

### Updated: Workout (AmakaFlow/Models/Workout.swift)

```swift
struct Workout: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let sport: WorkoutSport
    let duration: Int
    let blocks: [Block]              // PRIMARY — stored
    let description: String?
    let source: WorkoutSource
    let sourceUrl: String?

    // COMPUTED — derived from blocks, never stored
    var intervals: [WorkoutInterval] {
        BlockToIntervalConverter.flatten(blocks)
    }

    // Backward compat: exercise count from blocks
    var exerciseCount: Int {
        blocks.reduce(0) { $0 + $1.exercises.count }
    }

    var blockCount: Int {
        blocks.count
    }
}
```

### Codable Strategy

Custom decoder for backward compatibility:

```
1. Try to decode `blocks` from JSON
2. If blocks exist → use them (new format)
3. If no blocks → decode `intervals`, wrap in single Block(label: "Workout", structure: .straight)
4. This ensures old cached workouts and old API responses still decode
```

### New: BlockToIntervalConverter (AmakaFlow/Services/BlockToIntervalConverter.swift)

Converts blocks → flat WorkoutInterval array. Logic ported from backend's `to_workoutkit()`:

- Straight block: each exercise → reps/time interval, insert rest between exercises
- Superset block: group exercises by supersetGroup, wrap in `.repeat(reps: rounds)`
- Circuit block: all exercises in sequence, wrap in `.repeat(reps: rounds)`
- AMRAP/EMOM: time-capped container with exercises inside
- Warmup/cooldown blocks: use `.warmup()` / `.cooldown()` interval types

## API Changes

### Backend (mapper-api)

Update `GET /workouts/incoming` response to include blocks:

```python
transformed.append({
    "id": workout_record.get("id"),
    "name": title,
    "sport": sport,
    "duration": total_duration,
    "source": "amakaflow",
    "blocks": workout_data.get("blocks", []),  # NEW — raw blocks
    "intervals": intervals,                     # KEEP — for old iOS versions
})
```

One-line change. The blocks data is already in `workout_data` — just pass it through.

### iOS APIService

Update Workout decoder to parse blocks. Falls back to intervals if blocks missing (backward compat handled by custom decoder above).

## UI Changes

### WorkoutDetailView

Replace flat interval list with block-structured rendering:

```
[Block Header: "Warm-up"]
  1. Jumping Jacks — 30 reps
  2. Arm Circles — 30 sec

[Block Header: "Big Lifts — 3 sets" (badge: Straight)]
  1. Squat — 3x8-10 @ 100kg
  2. Bench Press — 3x8-10 @ 80kg

[Block Header: "Superset Cluster 1" (badge: Superset)]
  ┃ 1. Landmine Press — 3x8-10
  ┃ 2. Seal Row — 3x10-12
  (90s rest between sets)

[Block Header: "Cooldown"]
  1. Static Stretch — 5 min
```

Components:
- `BlockSectionView` — renders block header with label + structure badge + rounds
- `ExerciseRowView` — renders exercise name, sets x reps, load, rest
- `SupersetGroupView` — vertical connector bar for superset exercises

### WorkoutsView (list)

Update WorkoutCard to show:
- Exercise count from blocks: "6 exercises"
- Block count: "3 blocks"
- No other changes to list behavior

### WorkoutPlayerView — NO CHANGES

Still reads `.intervals` computed property. The player, WorkoutKit converter, and Apple Watch sync all continue working unchanged.

## Testing

### Unit Tests
- `BlockToIntervalConverterTests`: straight blocks, supersets, circuits, AMRAP, EMOM, mixed, empty blocks
- `WorkoutCodableTests`: decode blocks format, decode legacy intervals format, decode mixed, encode roundtrip
- `BlockModelTests`: exercise count, block count, computed intervals consistency

### Maestro E2E
- Update fixture data to include blocks
- Verify WorkoutDetailView shows block headers and exercises
- Verify workout player still works (intervals computed correctly)

## Scope Boundaries

**In scope:**
- Block, Exercise, ExerciseLoad models
- BlockToIntervalConverter
- Updated Workout model with computed intervals
- WorkoutDetailView block rendering
- WorkoutCard exercise count
- Backend: add blocks to /workouts/incoming response
- Backward compatibility for old format

**Out of scope (future tickets):**
- Block editing in iOS (web-only for now)
- Block context in player UI (AMA-1410+)
- Programs that reference blocks
- Analytics that track per-exercise volume
