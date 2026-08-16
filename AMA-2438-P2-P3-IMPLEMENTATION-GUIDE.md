# AMA-2438 P2-P3 Implementation Guide

## Status

**✅ Complete: P0-P1** (2 commits pushed)
**⏳ Remaining: P2-P3**

This document provides the exact steps to complete P2 (D2 + D3) and P3 (D4 codec).

## P2: D2 Declared Membership + D3 Derived Labels

### Step 1: Add new types to EditorV2Models.swift

```swift
/// AMA-2438 D2: Canvas row — either a group block or a loose exercise.
enum EditorV2Row: Equatable, Sendable {
    case group(String)      // GroupKey
    case loose(String)      // ExerciseID
    
    var id: String {
        switch self {
        case .group(let key): return key
        case .loose(let id): return id
        }
    }
}
```

### Step 2: Update EditorV2Group

Add these fields:
```swift
struct EditorV2Group {
    // ... existing fields ...
    var letter: String?         // D3: stable identity (A, B, C)
    var memberIDs: [String]     // D2: ordered member IDs
    
    // D3: Pure function for display name
    func displayName(memberCount: Int) -> String {
        let autoNames: Set<String> = ["Superset", "Tri-set", "Tri-sets", "Giant set"]
        guard autoNames.contains(name) || name.isEmpty else {
            return name  // Custom names pass through
        }
        
        if type == .superset {
            let base: String
            if memberCount >= 4 {
                base = "Giant set"
            } else if memberCount >= 3 {
                base = "Tri-set"
            } else {
                base = "Superset"
            }
            
            if let letter = letter, !letter.isEmpty {
                return "\(base) \(letter)"
            }
            return base
        }
        
        return type.label
    }
}
```

### Step 3: Update EditorV2Session

```swift
struct EditorV2Session {
    var title: String
    var order: [EditorV2Row]                    // D2: canvas owns order
    var groups: [String: EditorV2Group]
    var exercises: [String: EditorV2Exercise]   // D2: keyed dict, not array
    // ... rest unchanged ...
    
    // D2: runs projection becomes trivial
    var runs: [EditorV2Run] {
        var result: [EditorV2Run] = []
        for row in order {
            switch row {
            case .group(let key):
                guard let group = groups[key] else { continue }
                let members = group.memberIDs.compactMap { exercises[$0] }
                guard !members.isEmpty else { continue }
                result.append(EditorV2Run(id: key, groupKey: key, exercises: members))
            case .loose(let id):
                guard let exercise = exercises[id] else { continue }
                result.append(EditorV2Run(id: id, groupKey: nil, exercises: [exercise]))
            }
        }
        return result
    }
}
```

### Step 4: Rewrite all EditorV2Command implementations

Each command must now:
- Work with `order: [EditorV2Row]`
- Update `groups[].memberIDs` instead of `exercise.groupKey`
- Access `exercises[id]` dict instead of array index

Example - addExercises:
```swift
case .addExercises(let names, let into):
    for name in names {
        let ex = EditorV2Exercise(...)
        exercises[ex.id] = ex
        
        if let groupKey = into ?? formatGroupKey {
            groups[groupKey]?.memberIDs.append(ex.id)
            // Order already has .group(groupKey) or add it
            if !order.contains(where: { if case .group(groupKey) = $0 { return true }; return false }) {
                order.append(.group(groupKey))
            }
        } else {
            order.append(.loose(ex.id))
        }
    }
```

### Step 5: Update normalize()

```swift
private mutating func normalize() {
    repairBrokenGroups()    // Now checks memberIDs contiguity in order
    pruneEmptyGroups()      // Removes groups with memberIDs.isEmpty
    refreshSupersetLabels() // Now uses displayName(memberCount:)
}
```

### Step 6: Update validate() for D2

```swift
private func validate() -> ApplyResult {
    // I1: Partition invariant - every exercise in exactly one place
    var seen = Set<String>()
    for row in order {
        switch row {
        case .group(let key):
            guard let group = groups[key] else { return .rejected(.unresolvedReferences) }
            for memberID in group.memberIDs {
                guard !seen.contains(memberID) else { return .rejected(.duplicateIDs) }
                guard exercises[memberID] != nil else { return .rejected(.unresolvedReferences) }
                seen.insert(memberID)
            }
        case .loose(let id):
            guard !seen.contains(id) else { return .rejected(.duplicateIDs) }
            guard exercises[id] != nil else { return .rejected(.unresolvedReferences) }
            seen.insert(id)
        }
    }
    
    // All exercises must be in order
    for id in exercises.keys {
        guard seen.contains(id) else { return .rejected(.invalidGroupMembership) }
    }
    
    // ... rest of invariants ...
}
```

### Step 7: Migration from old model

Add to EditorV2Session+Persistence.swift:

```swift
static func from(title: String, blocks: [DDEditorBlockDraft]) -> EditorV2Session {
    var order: [EditorV2Row] = []
    var groups: [String: EditorV2Group] = [:]
    var exercises: [String: EditorV2Exercise] = [:]
    
    for block in blocks {
        if let groupType = EditorV2GroupType.from(dd: block.structure) {
            let key = block.id
            var memberIDs: [String] = []
            
            for exercise in block.exercises {
                let ex = exercise.asEditorV2(groupKey: nil)  // No back-pointer anymore
                exercises[ex.id] = ex
                memberIDs.append(ex.id)
            }
            
            groups[key] = EditorV2Group(
                id: key,
                type: groupType,
                name: block.label,
                memberIDs: memberIDs,
                // ... config ...
            )
            order.append(.group(key))
        } else {
            for exercise in block.exercises {
                let ex = exercise.asEditorV2(groupKey: nil)
                exercises[ex.id] = ex
                order.append(.loose(ex.id))
            }
        }
    }
    
    return EditorV2Session(title: title, order: order, groups: groups, exercises: exercises)
}
```

### Step 8: Update all view code

Views that iterate `session.exercises` must change to iterate `session.runs` or use the exercises dict. The `runs` projection handles the display logic.

### Step 9: Remove EditorV2Exercise.groupKey

Once all code uses D2, delete the `groupKey` field from `EditorV2Exercise`. It's dead.

### Step 10: Update tests

The expected-fail tests in EditorV2CommandTests should now pass:
- Remove `XCTExpectFailure` from the 5 audit regression tests
- They should all be green with D2+D3

## P3: D4 StructureCodec + BlockStructure Widening

### Step 1: Widen BlockStructure enum

In Block.swift:
```swift
enum BlockStructure: String, Codable, CaseIterable {
    case straight, superset, circuit, amrap, emom, tabata
    case timedCircuit = "timed_circuit"
    case warmup          // NEW
    case cooldown        // NEW  
    case fortime         // NEW (was mapped to straight)
}

struct Block {
    // ... existing fields ...
    let timeCapSeconds: Int?    // NEW - for AMRAP/for-time cap
    
    enum CodingKeys: String, CodingKey {
        // ... existing ...
        case timeCapSeconds = "time_cap_sec"
    }
}
```

### Step 2: Update WorkoutLibraryDetailStore.blockStructure

```swift
static func blockStructure(from type: String?) -> BlockStructure {
    switch type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "warmup": return .warmup           // No longer → .circuit
    case "cooldown": return .cooldown       // No longer → .straight
    case "for-time", "fortime": return .fortime  // No longer → .straight
    // ... rest unchanged ...
    }
}
```

### Step 3: Create StructureCodec

New file: AmakaFlow/Models/EditorV2Codec.swift

```swift
enum StructureCodec {
    static func encode(_ session: EditorV2Session) -> [SocialImportBlock] {
        var blocks: [SocialImportBlock] = []
        
        for row in session.order {
            switch row {
            case .group(let key):
                guard let group = session.groups[key] else { continue }
                let members = group.memberIDs.compactMap { session.exercises[$0] }
                guard !members.isEmpty else { continue }
                
                // Encode with timeCapSec for AMRAP/fortime
                let timeCapSec: Int? = {
                    if group.type == .amrap || group.type == .fortime {
                        return (group.config.capMinutes ?? 0) * 60
                    }
                    return nil
                }()
                
                blocks.append(SocialImportBlock(
                    label: group.displayName(memberCount: members.count),
                    rounds: group.config.rounds ?? 1,
                    exercises: members.map(\.asSocialImportExercise),
                    type: group.type.structureBlockType.rawValue,
                    restSec: group.config.restSeconds,
                    timeCapSec: timeCapSec,
                    structureSource: group.structureSource.rawValue,
                    enrichmentKind: group.enrichmentKind?.rawValue
                ))
                
            case .loose(let id):
                guard let exercise = session.exercises[id] else { continue }
                blocks.append(SocialImportBlock(
                    label: nil,
                    rounds: 1,
                    exercises: [exercise.asSocialImportExercise],
                    type: StructureBlockType.sets.rawValue,
                    restSec: nil,
                    structureSource: StructureSource.userConfirmed.rawValue
                ))
            }
        }
        
        return blocks
    }
    
    static func decode(_ blocks: [SocialImportBlock]) -> EditorV2Session {
        // Mirror of from(title:blocks:) but using SocialImportBlock directly
        // ...
    }
}
```

### Step 4: Update save path

In EditorV2Session+Persistence.swift:
```swift
func toSocialImportBlocks() -> [SocialImportBlock] {
    return StructureCodec.encode(self)
}
```

### Step 5: Update reload path

In WorkoutLibraryDetailStore.swift, change reload to use SocialImportBlock:
```swift
static func detailWorkout(saved: Workout, request: WorkoutSaveRequest) -> Workout {
    let blocks: [Block]
    if let requestBlocks = request.blocks, !requestBlocks.isEmpty {
        // Use request.blocks (SocialImportBlock) as source of truth
        blocks = requestBlocks.map { socialBlock in
            Block(
                label: socialBlock.label,
                structure: blockStructure(from: socialBlock.type),
                rounds: socialBlock.rounds,
                exercises: socialBlock.exercises.map { $0.toExercise() },
                restBetweenSeconds: socialBlock.restSec,
                timeCapSeconds: socialBlock.timeCapSec  // NEW
            )
        }
    }
    // ...
}
```

### Step 6: Add round-trip law tests

New file: EditorV2CodecTests.swift

```swift
func testRoundTripLaw_allGroupTypes() {
    for groupType in EditorV2GroupType.allCases {
        let session = makeSession(with: groupType)
        let encoded = StructureCodec.encode(session)
        let decoded = StructureCodec.decode(encoded)
        let normalized = normalize(decoded)
        
        XCTAssertEqual(decoded, normalized, "Round-trip failed for \(groupType)")
    }
}

func testWarmupSurvivesReload() {
    var session = EditorV2Session()
    // Add warmup group
    let warmupKey = "w1"
    session.groups[warmupKey] = EditorV2Group(id: warmupKey, type: .warmup)
    // ...
    
    let encoded = StructureCodec.encode(session)
    let decoded = StructureCodec.decode(encoded)
    
    XCTAssertTrue(decoded.groups.values.contains { $0.type == .warmup })
}
```

### Step 7: Register new files in pbxproj

Follow the pattern from P0-P1 commits to add EditorV2Codec.swift and EditorV2CodecTests.swift.

## Testing

After P2-P3 complete:

1. All 5 expected-fail tests should pass (remove XCTExpectFailure)
2. Property-based tests should stay green (300 sequences)
3. All existing EditorV2Tests should pass
4. New round-trip law tests should pass
5. CI pr-ios-tests.yml should be green

## Files Changed Summary

### P2 (D2 + D3)
- EditorV2Models.swift (add Row, update Group)
- EditorV2Session.swift (order + exercises dict + new runs)
- EditorV2Command.swift (rewrite all applyInternal cases)
- EditorV2Session+Persistence.swift (update from() migration)
- All view files using session.exercises (iterate runs instead)

### P3 (D4)
- Block.swift (widen BlockStructure, add timeCapSeconds)
- EditorV2Codec.swift (NEW - encode/decode with round-trip law)
- EditorV2Session+Persistence.swift (use StructureCodec)
- WorkoutLibraryDetailStore.swift (update blockStructure mapping, use timeCapSeconds)
- EditorV2CodecTests.swift (NEW - round-trip law tests)

## Estimated Effort

- P2: 3-4 hours (structural refactoring)
- P3: 1-2 hours (codec + widening)
- Testing/debugging: 1-2 hours

Total: 5-8 hours for complete P2-P3 implementation.
